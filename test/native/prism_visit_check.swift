// Run with test/native/run-prism-visit-check.sh. Auth and location are local stubs;
// Models, API decoding and the App Clip state machine are the production sources.
import Foundation

@MainActor final class PasskeyAuthenticationService {
  func authenticate(options: PasskeyRequestOptions) async throws -> PasskeyAssertion { throw CancellationError() }
}
@MainActor final class MunetAuthenticationService {
  func authenticate() async throws -> String { throw CancellationError() }
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

@main struct PrismVisitCheck {
  @MainActor static func main() async throws {
    var mahjongSeats: [[String:Any]] = []
    var member = false, active = false
    var billing = true
    var capabilities = ["power":true,"coin":true,"card":true,"door":true]
    var checkoutCalls = 0, coinCalls = 0, sessionStarts = 0
    var checkoutIds: [String] = []
    let testUser = UUID().uuidString
    FixtureProtocol.handler = { request in
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
      case "/api/v1/shops/store": return ok(["shop":["billingEnabled":billing,"checkinGeo":true,"checkoutGeo":true,"autoRegister":false,"botContact":"QQ Bot","timeZone":"Asia/Tokyo"],"membership":member ? ["playerId":"p"] : NSNull(),"entryPricing":[]])
      case "/api/v1/devices/session/state": return ok(["gate":!billing ? "ready" : member ? (active ? "ready" : "entry") : "qq", "power":"unknown","mahjong":["capacity":4,"seats":mahjongSeats]])
      case "/api/v1/shops/store/qq-binding": return ok(["code":"ABC123","expiresAt":"2999-01-01T00:00:00Z"])
      case "/api/v1/shops/store/player/me": return ok(["wallet":[],"activeSession":active ? ["id":"entry","startedAt":"2026-09-12T00:00:00Z"] : NSNull()])
      case "/api/v1/shops/store/player/assets": return ok(["holdings":[]])
      case "/api/v1/shops/store/player/sessions/history": return ok(["sessions":[]])
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
      case "/api/v1/shops/store/player/checkout/preview": return ok(["settlementPreview":["total":12],"chargeItems":[],"adjustments":[]])
      case "/api/v1/shops/store/player/checkout/confirm":
        checkoutIds.append(body["operationId"] as! String); checkoutCalls += 1
        if checkoutCalls == 1 { return (400,["error":["code":"INSUFFICIENT_BALANCE","message":"余额不足"]]) }
        if checkoutCalls == 2 { throw URLError(.networkConnectionLost) }
        active = false; return ok([:])
      default: preconditionFailure("Unexpected API path: \(path)")
      }
    }
    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
    let model = MachineLoginViewModel(api: PrismAPI(configuration: config))
    await model.start(shopCode:"store",publicId:"device")
    precondition(model.state == .ready && model.deviceState?.gate == "qq")
    precondition(model.binding?.code == "ABC123")
    member = true; await model.refreshVisit(); precondition(model.deviceState?.gate == "entry")
    await model.device("door.open", consent:true)
    precondition(model.doorPassword?.temporaryPassword == "12345678" && model.summary?.activeSession != nil)
    precondition(model.canUseCards && model.deviceState?.power == "unknown")
    await model.device("coin"); await model.device("coin"); precondition(coinCalls == 1)
    precondition(model.state == .expired && model.ticket == nil && sessionStarts == 1)
    await model.refreshVisit(); precondition(sessionStarts == 1)
    await model.start(shopCode: "store", publicId: "device")
    await model.login(card:model.cards[0]); precondition(model.state == .expired && model.ticket == nil)
    await model.previewCheckout(); precondition(model.checkoutPreview?.settlementPreview.total == 12)
    await model.checkout(); precondition(model.summary?.activeSession != nil)
    await model.checkout(); await model.checkout()
    precondition(checkoutIds[0] != checkoutIds[1] && checkoutIds[1] == checkoutIds[2])
    precondition(model.summary?.activeSession == nil && model.checkoutPreview == nil)
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
    for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("prism.operation.\(testUser).") { UserDefaults.standard.removeObject(forKey:key) }
    print("App Clip native visit checks passed")
  }
}
