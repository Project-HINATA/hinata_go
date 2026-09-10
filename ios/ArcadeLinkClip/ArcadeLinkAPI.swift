import Foundation

enum ArcadeLinkAPIError: LocalizedError {
  case invalidURL
  case invalidResponse
  case server(String)

  var isSessionExpired: Bool {
    guard case .server(let message) = self else { return false }
    return message == "本次会话已失效" || message == "缺少会话凭证"
  }

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return String(localized: "ArcadeLink 地址无效")
    case .invalidResponse:
      return String(localized: "ArcadeLink 返回的数据无效")
    case .server(let message):
      return NSLocalizedString(message, value: String(localized: "操作失败，请稍后重试"), comment: "Server error")
    }
  }
}

final class ArcadeLinkAPI {
  static let shared = ArcadeLinkAPI()

  private let baseURL = URL(string: "https://link.neri.moe")!
  private let session: URLSession
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  init(configuration: URLSessionConfiguration = .default) {
    configuration.httpCookieAcceptPolicy = .always
    configuration.httpShouldSetCookies = true
    session = URLSession(configuration: configuration)
  }

  func startMachineSession(shopCode: String, publicId: String) async throws -> MachineSessionResponse {
    var request = try makeRequest(path: "/api/machines/session/start", method: "POST")
    request.httpBody = try encoder.encode(["shopCode": shopCode, "publicId": publicId])
    return try await send(request)
  }

  func me() async throws -> MeResponse {
    try await send(makeRequest(path: "/api/me"))
  }

  func cards() async throws -> CardsResponse {
    try await send(makeRequest(path: "/api/cards"))
  }

  func exchangeAppClipAuth(code: String) async throws {
    var request = try makeRequest(path: "/api/appclip/auth/exchange", method: "POST")
    request.httpBody = try encoder.encode(["code": code])
    let _: EmptyResponse = try await send(request)
  }

  func passkeyOptions() async throws -> PasskeyRequestOptions {
    try await send(makeRequest(path: "/api/auth/passkey/options"))
  }

  func loginWithPasskey(_ assertion: PasskeyAssertion) async throws {
    var request = try makeRequest(path: "/api/auth/passkey", method: "POST")
    request.httpBody = try encoder.encode(assertion)
    let _: EmptyResponse = try await send(request)
  }

  func loginMachine(_ input: MachineLoginRequest) async throws {
    var request = try makeRequest(path: "/api/machines/login", method: "POST")
    request.httpBody = try encoder.encode(input)
    let _: EmptyResponse = try await send(request)
  }

  func webFallbackURL(ticket: String) -> URL? {
    URL(string: "https://link.neri.moe/m?ticket=\(ticket.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ticket)")
  }

  private func makeRequest(path: String, method: String = "GET") throws -> URLRequest {
    guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
      throw ArcadeLinkAPIError.invalidURL
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
      throw ArcadeLinkAPIError.invalidResponse
    }
    guard 200..<300 ~= httpResponse.statusCode else {
      let message = (try? decoder.decode(ServerError.self, from: data).error) ?? "请求失败（\(httpResponse.statusCode)）"
      throw ArcadeLinkAPIError.server(message)
    }
    do {
      return try decoder.decode(Response.self, from: data)
    } catch {
      throw ArcadeLinkAPIError.invalidResponse
    }
  }
}

private struct ServerError: Decodable {
  let error: String
}
