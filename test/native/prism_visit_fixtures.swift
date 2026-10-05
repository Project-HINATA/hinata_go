import Foundation
import Combine

// ActivityKit is unavailable in this macOS check; record the shared call boundary.
@MainActor final class StoreVisitLiveActivityManager {
  static let shared = StoreVisitLiveActivityManager()
  private(set) var session: PrismSummary.Session?
  private(set) var origin: URL?
  private(set) var lastApi: PrismAPI?
  /// Sign-out must retire every activity's push token, so the check records the sweep.
  private(set) var unregisteredAll = false
  private(set) var trackingPushToStart = false
  private(set) var recoveredActivities = false

  func reconcile(
    session: PrismSummary.Session?,
    shopCode: String,
    shopName: String,
    origin: URL?,
    api: PrismAPI,
    receipt: PrismCheckoutResult? = nil
  ) async {
    self.session = session
    self.origin = origin
    self.lastApi = api
  }
  private(set) var finishedReceipt: PrismCheckoutResult?
  func finishCheckout(receipt: PrismCheckoutResult, shopCode: String, api: PrismAPI) async {
    finishedReceipt = receipt
    session = nil
  }
  func unregisterAllPushTokens(api: PrismAPI) async {
    try! await api.unregisterStartToken(clientId: PrismAPI.clientId)
    unregisteredAll = true
    self.lastApi = api
  }
  func startPushToStartTracking(api: PrismAPI) {
    trackingPushToStart = true
    self.lastApi = api
  }
  func recoverExistingActivities(api: PrismAPI = .shared) {
    recoveredActivities = true
    self.lastApi = api
  }
  func startGlobalActivityTracking(fallbackAPI: PrismAPI = .shared) {
    self.lastApi = fallbackAPI
  }
}

@MainActor final class PasskeyAuthenticationService {
  static var cancelRegistration = false
  func authenticate(options: PasskeyRequestOptions) async throws -> PasskeyAssertion { throw CancellationError() }
  func register(options: PasskeyRegistrationOptions) async throws -> PasskeyRegistration {
    precondition(options.rp.id == "link-beta.neri.moe" && options.user.id == "dXNlcg")
    if Self.cancelRegistration { throw CancellationError() }
    return PasskeyRegistration(id: "credential", rawId: "credential", response: .init(clientDataJSON: "client", attestationObject: "attestation", transports: ["internal"]), type: "public-key", clientExtensionResults: [:], authenticatorAttachment: "platform")
  }
}
@MainActor final class MunetAuthenticationService {
  static var result: PrismMunetAuthenticationResult?
  func authenticate(origin: URL) async throws -> PrismMunetAuthenticationResult {
    guard let result = Self.result else { throw CancellationError() }
    return result
  }
}
struct LocationSample { let latitude: Double; let longitude: Double; let accuracy: Double }
@MainActor final class LocationService {
  static var calls = 0
  func currentLocation() async throws -> LocationSample { Self.calls += 1; return LocationSample(latitude: 35, longitude: 139, accuracy: 5) }
}
enum LocationError: LocalizedError { case unavailable }
func isAuthenticationCancellation(_ error: Error) -> Bool { error is CancellationError }

final class FixtureProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, [String: Any]))!
  static var holdNextShopResponse = false
  static var heldReply: (() -> Void)?
  static var holdNextIdentityResponse = false
  static var heldIdentityReply: (() -> Void)?
  static var holdNextPowerResponse = false
  static var heldPowerReply: (() -> Void)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, body) = try Self.handler(request)
      let data = try body["rawHTML"].map { Data(($0 as! String).utf8) } ?? JSONSerialization.data(withJSONObject: body)
      let reply = { [self] in
        var headers = body["headers"] as? [String: String] ?? [:]
        headers["content-type"] = "application/json"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
      }
      if Self.holdNextShopResponse && request.url?.path == "/api/v1/shops/store" {
        Self.holdNextShopResponse = false
        Self.heldReply = reply
      } else if Self.holdNextIdentityResponse && request.url?.path == "/api/v1/me" {
        Self.holdNextIdentityResponse = false; Self.heldIdentityReply = reply
      } else if Self.holdNextPowerResponse && request.url?.path == "/api/v1/devices/session/power" {
        Self.holdNextPowerResponse = false; Self.heldPowerReply = reply
      } else { reply() }
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
