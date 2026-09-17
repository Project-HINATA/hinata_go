// Run with test/native/run-prism-visit-check.sh. Auth and location are local stubs;
// Models, API decoding and the App Clip state machine are the production sources.
import Foundation

// ActivityKit is unavailable in this macOS check; record the shared call boundary.
@MainActor final class StoreVisitLiveActivityManager {
  static let shared = StoreVisitLiveActivityManager()
  private(set) var session: PrismSummary.Session?
  private(set) var origin: URL?
  func reconcile(session: PrismSummary.Session?, shopCode: String, shopName: String, origin: URL?) async {
    self.session = session
    self.origin = origin
  }
}

@MainActor final class PasskeyAuthenticationService {
  func authenticate(options: PasskeyRequestOptions) async throws -> PasskeyAssertion { throw CancellationError() }
}
@MainActor final class MunetAuthenticationService {
  func authenticate(origin: URL) async throws -> String { throw CancellationError() }
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
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, body) = try Self.handler(request)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["content-type": "application/json"])!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: body))
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

enum PersistentCookieCheck {
  static func check() async throws {
    let port = ProcessInfo.processInfo.environment["PRISM_COOKIE_TEST_PORT"]!
    let origin = URL(string: "http://127.0.0.1:\(port)")!
    let first = PrismAPI(origin: origin)
    try await first.exchangeAppClipAuth(code: "test")
    let loggedIn = try await first.me().user?.id == "persisted"
    precondition(loggedIn)
    let reopened = PrismAPI(origin: origin)
    let restored = try await reopened.me().user?.id == "persisted"
    precondition(restored, "Recreating the client must preserve login")
    let other = first.atOrigin(URL(string: "http://localhost:\(port)")!)
    let isolated = try await other.me().user == nil
    precondition(isolated, "Login cookies must not reach another host")
    let returned = try await other.atOrigin(origin).me().user?.id == "persisted"
    precondition(returned)
    _ = try await reopened.requestJSON(path: "/api/v1/auth/logout", body: [:])
    let loggedOut = try await PrismAPI(origin: origin).me().user == nil
    precondition(loggedOut, "Logout must remain effective after reopening")
  }
}

