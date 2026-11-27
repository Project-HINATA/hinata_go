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
  /// The shops whose activity the page asked to follow the visit (an entry, a checkout).
  private(set) var synced: [String] = []
  func sync(shopCode: String, shopName: String?, origin: URL?, api: PrismAPI) async {
    synced.append(shopCode)
    self.lastApi = api
  }
}

func liveActivityTrace(_ message: String) {}

#if os(macOS)
import Security
#endif
/// `PrismAPI.clientId` lives in the Keychain. To macOS every rebuilt check is another program, so reading
/// the item an earlier build made raises a permission dialog and the check waits on it for ever. Refusing
/// dialogs makes that read fail instead, and the client id falls back to the one in the defaults.
func refuseKeychainDialogs() {
  #if os(macOS)
  SecKeychainSetUserInteractionAllowed(false)
  #endif
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
enum LocationError: LocalizedError { case denied, unavailable }
func isAuthenticationCancellation(_ error: Error) -> Bool { error is CancellationError }

final class FixtureProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, [String: Any]))!
  static var holdNextShopResponse = false
  static var heldReply: (() -> Void)?
  static var holdNextIdentityResponse = false
  static var heldIdentityReply: (() -> Void)?
  static var holdNextPageResponse = false
  static var heldPageReply: (() -> Void)?
  static var holdNextShopPageResponse = false
  static var heldShopPageReply: (() -> Void)?
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
      } else if Self.holdNextPageResponse && request.url?.path == "/api/v1/devices/session/page" {
        Self.holdNextPageResponse = false; Self.heldPageReply = reply
      } else if Self.holdNextShopPageResponse && request.url?.path == "/api/v1/shops/store/player/page" {
        Self.holdNextShopPageResponse = false; Self.heldShopPageReply = reply
      } else { reply() }
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

/// Scanned pages as the platform makes them: PRiSM's `scripts/swift-page-fixtures.ts` writes them with the
/// server's own `renderPage`, so these checks fail when the page changes and the Swift models do not follow.
enum PageFixtures {
  /// The preview app carries the file as a resource; the command-line checks run from the repository root.
  private static let file: [String: Any] = {
    let url = Bundle.main.url(forResource: "pages", withExtension: "json")
      ?? URL(fileURLWithPath: "test/native/fixtures/prism-page/pages.json")
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
  }()
  private static var pages: [String: Any] { file["pages"] as! [String: Any] }
  private static var shopPages: [String: Any] { file["shopPages"] as! [String: Any] }
  static var noticeScreenshots: [[String: Any]] { file["screenshots"] as! [[String: Any]] }
  static var names: [String] { pages.keys.sorted() }
  static var shopPageNames: [String] { shopPages.keys.sorted() }
  static func page(_ name: String) -> [String: Any] {
    guard let page = pages[name] as? [String: Any] else { preconditionFailure("No page fixture named \(name)") }
    return page
  }
  static func shopPage(_ name: String) -> [String: Any] {
    guard let page = shopPages[name] as? [String: Any] else { preconditionFailure("No shopPage fixture named \(name)") }
    return page
  }
  static var binding: [String: Any] { file["binding"] as! [String: Any] }
  static var code: [String: Any] { file["code"] as! [String: Any] }
  static func notice(_ code: String) -> [String: Any] {
    (file[Locale.preferredLanguages.first?.hasPrefix("en") == true ? "noticesEn" : "notices"] as! [String: Any])[code] as! [String: Any]
  }
  static var celebration: [String: Any] { file["celebration"] as! [String: Any] }
  /// `page` with the first block of `kind` changed, for a state the platform would send next.
  static func changing(_ page: [String: Any], kind: String, _ change: (inout [String: Any]) -> Void) -> [String: Any] {
    var page = page
    var blocks = page["blocks"] as! [[String: Any]]
    guard let index = blocks.firstIndex(where: { $0["kind"] as? String == kind }) else { preconditionFailure("The page has no \(kind) block") }
    change(&blocks[index])
    page["blocks"] = blocks
    return page
  }
}
