// Run with test/native/run-prism-real-check.sh against a running end-to-end stack (PRiSM scripts/e2e-ha).
// Unlike the other native checks nothing here is faked on the network: PrismAPI and MachineLoginViewModel
// are the production sources, talking HTTP and a real URLSessionWebSocketTask to the platform, which
// talks to a real Home Assistant, with the real firmware watcher (a macOS build of hinata-aimeio-rs)
// as the HINATA IO. Only sign-in, location and Live Activities are the local stubs from the fixtures.
import Foundation

private let env = ProcessInfo.processInfo.environment
private func setting(_ key: String) -> String {
  guard let value = env[key] else { fatalError("Missing \(key)") }
  return value
}

private var passed = 0
private func check(_ ok: Bool, _ message: String, detail: @autoclosure () -> String = "") {
  if ok { passed += 1; print("  ok    \(message)") }
  else { print("  FAIL  \(message) \(detail())"); exit(1) }
}

/// Home Assistant as the shop's owner would drive it from outside the platform.
enum HA {
  static let url = URL(string: setting("PRISM_E2E_HA_URL"))!
  static let token = setting("PRISM_E2E_HA_TOKEN")

  private static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
    var request = URLRequest(url: url.appendingPathComponent(path))
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    let (data, response) = try await URLSession.shared.data(for: request)
    precondition((response as! HTTPURLResponse).statusCode < 300, "Home Assistant \(path)")
    return data
  }
  static func call(_ domain: String, _ service: String, _ data: [String: Any]) async throws {
    _ = try await request("api/services/\(domain)/\(service)", method: "POST", body: data)
  }
  static func state(_ entity: String) async throws -> (state: String, attributes: [String: Any]) {
    let object = try JSONSerialization.jsonObject(with: try await request("api/states/\(entity)")) as! [String: Any]
    return (object["state"] as! String, object["attributes"] as! [String: Any])
  }
  static func reset() async throws {
    try await call("switch", "turn_on", ["entity_id": "switch.decorative_lights"])
    try await call("input_boolean", "turn_off", ["entity_id": "input_boolean.lounge_power"])
    try await call("climate", "set_hvac_mode", ["entity_id": "climate.hvac", "hvac_mode": "cool"])
    try await call("climate", "set_temperature", ["entity_id": "climate.hvac", "temperature": 21])
    try await call("climate", "set_hvac_mode", ["entity_id": "climate.heatpump", "hvac_mode": "heat"])
    try await call("climate", "set_temperature", ["entity_id": "climate.heatpump", "temperature": 20])
  }

  /// Entities the platform read over REST since `since`, from Home Assistant's own access log. The
  /// platform sends no User-Agent, which is what tells it from this check.
  static func platformReads(since: Date) -> [String] {
    let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let output = shell("docker", ["logs", "--since", formatter.string(from: since), "prism-e2e-ha"])
    let pattern = try! NSRegularExpression(pattern: #"\[aiohttp\.access\] \S+ \[[^\]]*\] "GET /api/states/(\S+) HTTP/[\d.]+" \d+ \d+ "[^"]*" "([^"]*)""#)
    var reads: [String] = []
    for line in output.split(separator: "\n") {
      let text = String(line)
      guard let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let entity = Range(match.range(at: 1), in: text), let agent = Range(match.range(at: 2), in: text),
            text[agent] == "-" else { continue }
      reads.append(String(text[entity]))
    }
    return reads.sorted()
  }
}

@discardableResult func shell(_ tool: String, _ arguments: [String]) -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = [tool] + arguments
  let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
  try! process.run()
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return String(decoding: data, as: UTF8.self)
}

/// The real firmware watcher, one process.
final class IoSim {
  private var process: Process?
  func start() throws {
    precondition(process?.isRunning != true)
    let directory = setting("PRISM_E2E_IO_DIR")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: setting("PRISM_E2E_IO_BIN"))
    process.currentDirectoryURL = URL(fileURLWithPath: directory)
    process.environment = env.merging(["SEGATOOLS_CONFIG_PATH": "\(directory)/a.ini", "RUST_LOG": "hinata_mac_test=debug"]) { $1 }
    FileManager.default.createFile(atPath: "\(directory)/a.log", contents: nil)
    let log = try FileHandle(forWritingTo: URL(fileURLWithPath: "\(directory)/a.log"))
    process.standardOutput = log; process.standardError = log
    try process.run()
    self.process = process
  }
  func stop() {
    if let pid = process?.processIdentifier, process?.isRunning == true { kill(pid, SIGKILL) }
    process?.waitUntilExit()
    process = nil
  }
}

/// Whether the platform has the shop's Home Assistant connection marked as watched.
private func platformIsWatching() -> Bool {
  shell("\(setting("PRISM_E2E_ROOT"))/scripts/e2e-ha/d1.sh", ["SELECT count(*) AS n FROM ha_event_connections"]).contains("\"n\": 1")
}

