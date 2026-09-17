import ActivityKit
import Foundation
import OSLog

@MainActor
final class StoreVisitLiveActivityManager {
  static let shared = StoreVisitLiveActivityManager()

  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PRiSM", category: "LiveActivity")

  private init() {}

  /// `origin` is the HTTPS deployment origin; callers pass nil for non-HTTPS debug origins,
  /// which leaves the activity without a tap target instead of pointing it at a bad host.
  func reconcile(session: PrismSummary.Session?, shopCode: String, shopName: String, origin: URL?) async {
    let activities = Activity<StoreVisitAttributes>.activities
    let originValue = origin?.absoluteString
    if let session {
      if activities.contains(where: { $0.attributes.sessionId == session.id }) {
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
        _ = try Activity.request(
          attributes: StoreVisitAttributes(sessionId: session.id, shopCode: shopCode, shopName: shopName, origin: originValue),
          content: ActivityContent(
            state: .init(phase: "active", startedAtUnix: startedAt.timeIntervalSince1970, endedAtUnix: nil),
            staleDate: nil
          ),
          pushType: nil
        )
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

  private func end(_ activity: Activity<StoreVisitAttributes>, startedAt: Double, endedAt: Double) async {
    let state = StoreVisitAttributes.ContentState(phase: "ended", startedAtUnix: startedAt, endedAtUnix: endedAt)
    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
  }
}
