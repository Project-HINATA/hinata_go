import ActivityKit
import Foundation

@MainActor
final class StoreVisitLiveActivityManager {
  static let shared = StoreVisitLiveActivityManager()

  private var observedActivityIds = Set<String>()

  private init() {}

  func reconcile(session: PrismSummary.Session?, shopCode: String, shopName: String, api: PrismAPI) async {
    let activities = Activity<StoreVisitAttributes>.activities
    if let session {
      if let existing = activities.first(where: { $0.attributes.sessionId == session.id }) {
        await registerToken(for: existing, shopCode: shopCode, api: api)
        return
      }

      for activity in activities where activity.attributes.shopCode == shopCode {
        await end(activity, startedAt: activity.content.state.startedAtUnix, endedAt: Date().timeIntervalSince1970)
      }

      guard let startedAt = ISO8601DateFormatter().date(from: session.startedAt) else { return }
      do {
        let activity = try Activity.request(
          attributes: StoreVisitAttributes(sessionId: session.id, shopCode: shopCode, shopName: shopName),
          content: ActivityContent(
            state: .init(phase: "active", startedAtUnix: startedAt.timeIntervalSince1970, endedAtUnix: nil),
            staleDate: nil
          ),
          pushType: .token
        )
        await registerToken(for: activity, shopCode: shopCode, api: api)
      } catch {
        // Live Activities are optional and must not affect billing.
      }
    } else {
      for activity in activities where activity.attributes.shopCode == shopCode {
        await end(activity, startedAt: activity.content.state.startedAtUnix, endedAt: Date().timeIntervalSince1970)
      }
    }
  }

  private func registerToken(for activity: Activity<StoreVisitAttributes>, shopCode: String, api: PrismAPI) async {
    guard observedActivityIds.insert(activity.id).inserted else { return }
    Task { [weak self] in
      guard let self else { return }
      if let token = activity.pushToken {
        await self.upload(token: token, activity: activity, shopCode: shopCode, api: api)
      }
      for await token in activity.pushTokenUpdates {
        await self.upload(token: token, activity: activity, shopCode: shopCode, api: api)
      }
    }
  }

  private func upload(token: Data, activity: Activity<StoreVisitAttributes>, shopCode: String, api: PrismAPI) async {
    do {
      try await api.registerLiveActivity(
        shopCode: shopCode,
        sessionId: activity.attributes.sessionId,
        activityId: activity.id,
        pushToken: token.liveActivityHexString
      )
    } catch {
      // Registration is best-effort until the server endpoint is deployed.
    }
  }

  private func end(_ activity: Activity<StoreVisitAttributes>, startedAt: Double, endedAt: Double) async {
    observedActivityIds.remove(activity.id)
    let state = StoreVisitAttributes.ContentState(phase: "ended", startedAtUnix: startedAt, endedAtUnix: endedAt)
    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
  }
}
