import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class MunetAuthenticationService: NSObject, ASWebAuthenticationPresentationContextProviding {
  static let callbackScheme = "hinata-arcadelink-auth"

  private var session: ASWebAuthenticationSession?
  private var continuation: CheckedContinuation<String, Error>?

  func authenticate() async throws -> String {
    guard let url = URL(string: "https://link.neri.moe/api/appclip/auth/start") else {
      throw ArcadeLinkAPIError.invalidURL
    }

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let session = ASWebAuthenticationSession(
        url: url,
        callbackURLScheme: Self.callbackScheme,
      ) { [weak self] callbackURL, error in
        guard let self else { return }
        Task { @MainActor in
          self.handle(callbackURL: callbackURL, error: error)
        }
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false
      self.session = session
      guard session.start() else {
        finish(with: .failure(ArcadeLinkAPIError.server("无法打开 MuNET 登录")))
        return
      }
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    return window ?? UIWindow()
  }

  private func handle(callbackURL: URL?, error: Error?) {
    if let error {
      finish(with: .failure(error))
      return
    }
    guard let callbackURL else {
      finish(with: .failure(ArcadeLinkAPIError.invalidResponse))
      return
    }
    let query = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if let message = query.first(where: { $0.name == "error" })?.value {
      finish(with: .failure(message == "MuNET 授权已取消" ? CancellationError() : ArcadeLinkAPIError.server(message)))
      return
    }
    guard let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
      finish(with: .failure(ArcadeLinkAPIError.invalidResponse))
      return
    }
    finish(with: .success(code))
  }

  private func finish(with result: Result<String, Error>) {
    let continuation = continuation
    self.continuation = nil
    session = nil
    continuation?.resume(with: result)
  }
}
