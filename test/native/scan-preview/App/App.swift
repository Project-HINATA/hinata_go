import SwiftUI

@main @MainActor struct ScanPreviewApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model: MachineLoginViewModel
  /// Set to look at a real (local) server instead of fixtures: `PRISM_API_ORIGIN` (a loopback
  /// origin), `PRISM_PREVIEW_SESSION` (a signed-in session token) and `PRISM_PREVIEW_LINK` (the
  /// scanned or shop link to open).
  private static let live = ProcessInfo.processInfo.environment["PRISM_PREVIEW_LINK"].flatMap(URL.init(string:))

  init() {
    if let live = Self.live {
      let environment = ProcessInfo.processInfo.environment
      if let token = environment["PRISM_PREVIEW_SESSION"], let host = PrismAPI.defaultOrigin.host {
        HTTPCookieStorage.shared.setCookie(HTTPCookie(properties: [.domain: host, .path: "/", .name: "arcadelink_session", .value: token])!)
      }
      _model = StateObject(wrappedValue: MachineLoginViewModel(api: .shared))
      return
    }
    let checkout = ProcessInfo.processInfo.arguments.contains("checkout-insufficient")
    // `notices=<level>:<text>;…` makes every page action answer with those inline notices, so
    // Screenshots.swift can show how each nature looks where the player acted.
    var answerNotices: [[String: Any]]? = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("notices=") }.map { argument in
      argument.dropFirst(8).split(separator: ";").map { item in
        let pair = item.split(separator: ":", maxSplits: 1).map(String.init)
        return ["code": "PREVIEW", "level": pair[0], "display": "inline", "flow": "none", "title": NSNull(), "body": pair[1], "actions": []]
      }
    }
    if let codes = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("notice-codes=") }) {
      answerNotices = codes.dropFirst(13).split(separator: ",").map { PageFixtures.notice(String($0)) }
    }
    let auditCode = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("audit-code=") }.map { String($0.dropFirst(11)) }
    let audit = PageFixtures.noticeScreenshots.first { $0["code"] as? String == auditCode }
    func auditPage() -> [String: Any]? {
      guard let audit, let name = audit["page"] as? String else { return nil }
      var page = name == "redeemForm" ? PageFixtures.shopPage(name) : PageFixtures.page(name)
      page["shop"] = "测试店铺"
      return page
    }
    if let audit, let codes = audit["notices"] as? [String] { answerNotices = codes.map(PageFixtures.notice) }
    let authHeld = ProcessInfo.processInfo.arguments.contains("auth-held")
    FixtureProtocol.holdNextIdentityResponse = authHeld
    FixtureProtocol.handler = { request in
      func ok(_ data: [String: Any]) -> (Int, [String: Any]) { (200, ["data": data]) }
      if checkout {
        switch request.url!.path {
        case "/api/v1/me": return ok(["user": ["id": "u", "username": "test", "displayName": "测试玩家"]])
        case "/api/v1/shops/store": return ok(["shop": ["name": "测试店铺", "billingEnabled": true, "checkinGeo": false, "checkoutGeo": false, "autoRegister": false, "botContact": "", "timeZone": "Asia/Tokyo"], "membership": ["playerId": "p", "identityBound": true], "entryPricing": []])
        case "/api/v1/shops/store/player/me": return ok(["wallet": [], "activeSession": ["id": "visit", "startedAt": "2026-10-05T06:00:00Z"]])
        // The shop page the server draws: a live bill the phone computes from these read-only
        // inputs (an entry fee of 12), with checkout in the footer.
        case "/api/v1/shops/store/platform-binding": return ok(PageFixtures.binding)
      case "/api/v1/shops/store/player/page": return ok(Self.checkoutPage)
        case "/api/v1/shops/store/player/action":
          if let answerNotices { return ok(["ok": false, "page": Self.checkoutPage, "notices": answerNotices]) }
          return (409, ["error": ["code": "INSUFFICIENT_BALANCE", "message": "Insufficient currency holdings for this operation.", "notice": PageFixtures.notice("INSUFFICIENT_BALANCE")]])
        case "/api/v1/shops/store/player/billing-inputs": return ok(Self.billingInputs)
        case "/api/v1/shops/store/player/checkout/preview": return ok(["settlementPreview": ["total": 12], "chargeItems": [], "adjustments": []])
        case "/api/v1/shops/store/player/checkout/confirm": return (409, ["error": ["code": "INSUFFICIENT_BALANCE", "message": "Insufficient currency holdings for this operation.", "notice": PageFixtures.notice("INSUFFICIENT_BALANCE")]])
        default: return ok([:])
        }
      }
      switch request.url!.path {
      case "/api/v1/me": return ok(["user": ["id": "u", "username": "test", "displayName": "测试玩家"]])
      case "/api/v1/machines/session/start":
        return ok(["ticket": "v1.opaque-ticket", "expiresIn": 300, "machine": ["publicId": "device", "name": "测试机台", "capabilities": ["card": true, "power": true, "mahjong": true], "shop": ["name": "测试店铺", "latitude": 35, "longitude": 139, "radiusMeters": 80, "machineGeo": false, "billingEnabled": false]]])
      case "/api/v1/cards":
        if auditCode == "STATE_NO_CARDS" { return ok(["cards": []]) }
        if auditCode == "STATE_CARDS_LOADING" { Thread.sleep(forTimeInterval: 8) }
        if auditCode == "STATE_CARDS_ERROR" { return (503, ["error": ["code": "CLIENT_NETWORK_ERROR", "message": "unavailable", "notice": PageFixtures.notice("CLIENT_NETWORK_ERROR")]]) }
        return ok(["cards": [["id": "card", "label": "测试 Aime", "accessCode": "01234567890123456789"]]])
      // The page names the shop as this preview's server does everywhere else.
      case "/api/v1/devices/session/page":
        // `page=<fixture>` among the launch arguments shows that page instead (see Screenshots.swift).
        let chosen = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("page=") }.map { String($0.dropFirst(5)) }
        var page = auditPage() ?? PageFixtures.page(chosen ?? "cardsCapture")
        page["shop"] = "测试店铺"
        return ok(page)
      case "/api/v1/devices/session/cards/capture":
        if audit?["captureStatus"] as? String == "starting" { Thread.sleep(forTimeInterval: 8) }
        return ok(["captureId": "audit-capture", "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))])
      case "/api/v1/devices/session/cards/capture/audit-capture":
        if request.httpMethod == "DELETE" { return ok(["ok": true]) }
        let status = audit?["captureStatus"] as? String ?? "waiting"
        return ok(["status": ["starting", "left"].contains(status) ? "waiting" : status])
      case "/api/v1/devices/session/action" where answerNotices != nil:
        let chosen = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("page=") }.map { String($0.dropFirst(5)) }
        var page = auditPage() ?? PageFixtures.page(chosen ?? "cardsCapture")
        page["shop"] = "测试店铺"
        if auditCode == "TICKET_EXPIRED" {
          return (410, ["error": ["code": "TICKET_EXPIRED", "message": PageFixtures.notice("TICKET_EXPIRED")["body"]!, "notice": PageFixtures.notice("TICKET_EXPIRED")]])
        }
        return ok(["ok": true, "page": page, "notices": answerNotices!])
      case "/api/v1/shops/store/platform-binding": return ok(PageFixtures.binding)
      case "/api/v1/shops/store/player/page":
        let view = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "view" }?.value
        let item = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "item" }?.value
        if view == "history" { return ok(PageFixtures.shopPage(item == nil ? "historyList" : "historyDetail")) }
        return ok(PageFixtures.shopPage(view == "redeem" ? "redeemForm" : "billSheet"))
      case "/api/v1/shops/store/player/action":
        let redeem = ProcessInfo.processInfo.arguments.contains("sheet-preview=redeem")
        return ok(["ok": false, "page": PageFixtures.shopPage(redeem ? "redeemForm" : "billSheet"), "notices": [PageFixtures.notice(redeem ? "REDEEM_CODE_NOT_FOUND" : "INSUFFICIENT_BALANCE")]])
      case "/api/v1/devices/session/ws": return (404, ["error": ["code": "NOT_FOUND", "message": "Not found"]])
      case "/api/v1/devices/report": return ok([:])
      case "/api/v1/shops/store": return ok(["shop": ["name": "测试店铺", "billingEnabled": false, "checkinGeo": false, "checkoutGeo": false, "autoRegister": false, "botContact": "", "timeZone": "Asia/Tokyo"], "membership": NSNull(), "entryPricing": []])
      default: return (404, ["error": ["code": "UNEXPECTED", "message": "Unexpected preview request"]])
      }
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    _model = StateObject(wrappedValue: MachineLoginViewModel(api: PrismAPI(configuration: configuration)))
  }
  /// The shop page the server draws: a live bill the phone computes from these read-only
  /// inputs (an entry fee of 12), with checkout in the footer.
  private static var checkoutPage: [String: Any] {
    var page = PageFixtures.shopPage("shopLive")
    var blocks = page["blocks"] as! [[String: Any]]
    blocks[0]["billingInputs"] = billingInputs
    page["blocks"] = blocks
    // The server words its page in the phone's language; checking out needs no location here.
    var footer = page["footer"] as! [[String: Any]]
    footer[0]["needsLocation"] = false
    if Locale.preferredLanguages.first?.hasPrefix("en") == true { footer[0]["label"] = "Check out" }
    page["footer"] = footer
    return page
  }
  /// What the server hands the phone to price the visit: one entry fee of 12.
  private static let billingInputs: [String: Any] = ["playerId": "p", "billingSnapshot": [
    "version": 1, "capturedAt": "2026-10-05T07:00:00.000Z", "assetDefinitions": [], "pricingReleases": [],
    "currentPricingConfigs": [["id": "fee", "kind": "charge.fixed", "name": "入场费", "enabled": true, "status": "active",
      "versionId": "fee-v1", "version": 1, "provider": ["id": "fee", "label": "入场费", "amount": 12],
      "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z"]],
    "players": [["playerId": "p", "holdings": [], "pastAppliedAdjustments": [], "pricingPaidHistory": [:], "capPaidHistory": [:],
      "sessions": [["id": "visit", "playerId": "p", "startedAt": "2026-10-05T06:00:00.000Z", "status": "active",
        "pricingConfigIds": ["fee"], "pricingConfigId": "fee", "paymentStatus": "unpaid", "label": "entry"]]]],
  ]]

  var body: some Scene {
    WindowGroup {
      MachineLoginView(presentsAppClipNotice: true).environmentObject(model)
        .onChange(of: scenePhase) { _, phase in
          Task { await model.setSceneActive(phase == .active) }
        }
        .task {
          if let live = Self.live { await model.handleResolvedInvocation(live); return }
          let path = ProcessInfo.processInfo.arguments.contains("checkout-insufficient") ? "store" : "store/device"
          await model.handleResolvedInvocation(URL(string: "https://link.neri.moe/t/\(path)")!)
        }
    }
  }
}
