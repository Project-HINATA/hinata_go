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
  private var registrationContinuation: CheckedContinuation<PasskeyRegistration, Error>?

  func authenticate(options: PasskeyRequestOptions) async throws -> PasskeyAssertion {
    guard continuation == nil, registrationContinuation == nil else { throw PrismAPIError.server("登录正在进行") }
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

  func register(options: PasskeyRegistrationOptions) async throws -> PasskeyRegistration {
    guard continuation == nil, registrationContinuation == nil else { throw PrismAPIError.server("登录正在进行") }
    guard let challenge = Data(base64URLEncoded: options.challenge),
          let userID = Data(base64URLEncoded: options.user.id) else { throw PrismAPIError.invalidResponse }
    return try await withCheckedThrowingContinuation { continuation in
      self.registrationContinuation = continuation
      let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: options.rp.id)
      let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: options.user.name, userID: userID)
      request.displayName = options.user.displayName
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
    if registrationContinuation != nil {
      guard let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
            let attestation = registration.rawAttestationObject else {
        finishRegistration(with: .failure(PrismAPIError.invalidResponse)); return
      }
      let credentialId = registration.credentialID.base64URLEncodedString()
      finishRegistration(with: .success(PasskeyRegistration(
        id: credentialId, rawId: credentialId,
        response: PasskeyRegistration.Response(
          clientDataJSON: registration.rawClientDataJSON.base64URLEncodedString(),
          attestationObject: attestation.base64URLEncodedString(), transports: ["internal"]
        ), type: "public-key", clientExtensionResults: [:], authenticatorAttachment: "platform"
      )))
      return
    }
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
    if registrationContinuation != nil { finishRegistration(with: .failure(error)) }
    else { finish(with: .failure(error)) }
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    return window ?? UIWindow()
  }

  private func finishRegistration(with result: Result<PasskeyRegistration, Error>) {
    let continuation = registrationContinuation
    registrationContinuation = nil
    controller = nil
    continuation?.resume(with: result)
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
