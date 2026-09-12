import Foundation

enum PrismAPIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case server(String)
  case api(code: String, message: String)
  case http(status: Int, code: String, message: String)

  var code: String? {
    switch self { case .http(_, let code, _), .api(let code, _): return code; default: return nil }
  }
  var isSessionExpired: Bool {
    if case .http(_, let code, _) = self { return code == "TICKET_EXPIRED" }
    if case .api(let code, _) = self { return code == "TICKET_EXPIRED" }
    guard case .server(let message) = self else { return false }
    return message == "本次会话已失效" || message == "缺少会话凭证"
  }

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return String(localized: "PRiSM 地址无效")
    case .invalidResponse:
      return String(localized: "PRiSM 返回的数据无效")
    case .server(let message), .api(_, let message), .http(_, _, let message):
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

  init(configuration: URLSessionConfiguration = .ephemeral, origin: URL = PrismAPI.defaultOrigin) {
    self.baseURL = origin
    configuration.httpCookieAcceptPolicy = .always
    configuration.httpShouldSetCookies = true
    session = URLSession(configuration: configuration)
  }

  func atOrigin(_ origin: URL) -> PrismAPI {
    #if DEBUG
    if ["localhost", "127.0.0.1"].contains(Self.defaultOrigin.host ?? "") { return self }
    #endif
    if baseURL == origin { return self }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = session.configuration.protocolClasses
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
    URL(string: "\(baseURL.absoluteString)/m?ticket=\(ticket.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticket)")
  }

  func requestJSON(path: String, body: [String: Any]? = nil) async throws -> Data {
    var request = try makeRequest(path: path, method: body == nil ? "GET" : "POST")
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw PrismAPIError.invalidResponse }
    guard 200..<300 ~= http.statusCode else {
      if let error = try? decoder.decode(ServerError.self, from: data).error {
        throw PrismAPIError.http(status: http.statusCode, code: error.code, message: error.message)
      }
      throw PrismAPIError.server("请求失败（\(http.statusCode)）")
    }
    guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any], let payload = envelope["data"] else { throw PrismAPIError.invalidResponse }
    return try JSONSerialization.data(withJSONObject: payload)
  }

  func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
    try decoder.decode(T.self, from: await requestJSON(path: path, body: body))
  }

  private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
    guard path.hasPrefix("/api/v1/"), !path.contains(".."), let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, url.scheme == baseURL.scheme, url.host == baseURL.host, url.port == baseURL.port else {
      throw PrismAPIError.invalidURL
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if method != "GET" {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    return request
  }

  private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw PrismAPIError.invalidResponse
    }
    guard 200..<300 ~= httpResponse.statusCode else {
      if let error = try? decoder.decode(ServerError.self, from: data).error {
        throw PrismAPIError.api(code: error.code, message: error.message)
      }
      throw PrismAPIError.server("请求失败（\(httpResponse.statusCode)）")
    }
    do {
      return try decoder.decode(APIEnvelope<Response>.self, from: data).data
    } catch {
      throw PrismAPIError.invalidResponse
    }
  }
}

private struct ServerError: Decodable {
  let error: Detail
  struct Detail: Decodable { let code: String; let message: String }
}

private struct APIEnvelope<T: Decodable>: Decodable { let data: T }
