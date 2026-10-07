import Foundation

enum PrismAPIError: LocalizedError, PrismRetryAfterProviding {
  case invalidURL
  case invalidResponse
  case server(String)
  case api(code: String, message: String)
  case http(status: Int, code: String, message: String)
  case limited(status: Int, code: String, message: String, retryAfter: TimeInterval)

  var code: String? {
    switch self { case .http(_, let code, _), .limited(_, let code, _, _), .api(let code, _): return code; default: return nil }
  }
  var isTransientReadFailure: Bool {
    guard let status else { return false }
    return status == 408 || status == 429 || status >= 500
  }
  var status: Int? {
    switch self { case .http(let value, _, _), .limited(let value, _, _, _): return value; default: return nil }
  }
  var retryAfter: TimeInterval? {
    if case .limited(_, _, _, let delay) = self { return delay }
    return nil
  }
  var isSessionExpired: Bool {
    if code == "TICKET_EXPIRED" { return true }
    guard case .server(let message) = self else { return false }
    return message == "本次会话已失效" || message == "缺少会话凭证"
  }

  var errorDescription: String? {
    if code == "INSUFFICIENT_BALANCE" {
      return String(localized: "余额不足，请充值后重试")
    }
    switch self {
    case .invalidURL:
      return String(localized: "PRiSM 地址无效")
    case .invalidResponse:
      return String(localized: "PRiSM 返回的数据无效")
    case .server(let message), .api(_, let message), .http(_, _, let message), .limited(_, _, let message, _):
      return NSLocalizedString(message, value: message, comment: "Server error")
    }
  }
}

final class PrismAPI {
  static let shared = PrismAPI()

  static let defaultOrigin: URL = {
    #if DEBUG
    if let origin = ProcessInfo.processInfo.environment["PRISM_API_ORIGIN"], let url = URL(string: origin), ["localhost", "127.0.0.1"].contains(url.host ?? "") { return url }
    #endif
    return URL(string: "https://link.neri.moe")!
  }()
  let baseURL: URL
  private let session: URLSession
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()
  private let reads = PrismReadCache()

  func invalidateReads() async { await reads.clear() }

  init(configuration: URLSessionConfiguration = .default, origin: URL = PrismAPI.defaultOrigin) {
    self.baseURL = origin
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieAcceptPolicy = .always
    configuration.httpShouldSetCookies = true
    session = URLSession(configuration: configuration)
  }

  func atOrigin(_ origin: URL) -> PrismAPI {
    #if DEBUG
    if ["localhost", "127.0.0.1"].contains(Self.defaultOrigin.host ?? "") { return self }
    #endif
    if baseURL == origin { return self }
    let configuration = session.configuration
    return PrismAPI(configuration: configuration, origin: origin)
  }

  func startMachineSession(shopCode: String, publicId: String) async throws -> MachineSessionResponse {
    var request = try makeRequest(path: "/api/v1/machines/session/start", method: "POST")
    request.httpBody = try encoder.encode(["shopCode": shopCode, "publicId": publicId])
    return try await send(request)
  }

  func me() async throws -> MeResponse {
    try await send(makeRequest(path: "/api/v1/me"))
  }

  func cards() async throws -> CardsResponse {
    try await send(makeRequest(path: "/api/v1/cards"))
  }

  func exchangeAppClipAuth(code: String) async throws {
    var request = try makeRequest(path: "/api/v1/appclip/auth/exchange", method: "POST")
    request.httpBody = try encoder.encode(["code": code])
    let _: EmptyResponse = try await send(request)
  }

  func passkeyOptions() async throws -> PasskeyRequestOptions {
    try await send(makeRequest(path: "/api/v1/auth/passkey/options"))
  }

  func passkeyRegistrationOptions() async throws -> PasskeyRegistrationOptions {
    try await send(makeRequest(path: "/api/v1/auth/passkey/register/options"))
  }

  func registerPasskey(_ credential: PasskeyRegistration) async throws {
    struct Body: Encodable { let credential: PasskeyRegistration }
    var request = try makeRequest(path: "/api/v1/auth/passkey/register", method: "POST")
    request.httpBody = try encoder.encode(Body(credential: credential))
    let _: EmptyResponse = try await send(request)
  }

  func loginWithPasskey(_ assertion: PasskeyAssertion) async throws {
    var request = try makeRequest(path: "/api/v1/auth/passkey", method: "POST")
    request.httpBody = try encoder.encode(assertion)
    let _: EmptyResponse = try await send(request)
  }

  func loginMachine(_ input: MachineLoginRequest) async throws -> SwipeResult {
    var request = try makeRequest(path: "/api/v1/machines/login", method: "POST")
    request.httpBody = try encoder.encode(input)
    return try await send(request)
  }

