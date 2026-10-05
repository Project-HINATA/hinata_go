import Foundation

final class ScanCounts {
  private let lock = NSLock()
  private var counts: [String: Int] = [:]
  func increment(_ key: String) { lock.lock(); defer { lock.unlock() }; counts[key, default: 0] += 1 }
  func read(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[key, default: 0] }
  func reset() { lock.lock(); defer { lock.unlock() }; counts.removeAll() }
}

@main struct PrismScanCheck {
  @MainActor static func waitUntil(_ predicate: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(10)
    while !predicate() && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(predicate(), "Timed out waiting for a controlled request")
  }

  @MainActor static func main() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var budget = PrismReadBackoff()
    for delay in [5.0, 10.0, 20.0, 30.0, 60.0, 60.0] {
      budget.fail(now: now, random: 0.5)
      precondition(abs(budget.remaining(now: now) - delay) < 0.01)
    }
    budget.fail(retryAfter: 120, now: now, random: 1)
    precondition(budget.remaining(now: now) == 120)
    budget.succeed(); precondition(budget.remaining(now: now) == 0)
    precondition(PrismAPI.retryAfter("60", now: now) == 60)
    precondition(PrismAPI.retryAfter("Tue, 14 Nov 2023 22:14:20 GMT", now: now) == 60)
    precondition(PrismAPI.retryAfter("invalid", now: now) == nil)

    let counts = ScanCounts()
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FixtureProtocol.self]
    let origin = URL(string: "https://link-beta.neri.moe")!
    let api = PrismAPI(configuration: config, origin: origin)
    var unavailable = false
    FixtureProtocol.handler = { request in
      let path = request.url!.path
      counts.increment(path)
      func ok(_ data: [String: Any]) -> (Int, [String: Any]) { (200, ["data": data]) }
      switch path {
      case "/api/v1/me":
        if unavailable { return (503, ["error": ["code": "TEMPORARY", "message": "稍后重试"], "headers": ["Retry-After": "60"]]) }
        return ok(["user": ["id": "u", "username": "test", "displayName": "测试玩家"]])
      case "/api/v1/machines/session/start":
        return ok(["ticket": "v1.opaque-ticket", "expiresIn": 300, "machine": ["publicId": "device", "name": "测试机台", "capabilities": ["card": true, "power": true, "mahjong": true], "shop": ["name": "测试店铺", "latitude": 35, "longitude": 139, "radiusMeters": 80, "machineGeo": false, "billingEnabled": false]]])
      case "/api/v1/cards": return ok(["cards": [["id": "card", "label": "测试 Aime", "accessCode": "01234567890123456789"]]])
      case "/api/v1/devices/session/state":
        precondition(request.url!.query!.contains("includePower=0"))
        return ok(["gate": "ready", "power": "unmanaged", "mahjong": ["capacity": 4, "seats": []]])
      case "/api/v1/devices/session/power": return ok(["power": "on"])
      case "/api/v1/shops/store": return ok(["shop": ["name": "测试店铺", "billingEnabled": false, "checkinGeo": false, "checkoutGeo": false, "autoRegister": false, "botContact": "", "timeZone": "Asia/Tokyo"], "membership": NSNull(), "entryPricing": []])
      case "/api/v1/auth/passkey": return ok(["ok": true])
      default: preconditionFailure("Unexpected path: \(path)")
      }
    }
    // Typed and JSON reads preserve the status, code and Retry-After; failures are not cached.
    unavailable = true
    do { _ = try await api.me(); preconditionFailure("Expected 503") }
    catch let error as PrismAPIError {
      precondition(error.isTransientReadFailure && error.code == "TEMPORARY" && error.retryAfter == 60)
    }
    unavailable = false
    _ = try await api.me()
    precondition(counts.read("/api/v1/me") == 2)
    let fallback = api.webFallbackURL(ticket: "v1.opaque+ticket&part#x")!
    precondition(fallback.path == "/m" && fallback.query == nil && fallback.host == origin.host)
    let fragment = URLComponents(string: "?" + fallback.fragment!)!
    precondition(fragment.queryItems?.first?.value == "v1.opaque+ticket&part#x")

    // Simultaneous subscribers share transport; canceling one never cancels the other.
    FixtureProtocol.holdNextShopResponse = true
    let first = Task { try await api.requestJSON(path: "/api/v1/shops/store") }
    try await waitUntil { FixtureProtocol.heldReply != nil }
    let canceled = Task { try await api.requestJSON(path: "/api/v1/shops/store") }
    try await Task.sleep(nanoseconds: 20_000_000)
    canceled.cancel()
    let reply = FixtureProtocol.heldReply!; FixtureProtocol.heldReply = nil; reply()
    _ = try await first.value
    do { _ = try await canceled.value; preconditionFailure("Subscriber cancellation must surface") }
    catch is CancellationError {}
    _ = try await api.requestJSON(path: "/api/v1/shops/store")
    precondition(counts.read("/api/v1/shops/store") == 1)
    _ = try await api.requestJSON(path: "/api/v1/auth/passkey", body: [:])
    _ = try await api.requestJSON(path: "/api/v1/shops/store")
    precondition(counts.read("/api/v1/shops/store") == 2, "Successful mutations invalidate account reads")
    _ = try await api.atOrigin(URL(string: "https://other.example")!).requestJSON(path: "/api/v1/shops/store")
    precondition(counts.read("/api/v1/shops/store") == 3, "Origins never share cached membership")

    // Observe production state publication while both slow boundaries are held.
    counts.reset()
    FixtureProtocol.holdNextIdentityResponse = true
    FixtureProtocol.holdNextPowerResponse = true
    let model = MachineLoginViewModel(api: api)
    let launch = Task { await model.handleResolvedInvocation(origin.appendingPathComponent("t/store/device")) }
    try await waitUntil { model.machine != nil && FixtureProtocol.heldIdentityReply != nil }
    precondition(model.state == .loadingCards && model.machine?.shop.name == "测试店铺")
    let identityReply = FixtureProtocol.heldIdentityReply!; FixtureProtocol.heldIdentityReply = nil; identityReply()
    await launch.value
    try await waitUntil { FixtureProtocol.heldPowerReply != nil }
    precondition(model.state == .ready && model.canUseCards && model.cards.count == 1)
    precondition(model.playerStateLoaded && model.errorMessage == nil, "Initial context must decode and settle")
    try await Task.sleep(nanoseconds: 6_500_000_000)
    precondition(counts.read("/api/v1/devices/session/state") >= 2)
    precondition(counts.read("/api/v1/shops/store") == 1, "Shop reads: \(counts.read("/api/v1/shops/store"))")
    precondition(counts.read("/api/v1/me") == 1, "Identity reads: \(counts.read("/api/v1/me"))")
    precondition(counts.read("/api/v1/devices/session/power") == 1, "Slow HA must not overlap or block cards")
    let powerReply = FixtureProtocol.heldPowerReply!; FixtureProtocol.heldPowerReply = nil; powerReply()
    try await waitUntil { model.deviceState?.power == "on" }
    await model.setSceneActive(false)
    let beforeBackground = counts.read("/api/v1/devices/session/state")
    try await Task.sleep(nanoseconds: 3_300_000_000)
    precondition(counts.read("/api/v1/devices/session/state") == beforeBackground)
    print("PRiSM scan checks passed: opaque fallback, error status, cache, first paint and isolated polling")
  }
}