@MainActor private func waitUntil(_ what: String, seconds: Double = 10, _ predicate: () async -> Bool) async {
  let deadline = Date().addingTimeInterval(seconds)
  while Date() < deadline {
    if await predicate() { return }
    try? await Task.sleep(nanoseconds: 50_000_000)
  }
  print("  FAIL  timed out waiting for \(what)"); exit(1)
}

// What the player is shown, read from the page the platform sent.
@MainActor private func air(_ model: MachineLoginViewModel) -> PrismClimate? { model.page?.climate(id: "climate")?.state }
@MainActor private func offersPowerOn(_ model: MachineLoginViewModel) -> Bool { model.page?.hasButton(id: "power") == true }
@MainActor private func unreadable(_ model: MachineLoginViewModel) -> Bool {
  model.page?.allBlocks().contains { if case .unknown = $0 { return true }; return false } ?? true
}
@MainActor private func shown(_ model: MachineLoginViewModel) -> String {
  "blocks=\(model.page?.allBlocks().map(\.id) ?? [])"
}
/// Presses a button the page offers, as a tap on it does.
@MainActor private func press(_ model: MachineLoginViewModel, _ id: String) async {
  for block in model.page?.allBlocks() ?? [] {
    if case .button(let button) = block, button.id == id { await model.press(button); return }
  }
  print("  FAIL  the page offers no button \(id): \(shown(model))"); exit(1)
}

@MainActor private func player(_ origin: URL) -> MachineLoginViewModel {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.httpCookieStorage!.setCookie(HTTPCookie(properties: [
    .name: "arcadelink_session", .value: setting("PRISM_E2E_PLAYER_TOKEN"), .domain: origin.host!, .path: "/", .originURL: origin,
  ])!)
  return MachineLoginViewModel(api: PrismAPI(configuration: configuration, origin: origin))
}