  func webFallbackURL(ticket: String) -> URL? {
    guard var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
    parts.path = "/m"; parts.query = nil
    var fragment = URLComponents()
    fragment.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
    parts.percentEncodedFragment = fragment.percentEncodedQuery
    return parts.url
  }

  /// Ships a Live Activity push token to the server so a visit opened on *another*
  /// channel (admin console, shop bot) can update this phone. The call is scoped to the
  /// shop whose visit the activity shows.
  func registerLiveActivity(
    shopCode: String,
    activityId: String,
    token: String,
    sessionId: String?,
    attributes: [String: Any]
  ) async throws {
    var body: [String: Any] = [
      "activityId": activityId,
      "token": token,
      "environment": Self.liveActivityEnvironment,
      "bundleId": Bundle.main.bundleIdentifier ?? "",
      "attributes": attributes,
    ]
    if let sessionId { body["sessionId"] = sessionId }
    let _: EmptyResponse = try await requestSelfSigned(
      path: "/api/v1/shops/\(shopCode)/player/live-activity/register",
      body: body
    )
  }

  /// Retires a token when the activity ends or the player signs out, so a dead activity is
  /// never pushed to.
  func unregisterLiveActivity(shopCode: String, activityId: String) async throws {
    let _: EmptyResponse = try await requestSelfSigned(
      path: "/api/v1/shops/\(shopCode)/player/live-activity/unregister",
      body: ["activityId": activityId]
    )
  }

  /// Registers a device-level push-to-start token so the backend can remotely launch
  /// a Live Activity when a visit begins externally while the app is closed.
  func registerStartToken(
    clientId: String,
    token: String,
    environment: String = PrismAPI.liveActivityEnvironment,
    bundleId: String = Bundle.main.bundleIdentifier ?? ""
  ) async throws {
    let body: [String: Any] = [
      "clientId": clientId,
      "token": token,
      "environment": environment,
      "bundleId": bundleId,
    ]
    let _: EmptyResponse = try await requestSelfSigned(
      path: "/api/v1/me/live-activity/start-token",
      body: body
    )
  }

  /// Retires the device-level push-to-start token on sign-out.
  func unregisterStartToken(clientId: String) async throws {
    var request = try makeRequest(path: "/api/v1/me/live-activity/start-token", method: "DELETE")
    request.httpBody = try encoder.encode(["clientId": clientId])
    let _: EmptyResponse = try await send(request)
  }

  /// Persistent anonymous client installation identifier, used to distinguish multiple
  /// devices belonging to the same user and avoid self-push races on local checkout/checkin.
  static var clientId: String {
    let key = "prism.client-id"
    if let existing = UserDefaults.standard.string(forKey: key) {
      return existing
    }
    let newId = UUID().uuidString
    UserDefaults.standard.set(newId, forKey: key)
    return newId
  }

  /// Debug builds talk to the APNs sandbox; everything else uses production.
  private static var liveActivityEnvironment: String {
    #if DEBUG
    return "sandbox"
    #else
    return "production"
    #endif
  }

  /// POSTs and discards the payload. The envelope is still decoded so a server-side
  /// rejection surfaces as an error instead of a silent success.
  private func requestSelfSigned(path: String, body: [String: Any]) async throws -> EmptyResponse {
    var request = try makeRequest(path: path, method: "POST")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return try await send(request)
  }

  func requestJSON(path: String, body: [String: Any]? = nil) async throws -> Data {
    var request = try makeRequest(path: path, method: body == nil ? "GET" : "POST")
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await responseData(for: request)
    guard let http = response as? HTTPURLResponse else { throw PrismAPIError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      throw responseError(data: data, http: http)
    }
    guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = envelope["data"] else { throw PrismAPIError.invalidResponse }
    return try JSONSerialization.data(withJSONObject: payload)
  }

