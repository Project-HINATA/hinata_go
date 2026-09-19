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

  /// Activity-level observers
  private var activityUpdatesTask: Task<Void, Never>?
  private var stateTasks: [String: Task<Void, Never>] = [:]

  /// Push-token observers, keyed by activity id, so a token rotation can be reported
  /// without stacking a second listener on the same activity.
  private var tokenTasks: [String: Task<Void, Never>] = [:]
  private var registeredTokens: [String: String] = [:]
  private var registeredTokenOrigins: [String: String] = [:]

  /// Push-to-start observer and registration state
  private var startTokenTask: Task<Void, Never>?
  private var registeredStartToken: String?
  private var registeredStartOrigin: String?

  private init() {}

  /// Starts global activity tracking across the app lifecycle.
  /// Hooks activityUpdates and recovers existing activities.
  func startGlobalActivityTracking(fallbackAPI: PrismAPI = .shared) {
    recoverExistingActivities(api: fallbackAPI)

    guard activityUpdatesTask == nil else { return }
    activityUpdatesTask = Task { [weak self] in
      for await activity in Activity<StoreVisitAttributes>.activityUpdates {
        guard let self else { return }
        self.ensureTokenTracking(for: activity, fallbackAPI: fallbackAPI)
      }
    }
  }

  /// Starts or maintains push-to-start token tracking against the provided deployment API.
  /// Gracefully skips if iOS version is below 17.2 or Live Activities are disabled.
  func startPushToStartTracking(api: PrismAPI) {
    if #available(iOS 17.2, *) {
      guard ActivityAuthorizationInfo().areActivitiesEnabled else {
        logger.notice("Live Activities are disabled; skipping push-to-start registration")
        return
      }
      let clientId = PrismAPI.clientId
      if let currentToken = Activity<StoreVisitAttributes>.pushToStartToken {
        let token = currentToken.map { String(format: "%02x", $0) }.joined()
        Task { [weak self] in
          await self?.reportStartToken(token: token, clientId: clientId, api: api)
        }
      }
      startTokenTask?.cancel()
      startTokenTask = Task { [weak self] in
        for await tokenData in Activity<StoreVisitAttributes>.pushToStartTokenUpdates {
          guard let self else { return }
          let token = tokenData.map { String(format: "%02x", $0) }.joined()
          await self.reportStartToken(token: token, clientId: clientId, api: api)
        }
      }
    }
  }

  /// Cancels push-to-start listening and unregisters the start token on sign-out.
  func stopPushToStartTracking(api: PrismAPI) {
    startTokenTask?.cancel()
    startTokenTask = nil
    registeredStartToken = nil
    registeredStartOrigin = nil
    let clientId = PrismAPI.clientId
    Task { [weak self] in
      guard let self else { return }
      do {
        try await api.unregisterStartToken(clientId: clientId)
      } catch {
        self.logger.error("Failed to unregister push-to-start token: \(String(describing: error), privacy: .public)")
      }
    }
  }

  /// Reconciles the local Live Activity state with the server session.
  /// All network calls use the explicit origin-scoped `api` instance.
  func reconcile(
    session: PrismSummary.Session?,
    shopCode: String,
    shopName: String,
    origin: URL?,
    api: PrismAPI
  ) async {
    let activities = Activity<StoreVisitAttributes>.activities
    let originValue = origin?.absoluteString

    // Strategy 3: Deduplicate any duplicate Live Activities with the same sessionId on device
    var seenSessions = Set<String>()
    for activity in activities {
      let sessId = activity.attributes.sessionId
      if seenSessions.contains(sessId) {
        logger.notice("Ending duplicate Live Activity for session \(sessId, privacy: .public)")
        await reportUnregister(activity, api: api)
        await activity.end(nil, dismissalPolicy: .immediate)
      } else {
        seenSessions.insert(sessId)
      }
    }

    if let session {
      if let existing = Activity<StoreVisitAttributes>.activities.first(where: { $0.attributes.sessionId == session.id }) {
        // Already showing this visit (either created locally or remotely started via push-to-start).
        // Ensure token observer is active and current token is reported to the current deployment.
        ensureTokenTracking(
          for: existing,
          shopCode: shopCode,
          sessionId: session.id,
          shopName: shopName,
          origin: originValue,
          api: api
        )
        return
      }

      for activity in Activity<StoreVisitAttributes>.activities where activity.attributes.shopCode == shopCode {
        await end(activity, startedAt: activity.content.state.startedAtUnix, endedAt: Date().timeIntervalSince1970, api: api)
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
        let activity = try Activity.request(
          attributes: StoreVisitAttributes(sessionId: session.id, shopCode: shopCode, shopName: shopName, origin: originValue),
          content: ActivityContent(
            state: .init(phase: "active", startedAtUnix: startedAt.timeIntervalSince1970, endedAtUnix: nil),
            staleDate: nil
          ),
          pushType: .token
        )
        ensureTokenTracking(
          for: activity,
          shopCode: shopCode,
          sessionId: session.id,
          shopName: shopName,
          origin: originValue,
          api: api
        )
        if let target = StoreVisitAttributes(sessionId: session.id, shopCode: shopCode, shopName: shopName, origin: originValue).shopURL {
          UserDefaults.standard.set(target.absoluteString, forKey: Self.lastLinkKey)
        }
      } catch {
        logger.error("Failed to start Live Activity: \(String(describing: error), privacy: .public)")
      }
    } else {
      for activity in Activity<StoreVisitAttributes>.activities where activity.attributes.shopCode == shopCode {
        await end(activity, startedAt: activity.content.state.startedAtUnix, endedAt: Date().timeIntervalSince1970, api: api)
      }
    }
  }

  /// Retires every activity's token, across shops. Used on sign-out.
  func unregisterAllPushTokens(api: PrismAPI) async {
    stopPushToStartTracking(api: api)
    for activity in Activity<StoreVisitAttributes>.activities {
      await reportUnregister(activity, api: api)
    }
  }

  /// Ensures an activity's push token is observed and reported idempotently to the server.
  func ensureTokenTracking(
    for activity: Activity<StoreVisitAttributes>,
    fallbackAPI: PrismAPI = .shared
  ) {
    guard activity.activityState == .active else { return }
    let attrs = activity.attributes
    let api = attrs.origin.flatMap(URL.init(string:)).map { fallbackAPI.atOrigin($0) } ?? fallbackAPI
    ensureTokenTracking(
      for: activity,
      shopCode: attrs.shopCode,
      sessionId: attrs.sessionId,
      shopName: attrs.shopName,
      origin: attrs.origin,
      api: api
    )
  }

  /// Ensures an activity's push token is observed and reported idempotently to the server.
  func ensureTokenTracking(
    for activity: Activity<StoreVisitAttributes>,
    shopCode: String,
    sessionId: String,
    shopName: String,
    origin: String?,
    api: PrismAPI
  ) {
    guard activity.activityState == .active else { return }

    if stateTasks[activity.id] == nil {
      stateTasks[activity.id] = Task { [weak self] in
        for await state in activity.activityStateUpdates {
          guard let self else { return }
          if state == .dismissed || state == .ended {
            self.cleanupTracking(for: activity.id)
            break
          }
        }
      }
    }

    if tokenTasks[activity.id] == nil {
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
            origin: origin,
            api: api
          )
        }
      }
    }

    if let currentToken = activity.pushToken {
      let token = currentToken.map { String(format: "%02x", $0) }.joined()
      Task { [weak self] in
        await self?.reportRegister(
          token: token,
          activity: activity,
          shopCode: shopCode,
          sessionId: sessionId,
          shopName: shopName,
          origin: origin,
          api: api
        )
      }
    }
  }

  /// Re-attaches token tracking to any existing activities after app restart / foreground resume.
  func recoverExistingActivities(api: PrismAPI = .shared) {
    for activity in Activity<StoreVisitAttributes>.activities {
      ensureTokenTracking(for: activity, fallbackAPI: api)
    }
  }

  private func reportStartToken(token: String, clientId: String, api: PrismAPI) async {
    if registeredStartToken == token && registeredStartOrigin == api.baseURL.absoluteString {
      return
    }
    logger.notice(
      "Registering Live Activity push-to-start token via \(api.baseURL.absoluteString, privacy: .public) (token \(token.count) chars)"
    )
    do {
      try await api.registerStartToken(clientId: clientId, token: token)
      registeredStartToken = token
      registeredStartOrigin = api.baseURL.absoluteString
    } catch {
      logger.error("Failed to register push-to-start token: \(String(describing: error), privacy: .public)")
    }
  }

  private func reportRegister(
    token: String,
    activity: Activity<StoreVisitAttributes>,
    shopCode: String,
    sessionId: String,
    shopName: String,
    origin: String?,
    api: PrismAPI
  ) async {
    if registeredTokens[activity.id] == token && registeredTokenOrigins[activity.id] == api.baseURL.absoluteString {
      return
    }
    var attributes: [String: Any] = [
      "sessionId": sessionId,
      "shopCode": shopCode,
      "shopName": shopName,
    ]
    if let origin { attributes["origin"] = origin }
    logger.notice(
      "Registering Live Activity token for shop \(shopCode, privacy: .public) via \(api.baseURL.absoluteString, privacy: .public) (token \(token.count) chars)"
    )
    var delay: UInt64 = 1_000_000_000
    for attempt in 1...3 {
      do {
        try await api.registerLiveActivity(
          shopCode: shopCode,
          activityId: activity.id,
          token: token,
          sessionId: sessionId,
          attributes: attributes
        )
        registeredTokens[activity.id] = token
        registeredTokenOrigins[activity.id] = api.baseURL.absoluteString
        return
      } catch {
        logger.error("Attempt \(attempt) failed to register Live Activity push token: \(String(describing: error), privacy: .public)")
        if attempt < 3 {
          try? await Task.sleep(nanoseconds: delay)
          delay *= 2
        }
      }
    }
    registeredTokens.removeValue(forKey: activity.id)
    registeredTokenOrigins.removeValue(forKey: activity.id)
  }

  private func cleanupTracking(for activityId: String) {
    tokenTasks[activityId]?.cancel()
    tokenTasks.removeValue(forKey: activityId)
    stateTasks[activityId]?.cancel()
    stateTasks.removeValue(forKey: activityId)
    registeredTokens.removeValue(forKey: activityId)
    registeredTokenOrigins.removeValue(forKey: activityId)
  }

  private func reportUnregister(_ activity: Activity<StoreVisitAttributes>, api: PrismAPI) async {
    cleanupTracking(for: activity.id)
    do {
      try await api.unregisterLiveActivity(shopCode: activity.attributes.shopCode, activityId: activity.id)
    } catch {
      logger.error("Failed to unregister Live Activity push token: \(String(describing: error), privacy: .public)")
    }
  }

  private func end(_ activity: Activity<StoreVisitAttributes>, startedAt: Double, endedAt: Double, api: PrismAPI) async {
    let state = StoreVisitAttributes.ContentState(phase: "ended", startedAtUnix: startedAt, endedAtUnix: endedAt)
    await reportUnregister(activity, api: api)
    await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60)))
  }
}