@main struct PrismRealCheck {
  @MainActor static func main() async throws {
    refuseKeychainDialogs()
    let origin = URL(string: setting("PRISM_E2E_ORIGIN"))!
    let shop = setting("PRISM_E2E_SHOP")
    let io = IoSim()
    defer { io.stop() }
    shell("pkill", ["-x", "io_sim"])
    try await HA.reset()
    await waitUntil("nothing watched", seconds: 20) { !platformIsWatching() }

    print("== 休息室：没有 IO 监听（读页面时当场问 HA）")
    do {
      let since = Date()
      let model = player(origin)
      await model.start(shopCode: shop, publicId: setting("PRISM_E2E_LOUNGE"))
      check(model.state == .ready && model.ticket != nil && model.errorMessage == nil, "扫码进入页面", detail: "\(model.state) \(String(describing: model.errorMessage))")
      check(!unreadable(model), "平台下发的每个区块 App Clip 都认得", detail: shown(model))
      check(offersPowerOn(model), "页面按 HA 的实际状态给出开机按钮", detail: shown(model))
      check(air(model)?.mode == "heat" && air(model)?.temperature == 20, "空调状态来自 HA（制热 20°）", detail: "\(String(describing: air(model)))")
      try await Task.sleep(nanoseconds: 3_500_000_000)
      let reads = HA.platformReads(since: since)
      check(reads == ["climate.heatpump", "input_boolean.lounge_power"], "读一次页面，HA 只收到休息室两个实体各 1 次读取，之后不轮询", detail: "\(reads)")

      let beforeAction = Date()
      await press(model, "power")
      let on = try await HA.state("input_boolean.lounge_power").state
      check(on == "on" && !offersPowerOn(model) && model.waitingButtonId == nil, "开机：HA 真的打开了，操作的回答已经是开机后的页面", detail: "HA=\(on) \(shown(model)) \(String(describing: model.inlineNotice))")
      await model.climate("climate.set_temperature", ["temperature": 22.0])
      try await Task.sleep(nanoseconds: 800_000_000)
      let temperature = try await HA.state("climate.heatpump").attributes["temperature"] as? Double
      check(temperature == 22 && air(model)?.temperature == 22, "调温：HA 的温度变成 22°，页面显示后端读回的值", detail: "HA=\(String(describing: temperature)) page=\(String(describing: air(model))) \(String(describing: model.inlineNotice))")
      let after = HA.platformReads(since: beforeAction)
      check(!after.isEmpty && Set(after).isSubset(of: ["climate.heatpump", "input_boolean.lounge_power"]), "开机和调温之后后端只回读这台设备", detail: "\(after)")
      await model.setSceneActive(false)
    }

    print("\n== 机台A：IO 在监听（事件驱动，真实 WebSocket）")
    do {
      // The platform remembers what it last saw of this machine. An IO that connects to find off a
      // machine last seen on is held as if the power had just gone — a state a real IO, powered by that
      // machine, cannot be in, but the simulator can. So whatever an earlier run left behind, first let
      // the platform watch the machine go off.
      try await HA.reset()
      try io.start()
      await waitUntil("the platform to watch the machine while on", seconds: 30) { platformIsWatching() }
      try await HA.call("switch", "turn_off", ["entity_id": "switch.decorative_lights"])
      await waitUntil("it to see the machine go off", seconds: 10) { !platformIsWatching() }
      io.stop()
      try io.start()
      await waitUntil("the platform to watch", seconds: 25) { platformIsWatching() }
      try await Task.sleep(nanoseconds: 800_000_000)
      let since = Date()
      let model = player(origin)
      await model.start(shopCode: shop, publicId: setting("PRISM_E2E_A"))
      check(model.state == .ready && model.errorMessage == nil, "扫码进入页面", detail: "\(model.state) \(String(describing: model.errorMessage))")
      check(!unreadable(model) && offersPowerOn(model) && air(model)?.temperature == 21, "页面带着已监听的当前状态（关机 / 21°）", detail: shown(model))
      try await Task.sleep(nanoseconds: 1_500_000_000)

      await press(model, "power")
      check(model.waitingButtonId == "power" || !offersPowerOn(model), "开机后以后端读回或推送为准（不是 HA 回 200 就算数）", detail: "\(shown(model)) \(String(describing: model.inlineNotice))")
      await waitUntil("the page that says it is on") { model.waitingButtonId == nil && !offersPowerOn(model) }
      check(try await HA.state("switch.decorative_lights").state == "on", "页面往下走时，HA 里确实已开")
      check(model.page?.cards?.captureUi != nil, "开机后页面给出刷卡和在读卡器上添加卡片", detail: shown(model))

      try await HA.call("climate", "set_temperature", ["entity_id": "climate.hvac", "temperature": 25])
      await waitUntil("the push of the temperature", seconds: 4) { air(model)?.temperature == 25 }
      check(true, "HA 里把空调设成 25°：页面经 WebSocket 得知变化，立刻显示 25°")
      let quiet = HA.platformReads(since: since)
      check(quiet.isEmpty, "监听期间平台没有向 HA 读取任何东西", detail: "\(quiet)")

      // Switched off elsewhere: the page is told, and since the IO lives in that machine the platform
      // stops counting on it at once. From then on the page's reads ask Home Assistant.
      let off = Date()
      try await HA.call("switch", "turn_off", ["entity_id": "switch.decorative_lights"])
      await waitUntil("the push of the switch-off", seconds: 4) { offersPowerOn(model) }
      check(true, "HA 里把机台关掉：页面立刻回到开机页")
      await waitUntil("the watch of a machine without power to be released", seconds: 10) { !platformIsWatching() }
      try await Task.sleep(nanoseconds: 3_000_000_000)
      let afterOff = HA.platformReads(since: off)
      check(Set(afterOff).isSubset(of: ["climate.hvac", "switch.decorative_lights"]), "机台断电后监听立刻撤销，读取只涉及这台机台", detail: "\(afterOff)")
      io.stop()

      // On again and watched again, to see the IO leave while the machine stays on.
      try await HA.call("switch", "turn_on", ["entity_id": "switch.decorative_lights"])
      try io.start()
      await waitUntil("the platform to watch again", seconds: 30) { platformIsWatching() }
      await waitUntil("the page that says it is on", seconds: 30) { !offersPowerOn(model) && model.page?.cards != nil }
      check(true, "机台重新开机、IO 回来：页面回到刷卡页")
      try await Task.sleep(nanoseconds: 1_500_000_000)
      try await HA.call("climate", "set_temperature", ["entity_id": "climate.hvac", "temperature": 27])
      await waitUntil("the push of 27", seconds: 4) { air(model)?.temperature == 27 }

      // The IO goes away: the hub says the page changed, and reading it asks Home Assistant.
      let lost = Date()
      io.stop()
      await waitUntil("the read after the IO left", seconds: 20) { HA.platformReads(since: lost).count >= 2 }
      try await Task.sleep(nanoseconds: 3_000_000_000)
      let reads = HA.platformReads(since: lost)
      check(Set(reads) == ["climate.hvac", "switch.decorative_lights"], "IO 掉线：页面重读时只向 HA 问这台机台的两个实体", detail: "\(reads)")
      try await Task.sleep(nanoseconds: 4_000_000_000)
      check(HA.platformReads(since: lost) == reads, "读完就停，不轮询", detail: "\(HA.platformReads(since: lost))")
      check(!offersPowerOn(model) && air(model)?.temperature == 27, "读到的是 HA 此刻的值（开机 / 27°）", detail: "\(shown(model)) \(String(describing: air(model)))")

      // It returns: watched again, told by push, and nothing is asked of Home Assistant.
      try io.start()
      await waitUntil("the platform to watch once more", seconds: 30) { platformIsWatching() }
      try await Task.sleep(nanoseconds: 2_000_000_000)
      let back = Date()
      try await HA.call("climate", "set_temperature", ["entity_id": "climate.hvac", "temperature": 22])
      await waitUntil("the push of 22", seconds: 4) { air(model)?.temperature == 22 }
      check(HA.platformReads(since: back).isEmpty, "重新监听之后又靠推送更新，平台不再读 HA", detail: "\(HA.platformReads(since: back))")
      await model.setSceneActive(false)
    }
    print("\n\(passed) real-platform checks passed")
  }
}