  func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
    try decoder.decode(T.self, from: await requestJSON(path: path, body: body))
  }

  private func responseData(for request: URLRequest) async throws -> (Data, URLResponse) {
    let path = request.url?.path ?? ""
    let parts = path.split(separator: "/")
    let ttl: TimeInterval?
    if request.httpMethod == "GET", request.url?.query == nil {
      if path == "/api/v1/me" { ttl = 1 }
      else if parts.count >= 4 && parts.prefix(3).map(String.init) == ["api", "v1", "shops"] {
        ttl = parts.count == 4 ? 30 : (parts.count == 6 && parts.suffix(2).map(String.init) == ["player", "me"] ? 1 : nil)
      } else { ttl = nil }
    } else { ttl = nil }
    if let ttl, let key = request.url?.absoluteString {
      return try await reads.read(key: key, ttl: ttl) { [self] in try await uncachedResponseData(for: request) }
    }
    let result = try await uncachedResponseData(for: request)
    if request.httpMethod != "GET", !path.hasSuffix("/checkout/preview"), !path.hasSuffix("/machines/session/start"),
       let http = result.1 as? HTTPURLResponse, 200..<300 ~= http.statusCode { await invalidateReads() }
    return result
  }

  private func uncachedResponseData(for request: URLRequest) async throws -> (Data, URLResponse) {
    do { return try await session.data(for: request) }
    catch let error as URLError {
      guard Self.isRetryable(request), [.networkConnectionLost, .notConnectedToInternet, .timedOut, .cannotConnectToHost].contains(error.code) else { throw error }
      try await Task.sleep(nanoseconds: 300_000_000)
      return try await session.data(for: request)
    }
  }

  /// Reads are always safe to repeat. `machines/session/start` is included because a cold
  /// launch regularly loses its first request while the radio is still coming up; that call
  /// only mints an opaque ticket. Billing and device actions stay out so they are never sent twice.
  private static func isRetryable(_ request: URLRequest) -> Bool {
    if request.httpMethod == "GET" { return true }
    let path = request.url?.path ?? ""
    return path.hasSuffix("/checkout/preview") || path.hasSuffix("/machines/session/start")
  }

  private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
    guard path.hasPrefix("/api/v1/"), !path.contains(".."), let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port else {
      throw PrismAPIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(Self.clientId, forHTTPHeaderField: "x-prism-client-id")
    if method != "GET" {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
    let (data, response) = try await responseData(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw PrismAPIError.invalidResponse
    }
    guard 200..<300 ~= httpResponse.statusCode else {
      throw responseError(data: data, http: httpResponse)
    }
    do {
      return try decoder.decode(APIEnvelope<Response>.self, from: data).data
    } catch {
      throw PrismAPIError.invalidResponse
    }
  }

  private func responseError(data: Data, http: HTTPURLResponse) -> PrismAPIError {
    let detail = try? decoder.decode(ServerError.self, from: data).error
    let message = detail?.message ?? "请求失败（\(http.statusCode)）"
    if let delay = Self.retryAfter(http.value(forHTTPHeaderField: "Retry-After")) {
      return .limited(status: http.statusCode, code: detail?.code ?? "", message: message, retryAfter: delay)
    }
    return .http(status: http.statusCode, code: detail?.code ?? "", message: message)
  }

  static func retryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
    guard let value else { return nil }
    if let seconds = Double(value), seconds.isFinite, seconds >= 0 { return seconds }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    guard let date = formatter.date(from: value) else { return nil }
    return max(0, date.timeIntervalSince(now))
  }
}

/// Shared subscribers never cancel another subscriber's transport. Failed responses are not cached.
private actor PrismReadCache {
  struct Entry { let id: UUID; let task: Task<(Data, URLResponse), Error>; var expires: Date? }
  private var entries: [String: Entry] = [:]
  func clear() { entries.removeAll() }
  func read(key: String, ttl: TimeInterval, load: @escaping @Sendable () async throws -> (Data, URLResponse)) async throws -> (Data, URLResponse) {
    let entry: Entry
    if let existing = entries[key], existing.expires == nil || existing.expires! > Date() { entry = existing }
    else {
      if entries.count >= 100, let oldest = entries.keys.first { entries.removeValue(forKey: oldest) }
      entry = Entry(id: UUID(), task: Task { try await load() }, expires: nil)
      entries[key] = entry
    }
    do {
      let result = try await entry.task.value
      if entries[key]?.id == entry.id {
        if let http = result.1 as? HTTPURLResponse, 200..<300 ~= http.statusCode {
          if entries[key]?.expires == nil { entries[key]?.expires = Date().addingTimeInterval(ttl) }
        } else { entries.removeValue(forKey: key) }
      }
      try Task.checkCancellation()
      return result
    } catch {
      if !(error is CancellationError), entries[key]?.id == entry.id { entries.removeValue(forKey: key) }
      throw error
    }
  }
}

struct PrismReadBackoff {
  private(set) var failures = 0
  private(set) var nextReadAt = Date.distantPast
  func remaining(now: Date = Date()) -> TimeInterval { max(0, nextReadAt.timeIntervalSince(now)) }
  mutating func succeed() { failures = 0; nextReadAt = .distantPast }
  mutating func fail(retryAfter: TimeInterval? = nil, now: Date = Date(), random: Double = Double.random(in: 0...1)) {
    failures = min(5, failures + 1)
    let base: [TimeInterval] = [5, 10, 20, 30, 60]
    let delay = max(retryAfter ?? 0, min(60, base[failures - 1] * (0.85 + random * 0.3)))
    nextReadAt = now.addingTimeInterval(delay)
  }
}

private struct ServerError: Decodable {
  let error: Detail
  struct Detail: Decodable { let code: String; let message: String }
}

private struct APIEnvelope<T: Decodable>: Decodable { let data: T }
