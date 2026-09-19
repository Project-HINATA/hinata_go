import ActivityKit
import Foundation
import OSLog

@MainActor
final class StoreVisitLiveActivityManager {
  static let shared = StoreVisitLiveActivityManager()

  /// Written when an activity starts, read when a tap arrives without a URL of its own.
  /// Shared with `PrismURLBridge`, which runs in the app rather than this manager.
  static let lastLinkKey = "prism.last-link"

  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PRiSM", category: "LiveActivity")

  /// Push-token observers, keyed by activity id, so a token rotation can be reported
  /// without stacking a second listener on the same activity.
  private var tokenTasks: [String: Task<Void, Never>] = [:]

  private init() {}

  /// `origin` is the HTTPS deployment origin; callers pass nil for non-HTTPS debug origins,
  /// which leaves the activity without a tap target instead of pointing it at a bad host.
  func reconcile(session: PrismSummary.Session?, shopCode: String, shopName: String, origin: URL?) async {
    let activities = Activity<StoreVisitAttributes>.activities
    let originValue = origin?.absoluteString
    if let session {
      if activities.contains(where: { $0.attributes.sessionId == session.id }) {
        // Already showing this visit. A remote push may have refreshed it in the
        // meantime, and re-requesting would restart the timer on the device.
        return
      }

      for activity in activities where activity.attributes.shopCode == shopCode {
        await end(activity, startedAt: activity.content.state.startedAtUnix, endedAt: Date().timeIntervalSince1970)
      }

      guard let startedAt = prismParsedDate(session.startedAt) else {
        logger.error("Cannot start Live Activity: invalid session startedAt")
        return
      }
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        logger.notice("Cannot start Live Activity: activities are disabled")
        return
      }
      do {
        // `.token` is what makes the activity updatable by the server while the app is
        // suspended or killed, which is the whole point of this feature.
        let activity = try Activity.request(
          attributes: StoreVisitAttributes(sessionId: session.id, shopCode: shopCode, shopName: shopName, origin: originValue),
          content: ActivityContent(
            state: .init(phase: "active", startedAtUnix: startedAt.timeIntervalSince1970, endedAtUnix: nil),
            staleDate: nil
          ),
          pushType: .token
        )
        observePushToken(for: activity, shopCode: shopCode, sessionId: session.id, shopName: shopName, origin: originValue)
        // Remember the tap target in case the activity is delivered without one later (a
        // non-HTTPS origin, or an activity created before this field existed).
        if let target = StoreVisitAttributes(sessionId: session.id, shopCode: shopCode, shopName: shopName, origin: originValue).shopURL {
          UserDefaults.standard.set(target.absoluteString, forKey: Self.lastLinkKey)
        }
      } catch {
        // Live Activities are optional and must not affect billing.
        logger.error("Failed to start Live Activity: \(String(describing: error), privacy: .public)")
      }
    } else {
      for activity in activities where activity.attributes.shopCode == shopCode {
        await end(activity, startedAt: activity.content.state.startedAtUnix, endedAt: Date().timeIntervalSince1970)
      }
    }
  }

  /// Retires every activity's token, across shops. Used on sign-out: a shop-scoped sweep
  /// would leave other shops' activities still addressable by the server.
  func unregisterAllPushTokens() async {
    for activity in Activity<StoreVisitAttributes>.activities {
      await reportUnregister(activity)
    }
  }

  /// Reports the token now, then again whenever ActivityKit rotates it (reinstall,
  /// re-signing, or a system-side change). Without this a rotated token would silently
  /// stop delivering.
  private func observePushToken(
    for activity: Activity<StoreVisitAttributes>,
    shopCode: String,
    sessionId: String,
    shopName: String,
    origin: String?
  ) {
    tokenTasks[activity.id]?.cancel()
    tokenTasks[activity.id] = Task { [weak self] in
      for await tokenData in activity.pushTokenUpdates {
        guard let self else { return }
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        await self.reportRegister(
          token: token,
          activity: activity,
          shopCode: shopCode,
          sessionId: sessionId,
          shopName: shopName,
          origin: origin
        )
      }
    }
  }

  private func reportRegister(
    token: String,
    activity: Activity<StoreVisitAttributes>,
    shopCode: String,
    sessionId: String,
    shopName: String,
    origin: String?
  ) async {
    var attributes: [String: Any] = [
      "sessionId": sessionId,
      "shopCode": shopCode,
      "shopName": shopName,
    ]
    if let origin { attributes["origin"] = origin }
    do {
      try await PrismAPI.shared.registerLiveActivity(
        shopCode: shopCode,
        activityId: activity.id,
        token: token,
        sessionId: sessionId,
        attributes: attributes
      )
    } catch {
      // Registration is best-effort: the activity still works locally, and the next token
      // rotation reports again.
      logger.error("Failed to register Live Activity push token: \(String(describing: error), privacy: .public)")
    }
  }

  private func reportUnregister(_ activity: Activity<StoreVisitAttributes>) async {
    tokenTasks[activity.id]?.cancel()
    tokenTasks[activity.id] = nil
    do {
      try await PrismAPI.shared.unregisterLiveActivity(shopCode: activity.attributes.shopCode, activityId: activity.id)
    } catch {
      logger.error("Failed to unregister Live Activity push token: \(String(describing: error), privacy: .public)")
    }
  }

  private func end(_ activity: Activity<StoreVisitAttributes>, startedAt: Double, endedAt: Double) async {
    let state = StoreVisitAttributes.ContentState(phase: "ended", startedAtUnix: startedAt, endedAtUnix: endedAt)
    await reportUnregister(activity)
    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
  }
}
