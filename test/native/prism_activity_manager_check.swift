// ActivityKit test double for running the production manager on macOS.
import Foundation

protocol ActivityAttributes { associatedtype ContentState: Codable, Hashable }
struct ActivityContent<State> { let state: State; let staleDate: Date? }
enum ActivityState { case active, stale, ended, dismissed }
enum ActivityUIDismissalPolicy { case immediate; case after(Date) }
enum PushType { case token }
struct ActivityAuthorizationInfo { var areActivitiesEnabled = true }
@MainActor var testActivities: [Any] = []
@MainActor final class Activity<Attributes: ActivityAttributes> {
  let id = UUID().uuidString
  let attributes: Attributes
  var content: ActivityContent<Attributes.ContentState>
  var activityState = ActivityState.active
  var pushToken: Data? = nil
  var pushTokenUpdates: AsyncStream<Data> { AsyncStream { $0.finish() } }
  var activityStateUpdates: AsyncStream<ActivityState> { AsyncStream { $0.finish() } }
  static var activities: [Activity] { testActivities.compactMap { $0 as? Activity } }
  static var activityUpdates: AsyncStream<Activity> { AsyncStream { $0.finish() } }
  static var pushToStartToken: Data? { nil }
  static var pushToStartTokenUpdates: AsyncStream<Data> { AsyncStream { $0.finish() } }
  init(attributes: Attributes, content: ActivityContent<Attributes.ContentState>) {
    self.attributes = attributes; self.content = content
  }
  static func request(attributes: Attributes, content: ActivityContent<Attributes.ContentState>, pushType: PushType) throws -> Activity {
    let activity = Activity(attributes: attributes, content: content)
    testActivities.append(activity)
    return activity
  }
  func update(_ content: ActivityContent<Attributes.ContentState>) async { self.content = content }
  func end(_ content: ActivityContent<Attributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy) async {
    if let content { self.content = content }
    activityState = .ended
  }
}
final class PrismAPI {
  static let shared = PrismAPI()
  static let clientId = "client"
  let baseURL = URL(string: "https://test.example")!
  var snapshot: [String: Any] = [:]
  var fail = false
  var reads = 0
  var unregistered = [String]()
  var startUnregistered = false
  func atOrigin(_ origin: URL) -> PrismAPI { self }
  func request<T: Decodable>(_ path: String) async throws -> T {
    reads += 1
    if fail { throw URLError(.notConnectedToInternet) }
    return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: snapshot))
  }
  func registerStartToken(clientId: String, token: String) async throws {}
  func unregisterStartToken(clientId: String) async throws { startUnregistered = true }
  func registerLiveActivity(shopCode: String, activityId: String, token: String, sessionId: String?, attributes: [String: Any]) async throws {}
  func unregisterLiveActivity(shopCode: String, activityId: String) async throws { unregistered.append(activityId) }
}

@main enum ManagerCheck {
  @MainActor static func main() async throws {
    let api = PrismAPI.shared
    let manager = StoreVisitLiveActivityManager.shared
    let bill = StoreVisitAttributes.Bill(amountCents: 600, planLabel: "Plan", asOfUnix: 100)
    let activity = try Activity<StoreVisitAttributes>.request(
      attributes: .init(sessionId: "visit", shopCode: "shop", shopName: "Shop", origin: api.baseURL.absoluteString),
      content: .init(state: .init(phase: "active", startedAtUnix: 10, endedAtUnix: nil, bill: bill), staleDate: nil), pushType: .token)
    // Ordinary foreground refresh must not fetch or replace an already fresh bill.
    await manager.reconcile(session: .init(id: "visit", startedAt: "2026-01-01T00:00:00Z"), shopCode: "shop", shopName: "Shop", origin: api.baseURL, api: api)
    precondition(api.reads == 0 && activity.content.state.bill?.amountCents == 600)
    // A missing active session plus a network failure is not proof of payment.
    api.fail = true
    await manager.reconcile(session: nil, shopCode: "shop", shopName: "Shop", origin: api.baseURL, api: api)
    precondition(activity.activityState == .active && api.unregistered.isEmpty)
    api.fail = false
    api.snapshot = ["phase": "active", "startedAtUnix": 10, "endedAtUnix": 200,
      "bill": ["amountCents": 900, "planLabel": "", "asOfUnix": 210]]
    await manager.reconcile(session: nil, shopCode: "shop", shopName: "Shop", origin: api.baseURL, api: api)
    precondition(activity.activityState == .active && activity.content.state.endedAtUnix == 200)
    precondition(activity.content.state.bill?.amountCents == 900 && api.unregistered.isEmpty)
    api.snapshot = ["phase": "ended", "startedAtUnix": 10, "endedAtUnix": 200,
      "bill": ["amountCents": 800, "planLabel": "", "asOfUnix": 220]]
    await manager.reconcile(session: nil, shopCode: "shop", shopName: "Shop", origin: api.baseURL, api: api)
    precondition(activity.activityState == .ended && activity.content.state.endedAtUnix == 200)
    precondition(activity.content.state.bill?.amountCents == 800 && api.unregistered == [activity.id])
    // Both direct checkout and a matching latest receipt avoid a second bill request.
    let receipt = try JSONDecoder().decode(PrismCheckoutResult.self, from: Data(#"{"playerSettlement":{"total":12.34,"settledAt":"2026-09-12T02:00:00Z"},"chargeItems":[],"adjustments":[],"settlements":[{"settlement":{"sessionId":"visit","startedAt":"2026-09-12T00:00:00Z","endedAt":"2026-09-12T01:00:00Z"}}]}"#.utf8))
    let direct = try Activity<StoreVisitAttributes>.request(attributes: activity.attributes, content: activity.content, pushType: .token)
    let reads = api.reads
    await manager.finishCheckout(receipt: receipt, shopCode: "shop", api: api)
    precondition(direct.activityState == .ended && direct.content.state.bill?.amountCents == 1234 && api.reads == reads)
    precondition(direct.content.state.endedAtUnix == prismParsedDate("2026-09-12T01:00:00Z")!.timeIntervalSince1970)
    let reopened = try Activity<StoreVisitAttributes>.request(attributes: activity.attributes, content: activity.content, pushType: .token)
    await manager.reconcile(session: nil, shopCode: "shop", shopName: "Shop", origin: api.baseURL, api: api, receipt: receipt)
    precondition(reopened.activityState == .ended && api.reads == reads)
    let unmatched = try Activity<StoreVisitAttributes>.request(
      attributes: .init(sessionId: "unmatched", shopCode: "shop", shopName: "Shop", origin: api.baseURL.absoluteString),
      content: activity.content, pushType: .token)
    api.fail = true
    await manager.reconcile(session: nil, shopCode: "shop", shopName: "Shop", origin: api.baseURL, api: api, receipt: receipt)
    precondition(unmatched.activityState == .active && api.reads == reads + 1)
    api.fail = false
    let other = try Activity<StoreVisitAttributes>.request(
      attributes: .init(sessionId: "other", shopCode: "shop", shopName: "Other", origin: "https://other.example"),
      content: activity.content, pushType: .token)
    let current = try Activity<StoreVisitAttributes>.request(
      attributes: activity.attributes, content: activity.content, pushType: .token)
    await manager.unregisterAllPushTokens(api: api)
    precondition(api.startUnregistered && current.activityState == .ended)
    precondition(other.activityState == .active && !api.unregistered.contains(other.id))
    print("Live Activity recovery, final receipt, and logout checks passed")
  }
}