@main struct PrismVisitCheck {
  @MainActor static func main() async throws {
    let wholeSeconds = prismParsedDate("2026-09-12T00:00:00Z")!
    let milliseconds = prismParsedDate("2026-09-12T00:00:00.123Z")!
    precondition(abs(milliseconds.timeIntervalSince(wholeSeconds) - 0.123) < 0.00001)
    precondition(prismParsedDate("2026-09-12T09:00:00.123+09:00") == milliseconds)
    precondition(prismParsedDate("invalid") == nil)
    try await PersistentCookieCheck.check()
    let origin = URL(string: "https://link-beta.neri.moe")!
    precondition(InvocationParser.invocation(from: URL(string: "https://example.com:8443/t/store/device")!)?.origin.absoluteString == "https://example.com:8443")
    precondition(InvocationParser.invocation(from: URL(string: "http://example.com/t/store/device")!) == nil)
    precondition(InvocationParser.invocation(from: URL(string: "https://user@example.com/t/store/device")!) == nil)
    // A bare shop code is the device-free shop surface, and must not be read as a machine.
    let shopLink = InvocationParser.shopInvocation(from: URL(string: "https://link.neri.moe/t/store")!)
    precondition(shopLink?.shopCode == "store")
    precondition(shopLink?.origin.absoluteString == "https://link.neri.moe")
    precondition(InvocationParser.invocation(from: URL(string: "https://link.neri.moe/t/store")!) == nil)
    precondition(InvocationParser.shopInvocation(from: URL(string: "https://link.neri.moe/t/store/device")!) == nil)
    precondition(InvocationParser.shopInvocation(from: URL(string: "http://link.neri.moe/t/store")!) == nil)
    precondition(InvocationParser.shopInvocation(from: URL(string: "https://link.neri.moe/t/store/")!)?.shopCode == "store")
    precondition(InvocationParser.shopInvocation(from: URL(string: "https://link.neri.moe/t")!) == nil)
    precondition(InvocationParser.shopInvocation(from: URL(string: "https://link.neri.moe/t/bad!code")!) == nil)
    precondition(InvocationParser.shopInvocation(from: URL(string: "https://user@link.neri.moe/t/store")!) == nil)
    var mahjongSeats: [[String:Any]] = []
    var member = false, active = false
    var billing = true
    let heroUrl: String? = "/api/v1/shops/store/hero?v=abc123"
    var capabilities = ["power":true,"coin":true,"card":true,"door":true]
    var historyReads = 0, assetReads = 0
    var failBillRead = true
    var statusReads = 0
    var failNextStatusRead = false
    var checkoutCalls = 0, coinCalls = 0, sessionStarts = 0
    var checkoutIds: [String] = []
    let testUser = UUID().uuidString
    FixtureProtocol.handler = { request in
      precondition(request.url!.host == origin.host)
      let path = request.url!.path
      let data: Data
      if let body = request.httpBody { data = body }
      else if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var bytes = Data(), buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; bytes.append(buffer, count: count) }
        data = bytes
      } else { data = Data("{}".utf8) }
      let body = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      func ok(_ value: [String: Any]) -> (Int, [String: Any]) { (200, ["data": value]) }
      switch path {
      case "/api/v1/machines/session/start": sessionStarts += 1; return ok(["ticket":"ticket-\(sessionStarts)", "expiresIn":300, "machine":["publicId":"device", "name":"Device", "webOnly":true, "coinAfterSwipe":true, "capabilities":capabilities, "shop":["name":"Store", "latitude":35,"longitude":139,"radiusMeters":80,"machineGeo":false,"billingEnabled":billing]]])
      case "/api/v1/me": return ok(["user":["id":testUser,"username":"test","displayName":"Test"]])
      case "/api/v1/cards": return ok(["cards":[["id":"card","label":"Aime","accessCode":"01234567890123456789"]]])
      case "/api/v1/shops/store":
        statusReads += 1
        if failNextStatusRead { failNextStatusRead = false; throw URLError(.networkConnectionLost) }
        return ok(["shop":["name":"Store","billingEnabled":billing,"checkinGeo":true,"checkoutGeo":true,"autoRegister":false,"botContact":"QQ Bot","timeZone":"Asia/Tokyo","heroUrl":heroUrl as Any],"membership":member ? ["playerId":"p"] : NSNull(),"entryPricing":[]])
      case "/api/v1/devices/session/state": return ok(["gate":!billing ? "ready" : member ? (active ? "ready" : "entry") : "qq", "power":"unknown","mahjong":["capacity":4,"seats":mahjongSeats]])
      case "/api/v1/shops/store/qq-binding": return ok(["code":"ABC123","expiresAt":"2999-01-01T00:00:00Z"])
      case "/api/v1/shops/store/player/me": return ok(["wallet":[],"activeSession":active ? ["id":"entry","startedAt":"2026-09-12T00:00:00.123Z"] : NSNull()])
      case "/api/v1/shops/store/player/assets": assetReads += 1; return ok(["holdings":[]])
      case "/api/v1/shops/store/player/sessions/history": historyReads += 1; return ok(["sessions":[]])
      case "/api/v1/shops/store/devices": return ok(["devices":[]])
      case "/api/v1/devices/session/actions":
        if body["action"] as? String == "mahjong.join" {
          precondition(body["ticket"] != nil && body["operationId"] != nil)
          mahjongSeats = [["name":"Player","mine":true,"playing":false]]
          return ok([:])
        }
        if body["action"] as? String == "mahjong.leave" { mahjongSeats = []; return ok([:]) }

        if body["action"] as? String == "coin" { coinCalls += 1; throw URLError(.networkConnectionLost) }
        precondition(body["consent"] as? Bool == true)
        precondition(body["location"] != nil)
        active = true
        return ok(["temporaryPassword":"12345678","expiresAt":"2999-01-01T00:00:00Z"])
      case "/api/v1/machines/login": return ok(["ok":true,"coin":["status":"unknown"]])
      case "/api/v1/shops/store/player/checkout/preview":
        if failBillRead { failBillRead = false; throw URLError(.networkConnectionLost) }
        return ok(["settlementPreview":["total":12],"chargeItems":[],"adjustments":[]])
      case "/api/v1/shops/store/player/checkout/confirm":
        checkoutIds.append(body["operationId"] as! String); checkoutCalls += 1
        if checkoutCalls == 1 { return (400,["error":["code":"INSUFFICIENT_BALANCE","message":"余额不足"]]) }
        if checkoutCalls == 2 { throw URLError(.networkConnectionLost) }
        active = false
        // Mirrors the real confirm payload; the success screen renders from this.
        return ok([
          "playerSettlement":["total":12, "settledAt":"2026-09-12T01:00:00Z"],
          "chargeItems":[["id":"c1","label":"入场费","amount":12]],
          "adjustments":[],
          "wallet":["balanceBefore":100,"balanceAfter":88],
        ])
      default: preconditionFailure("Unexpected API path: \(path)")
      }
    }
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
    let model = MachineLoginViewModel(api: PrismAPI(configuration: config))
    await model.handleInvocation(origin.appendingPathComponent("t/store/device"))
    precondition(model.state == .ready && model.deviceState?.gate == "qq")
    precondition(model.binding?.code == "ABC123")
    try await Task.sleep(nanoseconds: 3_300_000_000)
    precondition(statusReads >= 2 && model.errorMessage == nil, "Polling must not cancel its own requests")
    await model.setSceneActive(false)
    let readsBeforeBackground = statusReads
    await model.refreshVisit()
    precondition(statusReads == readsBeforeBackground)
    failNextStatusRead = true
    await model.setSceneActive(true)
    precondition(model.errorMessage == nil && model.ticket != nil, "Resume network errors must not show an alert")
    try await Task.sleep(nanoseconds: 3_300_000_000)
    precondition(statusReads >= readsBeforeBackground + 2 && sessionStarts == 1 && model.binding?.code == "ABC123")
    member = true; await model.refreshVisit(); precondition(model.deviceState?.gate == "entry")
    await model.device("door.open", consent:true)
    precondition(model.doorPassword?.temporaryPassword == "12345678" && model.summary?.activeSession != nil)
    precondition(StoreVisitLiveActivityManager.shared.session?.id == "entry")
    precondition(prismParsedDate(StoreVisitLiveActivityManager.shared.session!.startedAt) == milliseconds)
    precondition(model.canUseCards && model.deviceState?.power == "unknown")
    await model.device("coin"); await model.device("coin"); precondition(coinCalls == 1)
    precondition(model.state == .ready && model.ticket != nil && model.errorMessage != nil && sessionStarts == 1)
    await model.refreshVisit(); precondition(sessionStarts == 1)
    await model.start(shopCode: "store", publicId: "device")
    await model.login(card:model.cards[0]); precondition(model.state == .ready && model.ticket != nil)
    precondition(historyReads == 0 && assetReads == 0, "Status, admission and device operations must not fetch wallet/history")
    try await model.loadAccountSection(0)
    precondition(historyReads == 0 && assetReads == 0, "Bill must not fetch unrelated account data")
    try await model.loadAccountSection(2)
    precondition(historyReads == 1 && assetReads == 0)
    try await model.loadAccountSection(3)
    precondition(historyReads == 1 && assetReads == 1)
    await model.previewCheckout(); precondition(model.checkoutPreview?.settlementPreview.total == 12)
    await model.checkout(); precondition(model.summary?.activeSession != nil)
    await model.checkout(); await model.checkout()
    precondition(checkoutIds[0] != checkoutIds[1] && checkoutIds[1] == checkoutIds[2])
    precondition(model.summary?.activeSession == nil && model.checkoutPreview == nil)
    precondition(StoreVisitLiveActivityManager.shared.session == nil)
    precondition(LocationService.calls == 4)
    billing = false; member = false; capabilities.removeValue(forKey: "door")
    await model.start(shopCode: "store", publicId: "device")
    precondition(model.canUseCards && !model.showVisit && !model.showDeviceControls)
    capabilities = ["mahjong":true]
    await model.start(shopCode:"store",publicId:"device")
    precondition(model.showDeviceControls)
    await model.device("mahjong.join")
    precondition(model.deviceState?.mahjong?.seats.first?.mine == true && !model.waitingPower)
    await model.device("mahjong.leave")
    precondition(model.deviceState?.mahjong?.seats.isEmpty == true)
    capabilities = [:]
    await model.start(shopCode: "store", publicId: "device")
    precondition(model.state == .ready && model.machine?.empty == true && !model.canUseCards)
    // A bare shop link opens the settle-only surface: no machine, no ticket, no admission.
    billing = true; member = true; active = false
    let shopOnly = MachineLoginViewModel(api: PrismAPI(configuration: config))
    await shopOnly.handleInvocation(origin.appendingPathComponent("t/store"))
    precondition(shopOnly.isShopOnly && shopOnly.ticket == nil && shopOnly.machine == nil)
    precondition(shopOnly.state == .ready && shopOnly.summary?.activeSession == nil)
    // The card's subtitle carries the billing state where a device card shows the machine name.
    precondition(shopOnly.shopBillingState == "未入场")
    precondition(shopOnly.canUseShopSurface && !shopOnly.shopHasActiveSession)
    // The shop card needs the cover the shop page now returns, the same as a device card.
    precondition(shopOnly.visit?.shop.heroUrl == "/api/v1/shops/store/hero?v=abc123")
    // A player who has not verified with the Bot gets the binding explanation.
    member = false
    await shopOnly.handleInvocation(origin.appendingPathComponent("t/store"))
    precondition(shopOnly.visit?.membership == nil && !shopOnly.canUseShopSurface)
    member = true
    // Admission comes from the machine flow, so the shop link reads the bill it opened.
    active = true
    await shopOnly.handleInvocation(origin.appendingPathComponent("t/store"))
    precondition(shopOnly.shopHasActiveSession && shopOnly.shopBillingState == "计费中")
    precondition(StoreVisitLiveActivityManager.shared.session?.id == "entry")
    precondition(StoreVisitLiveActivityManager.shared.origin?.absoluteString == "https://link-beta.neri.moe")
    // Loading the bill section is what the embedded bill view does on appear.
    try await shopOnly.loadAccountSection(0)
    precondition(shopOnly.checkoutPreview != nil)
    // Settling keeps a receipt on screen; without it the page snapped back to admission.
    await shopOnly.checkout()
    precondition(shopOnly.settlement?.playerSettlement.total == 12)
    precondition(shopOnly.settlement?.wallet?.balanceAfter == 88)
    precondition(shopOnly.settlement?.chargeItems.first?.label == "入场费")
    precondition(shopOnly.summary?.activeSession == nil, "The session is settled server-side")
    precondition(shopOnly.settlement != nil, "The receipt must outlive the refresh that clears the session")
    shopOnly.clearSettlement()
    precondition(shopOnly.settlement == nil && shopOnly.shopBillingState == "未入场")

    // A machine link afterwards must leave shop-only mode behind.
    await shopOnly.handleInvocation(origin.appendingPathComponent("t/store/device"))
    precondition(!shopOnly.isShopOnly && shopOnly.machine != nil && shopOnly.ticket != nil)
    precondition(shopOnly.shopBillingState == "", "A device link keeps the machine name, not the billing state")
    // An unusable link clears the shop and fails without touching the previous session.
    await shopOnly.handleInvocation(URL(string: "https://link-beta.neri.moe/not-a-link")!)
    precondition(!shopOnly.isShopOnly && shopOnly.shopCode == nil && shopOnly.ticket == nil)
    for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("prism.operation.\(origin.absoluteString).\(testUser).") { UserDefaults.standard.removeObject(forKey:key) }
    print("App Clip native visit checks passed")
  }
}
