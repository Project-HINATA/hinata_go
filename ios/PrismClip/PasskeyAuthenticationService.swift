import AuthenticationServices
import Foundation
import UIKit

func isAuthenticationCancellation(_ error: Error) -> Bool {
  (error as? ASAuthorizationError)?.code == .canceled ||
    (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin ||
    error is CancellationError
}

@MainActor
final class PasskeyAuthenticationService: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private var continuation: CheckedContinuation<PasskeyAssertion, Error>?
  private var controller: ASAuthorizationController?

  func authenticate(options: PasskeyRequestOptions) async throws -> PasskeyAssertion {
    guard let challenge = Data(base64URLEncoded: options.challenge) else {
      throw PrismAPIError.invalidResponse
    }

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rpId)
      let request = provider.createCredentialAssertionRequest(challenge: challenge)
      request.userVerificationPreference = .required

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = self
      controller.presentationContextProvider = self
      self.controller = controller
      controller.performRequests()
    }
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization,
  ) {
    guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
      finish(with: .failure(PrismAPIError.invalidResponse))
      return
    }

    let credentialId = assertion.credentialID.base64URLEncodedString()
    let result = PasskeyAssertion(
      id: credentialId,
      rawId: credentialId,
      response: PasskeyAssertionResponse(
        clientDataJSON: assertion.rawClientDataJSON.base64URLEncodedString(),
        authenticatorData: assertion.rawAuthenticatorData.base64URLEncodedString(),
        signature: assertion.signature.base64URLEncodedString(),
        userHandle: assertion.userID.isEmpty ? nil : assertion.userID.base64URLEncodedString(),
      ),
      type: "public-key",
    )
    finish(with: .success(result))
  }

  func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithError error: Error,
  ) {
    finish(with: .failure(error))
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    return window ?? UIWindow()
  }

  private func finish(with result: Result<PasskeyAssertion, Error>) {
    let continuation = continuation
    self.continuation = nil
    controller = nil
    continuation?.resume(with: result)
  }
}

private extension Data {
  init?(base64URLEncoded value: String) {
    var encoded = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
    self.init(base64Encoded: encoded)
  }

  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
