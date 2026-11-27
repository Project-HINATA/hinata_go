// Run with test/native/run-prism-visit-check.sh. Auth and location are local stubs;
// Models, API decoding and the App Clip state machine are the production sources.
import Foundation
import Combine

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

/// Waits for a reply the fixture server sends from another thread. A number of yields is not a wait:
/// a fast run gets through them before the reply arrives.
@MainActor func waitUntil(_ done: () -> Bool, seconds: Double = 5) async {
  let deadline = Date().addingTimeInterval(seconds)
  while !done() && Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
}

// Print the failed check for command-line runs where Swift's crash report is unavailable.
private func precondition(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
  if !condition() {
    fputs("\(file):\(line): \(message())\n", stderr)
    exit(1)
  }
}

@main struct PrismVisitCheck {
  @MainActor static func main() async throws {
    refuseKeychainDialogs()
    var timedNotice = try JSONDecoder().decode(PrismNotice.self, from: JSONSerialization.data(withJSONObject: PageFixtures.notice("COIN_SENT")))
    timedNotice.durationMs = 731
    timedNotice.controlDurationMs = 947
    precondition(noticeDuration(timedNotice, onControl: false) == 731_000_000)
    precondition(noticeDuration(timedNotice, onControl: true) == 947_000_000)
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
    // What the platform says a scanned page is right now. The pages themselves are the platform's own.
    var scene = "binding"
    var member = false, active = false
    var signedIn = true
    var billing = true
    var identityBindingRequired = true, identityBound = true
    var bindingRequests = 0, bindingStatus = 200
    var bindingExpiry = "2999-01-01T00:00:00Z"
    var passkeyRequests = 0, passkeyStatus = 200
    let heroUrl: String? = "/api/v1/shops/store/hero?v=abc123"
    var historyReads = 0, assetReads = 0
    var failBillRead = true
    var cardReads = 0, previewReads = 0, serverPreviewReads = 0
    var shopPageReads = 0, shopActionCalls = 0, bindingsRefreshReads = 0
    var redeemCalls = 0, sheetHistoryReads = 0
    var cardsFail = false
    var shopStatus = 200, previewStatus = 200
    let checkoutGeo = true
    /// A shop whose billing only the server can compute: the phone falls back to the server's preview.
    var clientBillingUnavailable = false
    var htmlOutage = false
    var statusReads = 0, pageReads = 0, identityReads = 0, bindingStatusReads = 0
    var failNextStatusRead = false
    var checkoutCalls = 0, sessionStarts = 0
    var checkoutIds: [String] = []
    var lastReceipt: [String: Any]?
    var redeemed = false
    let testUser = UUID().uuidString
    // Everything the page's buttons sent, and how the platform answers the next ones.
    var actions: [[String: Any]] = []
    var shopActions: [[String: Any]] = []
    /// Replies lost on the way back, and replies saying the same operation is still running.
    var lostReplies = 0, pendingReplies = 0
    var swipeRefused = false
    var powerComesOnAtOnce = false
    var climate = (PageFixtures.page("climate")["blocks"] as! [[String: Any]])[0]["state"] as! [String: Any]
    var powerWaitMs: Int?
    var captureStatus = "waiting"
    var captureStarts = 0, captureReads = 0, captureCancels = 0

    func currentPage() -> [String: Any] {
        var page = PageFixtures.page(signedIn ? scene : "signin")
        if scene.hasPrefix("climate"), signedIn, scene != "climateUnknown" {
            page = PageFixtures.changing(page, kind: "climate") { $0["state"] = climate }
        }
        if scene == "powerOff", signedIn, let ms = powerWaitMs {
            var blocks = page["blocks"] as! [[String: Any]]
            let index = blocks.firstIndex { $0["id"] as? String == "power" }!
            var wait = blocks[index]["wait"] as! [String: Any]; wait["ms"] = ms; blocks[index]["wait"] = wait
            page["blocks"] = blocks
        }
        return page
    }
    func liveSnapshotPayload() -> [String: Any] {
      ["playerId": "player", "billingSnapshot": [
        "version": 1, "capturedAt": "2026-09-12T01:00:00.000Z", "assetDefinitions": [], "pricingReleases": [],
        "currentPricingConfigs": [["id": "fee", "kind": "charge.fixed", "name": "入场费", "enabled": true, "status": "active",
          "versionId": "fee-v1", "version": 1, "provider": ["id": "fee", "label": "入场费", "amount": 12],
          "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z"]],
        "players": [["playerId": "player", "holdings": [], "pastAppliedAdjustments": [], "pricingPaidHistory": [:], "capPaidHistory": [:],
          "sessions": [["id": "entry", "playerId": "player", "startedAt": "2026-09-12T00:00:00.123Z", "status": "active",
            "pricingConfigIds": ["fee"], "pricingConfigId": "fee", "paymentStatus": "unpaid", "label": "entry"]]]],
      ]]
    }
    func makeSettledBillPage(title: String? = nil, backLabel: String? = nil, resource: String = "结账成功", includeAccountMenu: Bool = true, receipt: [String: Any]) -> [String: Any] {
      var page = PageFixtures.shopPage("shopSettled")
      page["resource"] = resource
      if let title { page["title"] = title }
      if let backLabel { page["backLabel"] = backLabel }
      if !includeAccountMenu { page.removeValue(forKey: "accountMenu") }
      var bill = (page["blocks"] as! [[String: Any]])[0]
      let settlement = receipt["playerSettlement"] as! [String: Any]
      bill["settledAt"] = settlement["settledAt"]
      if let wallet = receipt["wallet"] as? [String: Any], let after = wallet["balanceAfter"] {
        bill["balanceAfter"] = after
      } else {
        bill.removeValue(forKey: "balanceAfter")
      }
      var preview: [String: Any] = [
        "settlementPreview": ["total": settlement["total"] ?? 0],
        "chargeItems": receipt["chargeItems"] ?? [],
        "adjustments": receipt["adjustments"] ?? [],
      ]
      if let timeline = receipt["timeline"] { preview["timeline"] = timeline }
      bill["preview"] = preview
      page["blocks"] = [bill]
      return page
    }
    func makeShopViewPage(view: String, item: String? = nil, cursor: String? = nil) -> [String: Any] {
      let needsBinding = billing && identityBindingRequired && (!member || !identityBound)
      switch view {
      case "shop":
        if !signedIn { return PageFixtures.shopPage("shopSignIn") }
        if needsBinding && !active { return PageFixtures.shopPage("shopBinding") }
        if active {
          var page = PageFixtures.shopPage(clientBillingUnavailable ? "shopLivePreview" : "shopLive")
          if !clientBillingUnavailable {
            var blocks = page["blocks"] as! [[String: Any]]
            blocks[0]["billingInputs"] = liveSnapshotPayload()
            page["blocks"] = blocks
          }
          var footer = page["footer"] as! [[String: Any]]
          footer[0]["needsLocation"] = checkoutGeo
          page["footer"] = footer
          return page
        }
        if let lastReceipt { return makeSettledBillPage(receipt: lastReceipt) }
        return PageFixtures.shopPage("shopEmpty")
      case "bill":
        if active {
          var page = PageFixtures.shopPage("billSheet")
          if !clientBillingUnavailable {
            var blocks = page["blocks"] as! [[String: Any]]
            blocks[0].removeValue(forKey: "preview")
            blocks[0]["billingInputs"] = liveSnapshotPayload()
            page["blocks"] = blocks
          }
          var footer = page["footer"] as! [[String: Any]]
          footer[0]["needsLocation"] = checkoutGeo
          page["footer"] = footer
          return page
        }
        if let lastReceipt {
          return makeSettledBillPage(title: "账单", resource: "", includeAccountMenu: false, receipt: lastReceipt)
        }
        var empty = PageFixtures.shopPage("shopEmpty")
        empty["title"] = "账单"
        empty["resource"] = ""
        empty.removeValue(forKey: "accountMenu")
        empty["blocks"] = [["kind": "text", "id": "bill-empty", "text": "暂无待结账单", "style": "status", "icon": "receipt", "level": "muted"]]
        return empty
      case "redeem":
        return PageFixtures.shopPage(redeemed ? "redeemDone" : "redeemForm")
      case "history":
        if let item {
          if item == "bill:old" {
            let oldReceipt: [String: Any] = [
              "playerSettlement": ["total": 12, "settledAt": "2026-09-12T01:00:00Z"],
              "chargeItems": [],
              "adjustments": [],
            ]
            return makeSettledBillPage(title: "账单详情", resource: "", includeAccountMenu: false, receipt: oldReceipt)
          }
          let newReceipt = lastReceipt ?? [
            "timeline": ["tracks": [], "events": [], "totals": []],
            "playerSettlement": ["total": 12, "settledAt": "2026-09-12T01:00:00Z"],
            "chargeItems": [],
            "adjustments": [],
            "wallet": ["balanceAfter": 88],
          ]
          return makeSettledBillPage(title: "账单详情", resource: "", includeAccountMenu: false, receipt: newReceipt)
        }
        var page = PageFixtures.shopPage("historyList")
        var list = (page["blocks"] as! [[String: Any]])[0]
        if cursor != nil {
          list["items"] = [[
            "id": "bill:old",
            "group": "9月12日",
            "title": "09:00 – 10:00",
            "titleMeta": "1小时",
            "subtitle": "资产结算",
            "trailing": "12.00",
            "open": ["view": "history", "item": "bill:old"],
          ]]
          list.removeValue(forKey: "moreLabel")
          list.removeValue(forKey: "moreTarget")
        } else {
          list["items"] = [[
            "id": "bill:new",
            "group": "9月12日",
            "title": "09:00 – 10:00",
            "titleMeta": "1小时",
            "subtitle": "资产结算",
            "trailing": "12.00",
            "open": ["view": "history", "item": "bill:new"],
          ]]
          list["moreTarget"] = ["view": "history", "cursor": "30"]
        }
        page["blocks"] = [list]
        return page
      case "wallet":
        return PageFixtures.shopPage("wallet")
      case "bindings":
        return PageFixtures.shopPage("bindings")
      default:
        preconditionFailure("Unexpected shop page view: \(view)")
      }
    }
    func notice(_ code: String, _ level: String, _ body: String) -> [String: Any] {
        ["code": code, "level": level, "display": "inline", "flow": "none", "body": body, "actions": []]
    }

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
      let body = data.isEmpty ? [:] : try JSONSerialization.jsonObject(with: data) as! [String: Any]
      func ok(_ value: [String: Any]) -> (Int, [String: Any]) { (200, ["data": value]) }
      switch path {
      case "/api/v1/machines/session/start":
        sessionStarts += 1
        // Echo the requested machine so routing can be asserted per link.
        let requested = (body["publicId"] as? String) ?? "device"
        return ok(["ticket":"ticket-\(sessionStarts)", "expiresIn":300, "machine":["publicId":requested, "name":"Device", "webOnly":true, "capabilities":["card":true], "shop":["name":"Store", "latitude":35,"longitude":139,"radiusMeters":80,"machineGeo":false,"billingEnabled":billing]]])
      case "/api/v1/appclip/auth/exchange":
        precondition(body["code"] as? String == "oauth-code")
        signedIn = true
        return ok(["ok":true])
      case "/api/v1/auth/passkey/register/options":
        return ok(["challenge":"AQID","rp":["id":"link-beta.neri.moe"],"user":["id":"dXNlcg","name":"test","displayName":"Test"]])
      case "/api/v1/auth/passkey/register":
        passkeyRequests += 1
        let credential = body["credential"] as! [String:Any]
        precondition(credential["type"] as? String == "public-key" && credential["id"] as? String == "credential")
        precondition((credential["clientExtensionResults"] as? [String:String])?.isEmpty == true)
        precondition((credential["response"] as? [String:Any])?["attestationObject"] as? String == "attestation")
        if passkeyStatus != 200 { return (passkeyStatus,["error":["code":"PASSKEY_FAILED","message":"Passkey 验证失败"]]) }
        return ok(["ok":true])
      case "/api/v1/me":
        identityReads += 1
        // Mirrors the server: signed-in state lives in the cookie store.
        return ok(["user": signedIn ? ["id":testUser,"username":"test","displayName":"Test"] : NSNull()])
      case "/api/v1/me/live-activity/start-token":
        precondition(signedIn, "Tokens must be removed before logout invalidates authentication")
        precondition(request.httpMethod == "DELETE", "Start-token retirement must use DELETE")
        precondition(body["clientId"] as? String == PrismAPI.clientId)
        return ok(["ok": true])
      case "/api/v1/auth/logout":
        precondition(StoreVisitLiveActivityManager.shared.unregisteredAll)
        signedIn = false
        return ok(["ok": true])
      case "/api/v1/cards":
        cardReads += 1
        if cardsFail { return (500, ["error": ["code": "UNAVAILABLE", "message": "服务暂时不可用"]]) }
        return ok(["cards":[["id":"card","label":"Aime","accessCode":"01234567890123456789"]]])
      case "/api/v1/shops/store":
        statusReads += 1
        if htmlOutage { return (503, ["rawHTML": "<html>Service temporarily unavailable</html>"]) }
        if shopStatus != 200 { return (shopStatus, ["error": ["code": "SHOP_NOT_FOUND", "message": "没有找到店铺"]]) }
        if failNextStatusRead { failNextStatusRead = false; throw URLError(.networkConnectionLost) }
        return ok(["shop":["name":"Store","billingEnabled":billing,"checkinGeo":true,"checkoutGeo":true,"autoRegister":false,"botContact":"Store Bot","identityBindingRequired":identityBindingRequired,"timeZone":"Asia/Tokyo","heroUrl":heroUrl as Any],"membership":member ? ["playerId":"p","identityBound":identityBound] : NSNull(),"entryPricing":[]])
      case "/api/v1/devices/session/page":
        precondition(request.url!.query?.hasPrefix("ticket=ticket-") == true)
        pageReads += 1
        return ok(currentPage())
      case "/api/v1/devices/session/action":
        precondition((body["ticket"] as? String)?.hasPrefix("ticket-") == true)
        precondition(UUID(uuidString: body["operationId"] as? String ?? "") != nil, "Every action carries an operation id")
        let name = body["action"] as! String, payload = body["payload"] as! [String: Any]
        actions.append(body)
        if lostReplies > 0 { lostReplies -= 1; throw URLError(.networkConnectionLost) }
        if pendingReplies > 0 {
          pendingReplies -= 1
          return ok(["ok": false, "page": currentPage(), "notices": [notice("OPERATION_PENDING", "info", "处理中")]])
        }
        var accepted = true, notices: [[String: Any]] = [], code: [String: Any]?
        switch name {
        case "entry": active = true; scene = "door"; code = PageFixtures.code
        case "coin": notices = [notice("COIN_SENT", "success", "已投币")]
        case "card.swipe":
          accepted = !swipeRefused
          notices = [swipeRefused ? notice("CARD_GONE", "error", "这张卡已停用") : notice("CARD_SENT", "success", "已发送")]
        case "table.join": scene = "tableMine"
        case "table.leave": scene = "tableEmpty"
        case "power.on": if powerComesOnAtOnce { scene = "powerOn" }
        case "climate.on": climate["mode"] = "cool"
        case "climate.off": climate["mode"] = "off"
        case "climate.set_mode": climate["mode"] = payload["mode"]
        case "climate.set_temperature": climate["temperature"] = payload["temperature"]
        case "climate.set_fan_mode": climate["fanMode"] = payload["fanMode"]
        case "booking.create": break
        default: preconditionFailure("Unexpected action: \(name)")
        }
        var answer: [String: Any] = ["ok": accepted, "page": currentPage(), "notices": notices]
        if let code { answer["code"] = code }
        return ok(answer)
      case "/api/v1/devices/session/cards/capture":
        captureStarts += 1
        return ok(["captureId": "capture-\(captureStarts)", "expiresAt": ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))])
      case _ where path.hasPrefix("/api/v1/devices/session/cards/capture/"):
        if request.httpMethod == "DELETE" { captureCancels += 1; return ok(["status": "cancelled"]) }
        captureReads += 1
        return ok(["status": captureStatus])
      case "/api/v1/devices/report": return ok([:])
      case "/api/v1/shops/store/platform-binding":
        if request.httpMethod == "GET" {
          bindingStatusReads += 1
          if shopStatus != 200 { return (shopStatus,["error":["code":"UNAVAILABLE","message":"暂不可用"]]) }
          return ok(["bindings": identityBound && member ? [["playerId":"p"]] : []])
        }
        precondition(request.httpMethod == "POST")
        bindingRequests += 1
        if bindingStatus != 200 { return (bindingStatus, ["error":["code":"BINDING_FAILED","message":"生成绑定码失败"]]) }
        return ok(["code":"ABC12345","expiresAt":bindingExpiry,"botContact":"Store Bot",
                   "lines":[["text":"Store Bot","command":false],["text":"bind ABC12345","command":true]]])
      case "/api/v1/shops/store/player/me": return ok(["wallet":[],"activeSession":active ? ["id":"entry","startedAt":"2026-09-12T00:00:00.123Z"] : NSNull()])
      case "/api/v1/shops/store/player/assets": assetReads += 1; return ok(["holdings":[]])
      case "/api/v1/shops/store/player/checkouts/history":
        historyReads += 1
        let more = request.url!.query != nil
        return ok(["records": [["id": more ? "bill:old" : "bill:new", "settledAt":"2026-09-12T01:00:00Z", "startedAt":"2026-09-12T00:00:00Z", "endedAt":"2026-09-12T01:00:00Z", "total":12, "sessionCount":2]], "nextOffset": more ? NSNull() : 30])
      case "/api/v1/shops/store/player/checkouts/bill:new", "/api/v1/shops/store/player/checkouts/bill:old":
        var receipt: [String: Any] = ["playerSettlement":["total":12,"settledAt":"2026-09-12T01:00:00Z"], "chargeItems":[], "adjustments":[]]
        if path.hasSuffix("new") { receipt["wallet"] = ["balanceAfter":88]; receipt["timeline"] = ["tracks":[],"events":[],"totals":[]] }
        return ok(["receipt":receipt])
      case "/api/v1/shops/store/devices": return ok(["devices":[]])
      // The bill is computed on the phone from these read-only inputs: an entry fee of 12.
      case "/api/v1/shops/store/player/billing-inputs":
        previewReads += 1
        if previewStatus != 200 { return (previewStatus, ["error": ["code": "PREVIEW_UNAVAILABLE", "message": "账单暂不可用"]]) }
        if failBillRead { failBillRead = false; throw URLError(.networkConnectionLost) }
        if clientBillingUnavailable { return (503, ["error": ["code": "CLIENT_BILLING_UNAVAILABLE", "message": "Client billing is unavailable for this runtime."]]) }
        return ok(["playerId": "player", "billingSnapshot": [
          "version": 1, "capturedAt": "2026-09-12T01:00:00.000Z", "assetDefinitions": [], "pricingReleases": [],
          "currentPricingConfigs": [["id": "fee", "kind": "charge.fixed", "name": "入场费", "enabled": true, "status": "active",
            "versionId": "fee-v1", "version": 1, "provider": ["id": "fee", "label": "入场费", "amount": 12],
            "createdAt": "2026-01-01T00:00:00.000Z", "updatedAt": "2026-01-01T00:00:00.000Z"]],
          "players": [["playerId": "player", "holdings": [], "pastAppliedAdjustments": [], "pricingPaidHistory": [:], "capPaidHistory": [:],
            "sessions": [["id": "entry", "playerId": "player", "startedAt": "2026-09-12T00:00:00.123Z", "status": "active",
              "pricingConfigIds": ["fee"], "pricingConfigId": "fee", "paymentStatus": "unpaid", "label": "entry"]]]],
        ]])
      case "/api/v1/shops/store/player/checkout/preview":
        serverPreviewReads += 1
        return ok(["settlementPreview":["total":12],"chargeItems":[],"adjustments":[]])
      case "/api/v1/shops/store/player/checkout/latest": return ok(["receipt": lastReceipt ?? NSNull()])
      case "/api/v1/shops/store/player/checkout/confirm":
        checkoutIds.append(body["operationId"] as! String); checkoutCalls += 1
        if checkoutCalls == 1 { return (409,["error":["code":"INSUFFICIENT_BALANCE","message":"Insufficient currency holdings for this operation."]]) }
        if checkoutCalls == 2 { throw URLError(.networkConnectionLost) }
        active = false
        // Mirrors the real confirm payload; the success screen renders from this.
        lastReceipt = [
          "timeline": ["tracks": [], "events": [], "totals": [["name": "入场费", "amount": 12]]],
          "playerSettlement":["total":12, "settledAt":"2026-09-12T01:00:00Z"],
          "chargeItems":[["id":"c1","label":"入场费","amount":12]],
          "adjustments":[],
          "settlements": [["settlement": ["sessionId": "entry", "startedAt": "2026-09-12T00:00:00.123Z", "endedAt": "2026-09-12T01:00:00Z"]]],
          "wallet":["balanceBefore":100,"balanceAfter":88],
        ]
        return ok(lastReceipt!)
      case "/api/v1/shops/store/player/page":
        let queryItems = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let view = queryItems.first(where: { $0.name == "view" })?.value ?? "shop"
        let item = queryItems.first(where: { $0.name == "item" })?.value
        let cursor = queryItems.first(where: { $0.name == "cursor" })?.value
        if view == "shop" { shopPageReads += 1 }
        if view == "history" { sheetHistoryReads += 1 }
        if htmlOutage { return (503, ["rawHTML": "<html>Service temporarily unavailable</html>"]) }
        if shopStatus != 200 { return (shopStatus, ["error": ["code": "SHOP_NOT_FOUND", "message": "没有找到店铺"]]) }
        if previewStatus != 200 && (view == "shop" || view == "bill") {
          return (previewStatus, ["error": ["code": "PREVIEW_UNAVAILABLE", "message": "账单暂不可用"]])
        }
        if view != "shop" && billing && identityBindingRequired && (!member || !identityBound) {
          return (403, ["error": [
            "code": "PLATFORM_BINDING_REQUIRED",
            "message": "请先绑定平台身份",
            "notice": ["code": "PLATFORM_BINDING_REQUIRED", "level": "info", "display": "none", "flow": "refresh", "body": "请先绑定平台身份", "actions": []],
          ]])
        }
        if failNextStatusRead && view == "shop" { failNextStatusRead = false; throw URLError(.networkConnectionLost) }
        return ok(makeShopViewPage(view: view, item: item, cursor: cursor))
      case "/api/v1/shops/store/player/action":
        precondition(UUID(uuidString: body["operationId"] as? String ?? "") != nil, "Every shop action carries an operation id")
        let view = (body["view"] as? String) ?? "shop"
        let actionName = body["action"] as! String
        shopActionCalls += 1
        shopActions.append(body)
        if lostReplies > 0 { lostReplies -= 1; throw URLError(.networkConnectionLost) }
        if pendingReplies > 0 {
          pendingReplies -= 1
          return ok(["ok": false, "page": makeShopViewPage(view: view), "notices": [notice("OPERATION_PENDING", "info", "处理中")]])
        }
        switch actionName {
        case "page.refresh":
          if view == "bindings" { bindingsRefreshReads += 1 }
          return ok(["ok": true, "page": makeShopViewPage(view: view), "notices": []])
        case "redeem.submit":
          redeemCalls += 1
          let payload = body["payload"] as? [String: Any]
          let codeValue = (payload?["code"] as? String) ?? ""
          if codeValue == "BAD" {
            return ok(["ok": false, "page": makeShopViewPage(view: view), "notices": [notice("INVALID_REDEEM_CODE", "error", "兑换码无效")]])
          }
          redeemed = true
          return ok(["ok": true, "page": makeShopViewPage(view: view), "notices": []])
        case "checkout.confirm":
          checkoutIds.append(body["operationId"] as! String); checkoutCalls += 1
          if checkoutCalls == 1 {
            return (409, ["error": ["code": "INSUFFICIENT_BALANCE", "message": "Insufficient currency holdings for this operation."]])
          }
          if checkoutCalls == 2 { throw URLError(.networkConnectionLost) }
          active = false
          lastReceipt = [
            "timeline": ["tracks": [], "events": [], "totals": [["name": "入场费", "amount": 12]]],
            "playerSettlement": ["total": 12, "settledAt": "2026-09-12T01:00:00Z"],
            "chargeItems": [["id": "c1", "label": "入场费", "amount": 12]],
            "adjustments": [],
            "settlements": [["settlement": ["sessionId": "entry", "startedAt": "2026-09-12T00:00:00.123Z", "endedAt": "2026-09-12T01:00:00Z"]]],
            "wallet": ["balanceBefore": 100, "balanceAfter": 88],
          ]
          return ok([
            "ok": true,
            "page": makeShopViewPage(view: view),
            "notices": [],
            "celebration": PageFixtures.celebration,
            "receipt": lastReceipt!,
          ])
        default:
          preconditionFailure("Unexpected shop action: \(actionName)")
        }
      // No hub channel here: pages are read when the check asks, and once a minute.
      case "/api/v1/devices/session/ws": return (404, ["error": ["code": "NOT_FOUND", "message": "Not found"]])
      default: preconditionFailure("Unexpected API path: \(path)")
      }
    }
    // Every page the platform can send decodes whole: a block these models cannot read would be skipped
    // on a real phone, silently. This is what notices the platform and the App Clip drifting apart.
    func decodePage(_ value: [String: Any]) throws -> PrismPage {
      try JSONDecoder().decode(PrismPage.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func kinds(_ blocks: [[String: Any]]) -> [String] {
      // A `status` text is its own case here: the page's one state, drawn as a whole-page message.
      blocks.flatMap { block -> [String] in
        let kind = block["kind"] as! String
        let name = kind == "text" && block["style"] as? String == "status" ? "status" : kind
        return [name] + kinds((block["blocks"] as? [[String: Any]]) ?? [])
      }
    }
    func name(of block: PrismPageBlock) -> String { String(describing: Mirror(reflecting: block).children.first?.label ?? "\(block)") }
    for fixture in PageFixtures.names {
      let raw = PageFixtures.page(fixture)
      let decoded = try decodePage(raw).allBlocks().map(name)
      let expected = kinds(raw["blocks"] as! [[String: Any]]) + kinds((raw["footer"] as? [[String: Any]]) ?? [])
      precondition(decoded == expected, "\(fixture) decodes as \(decoded)")
    }
    for fixture in PageFixtures.shopPageNames {
      let raw = PageFixtures.shopPage(fixture)
      let decoded = try decodePage(raw).allBlocks().map(name)
      let expected = kinds(raw["blocks"] as! [[String: Any]]) + kinds((raw["footer"] as? [[String: Any]]) ?? [])
      precondition(decoded == expected, "\(fixture) decodes as \(decoded)")
    }
    let decodedDoor = try decodePage(PageFixtures.page("door"))
    precondition(decodedDoor.accountMenu?.billingBadge == "计费中")
    precondition(decodedDoor.accountMenu?.tabs.map(\.id) == ["bill", "redeem", "history", "wallet", "bindings"])
    precondition(decodedDoor.accountMenu?.tabs.last?.label == "身份")
    precondition(decodedDoor.accountMenu?.logoutLabel == "退出登录")

    let decodedBinding = try decodePage(PageFixtures.page("binding"))
    precondition(decodedBinding.accountMenu?.tabs.isEmpty == true && decodedBinding.accountMenu?.billingBadge == nil)
    let decodedShopBinding = try decodePage(PageFixtures.shopPage("shopBinding"))
    precondition(decodedShopBinding.accountMenu?.tabs.isEmpty == true && decodedShopBinding.accountMenu?.billingBadge == nil)

    let decodedShopLive = try decodePage(PageFixtures.shopPage("shopLive"))
    precondition(decodedShopLive.accountMenu?.billingBadge == "计费中")
    precondition(decodedShopLive.accountMenu?.tabs.map(\.id) == ["redeem", "history", "wallet", "bindings"])
    precondition(decodedShopLive.bill()?.mode == "live" && decodedShopLive.bill()?.billingInputs?.playerId == "p1")
    precondition(decodedShopLive.bill()?.labels.estimateError == "账单预估失败，请刷新后重试")
    precondition(decodedShopLive.hasButton(id: "checkout") && decodedShopLive.buttonIds == ["checkout"])

    let decodedShopLivePreview = try decodePage(PageFixtures.shopPage("shopLivePreview"))
    precondition(decodedShopLivePreview.bill()?.billingInputs == nil && decodedShopLivePreview.bill()?.preview?.settlementPreview.total == 12)

    let decodedShopSettled = try decodePage(PageFixtures.shopPage("shopSettled"))
    precondition(decodedShopSettled.bill()?.mode == "settled" && decodedShopSettled.bill()?.balanceAfter == 76)
    precondition(decodedShopSettled.bill()?.settledAt == "2026-10-02T03:00:00.000Z")
    precondition(decodedShopSettled.bill()?.preview?.timeline?.tracks.count == 1)

    let decodedHistoryList = try decodePage(PageFixtures.shopPage("historyList"))
    let historyBlock = decodedHistoryList.list(id: "history-list")!
    precondition(historyBlock.timeZone == "Asia/Tokyo" && historyBlock.emptyIcon == "receipt")
    precondition(historyBlock.moreLabel == "加载更多" && historyBlock.moreTarget == PrismPageTarget(view: "history", cursor: "20"))
    precondition(historyBlock.items.count == 2)
    precondition(historyBlock.items[0].group == "10月2日" && historyBlock.items[0].title == "11:00 – 12:00" && historyBlock.items[0].titleMeta == "1小时")
    precondition(historyBlock.items[0].subtitle == "资产结算" && historyBlock.items[0].trailing == "24.00" && historyBlock.items[0].trailingStrikethrough == "30.00")
    precondition(historyBlock.items[0].open == PrismPageTarget(view: "history", item: "co-1"))
    precondition(historyBlock.items[1].group == "10月1日" && historyBlock.items[1].subtitle == "现场收款 · 微信 · 2 项" && historyBlock.items[1].trailingStrikethrough == nil)

    let decodedHistoryDetail = try decodePage(PageFixtures.shopPage("historyDetail"))
    precondition(decodedHistoryDetail.title == "账单详情" && decodedHistoryDetail.backLabel == nil)

    let decodedWallet = try decodePage(PageFixtures.shopPage("wallet"))
    if case .kv(let walletKv) = decodedWallet.blocks.first {
      precondition(walletKv.items.map(\.id) == ["h-paid", "h-free", "h-coupon", "h-pass", "h-ticket"])
      precondition(walletKv.items[0].icon == "wallet" && walletKv.items[0].badge == "充值余额" && walletKv.items[0].badgeTone == "success")
      precondition(walletKv.items[1].icon == "gift" && walletKv.items[1].badge == "赠送余额" && walletKv.items[1].badgeTone == "accent")
      precondition(walletKv.items[2].icon == "coupon" && walletKv.items[2].badge == "优惠券" && walletKv.items[2].badgeTone == "warning")
      precondition(walletKv.items[3].icon == "pass" && walletKv.items[3].badge == "通行证" && walletKv.items[3].badgeTone == "purple")
      precondition(walletKv.items[4].icon == "ticket" && walletKv.items[4].badge == "票券" && walletKv.items[4].badgeTone == "accent")
    } else {
      preconditionFailure("wallet fixture must decode as kv")
    }

    let decodedCelebration = try JSONDecoder().decode(PrismPageCelebration.self, from: JSONSerialization.data(withJSONObject: PageFixtures.celebration))
    precondition(decodedCelebration == PrismPageCelebration(title: "结账成功", subtitle: "计费已结束，离店前无需再做其他操作。", effect: "checkout"))

    // What only annotates a block cannot take the block with it.
    let unreadableChanges = try decodePage(PageFixtures.changing(PageFixtures.page("entryDoor"), kind: "pricing") { $0["changes"] = ["revision": 1] })
    precondition(unreadableChanges.allBlocks().contains { if case .pricing(let block) = $0 { return block.changes == nil }; return false },
                 "Pricing stays readable when what confirming changes is not")
    let unreadableState = try decodePage(PageFixtures.changing(PageFixtures.page("climate"), kind: "climate") { $0["state"] = "warm" })
    precondition(unreadableState.climate(id: "climate") != nil && unreadableState.climate(id: "climate")?.state == nil)
    let unreadableBillPreview = try decodePage(PageFixtures.changing(PageFixtures.shopPage("shopLivePreview"), kind: "bill") { $0["preview"] = ["bad": true] })
    precondition(unreadableBillPreview.bill()?.preview == nil && unreadableBillPreview.allBlocks().map(name) == ["bill", "button"])
    let unlabelledBill = try decodePage(PageFixtures.changing(PageFixtures.shopPage("shopSettled"), kind: "bill") { $0["labels"] = nil })
    precondition(unlabelledBill.bill() == nil && unlabelledBill.allBlocks().map(name) == ["unknown"])
    // A block missing what it must have is skipped whole, not drawn with words made up on the phone.
    let unlabelled = try decodePage(PageFixtures.changing(PageFixtures.page("cards"), kind: "cards") { $0["title"] = nil })
    precondition(unlabelled.cards == nil && unlabelled.allBlocks().map(name) == ["unknown"])

    // Forms walk both body blocks and sticky footer blocks together.
    let footerFormRaw: [String: Any] = [
      "shop": "Store", "shopCode": "store", "heroUrl": NSNull(), "resource": "", "publicId": "", "billingActive": true,
      "blocks": [
        ["kind": "input", "id": "note", "name": "note", "required": true],
        ["kind": "consent", "id": "agree-body", "text": "同意"],
      ],
      "footer": [
        ["kind": "toggle", "id": "opt", "label": "提醒", "defaultValue": true],
        ["kind": "button", "id": "footer-submit", "label": "提交", "action": "footer.submit", "enabled": true, "needsLocation": false, "requires": "agree-body", "collect": ["note", "opt"]],
      ],
    ]
    let footerFormPage = try decodePage(footerFormRaw)
    precondition(footerFormPage.fieldIds == Set(["note", "agree-body", "opt"]))
    precondition(footerFormPage.buttonIds == ["footer-submit"] && footerFormPage.hasButton(id: "footer-submit"))
    let footerSubmit = footerFormPage.allBlocks().compactMap { if case .button(let b) = $0 { return b }; return nil }.first!
    var footerValues = footerFormPage.reconciledValues(from: [:])
    precondition(!footerFormPage.canSubmit(footerSubmit, values: footerValues))
    footerValues["agree-body"] = .bool(true); footerValues["note"] = .string("ok")
    precondition(footerFormPage.canSubmit(footerSubmit, values: footerValues))
    let footerCollected = footerFormPage.collectedPayload(for: footerSubmit, values: footerValues)
    precondition(footerCollected["note"] as? String == "ok" && footerCollected["opt"] as? Bool == true)

    let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
    let model = MachineLoginViewModel(api: PrismAPI(configuration: config))
    func button(_ id: String) -> PrismPageButton {
      for block in model.page?.allBlocks() ?? [] { if case .button(let found) = block, found.id == id { return found } }
      preconditionFailure("No button \(id) among \(model.page?.buttonIds ?? [])")
    }
    func text(_ id: String) -> String? {
      for block in model.page?.allBlocks() ?? [] {
        if case .text(let found, let value, _, _) = block, found == id { return value }
        if case .status(let status) = block, status.id == id { return status.text }
      }
      return nil
    }
    func table() -> PrismPageTable? {
      for block in model.page?.allBlocks() ?? [] { if case .table(let found) = block { return found } }
      return nil
    }
    func sent(_ name: String) -> [[String: Any]] { actions.filter { $0["action"] as? String == name } }
    func operationIds(_ name: String) -> [String] { sent(name).map { $0["operationId"] as! String } }
    /// Shows another page the way the app would: the link again, from the start.
    func scan(_ next: String) async {
      scene = next
      await model.start(shopCode: "store", publicId: "device")
    }

    await model.handleResolvedInvocation(origin.appendingPathComponent("t/store/device"))
    precondition(model.state == .ready && model.needsPlatformBinding && model.page?.cards == nil)
    precondition(model.binding?.code == "ABC12345" && model.binding?.lines.last == PrismBindingPromptLine(text: "bind ABC12345", command: true))
    let initialBindingRequests = bindingRequests, readsAfterOpening = pageReads
    try await Task.sleep(nanoseconds: 3_300_000_000)
    precondition(pageReads == readsAfterOpening && model.errorMessage == nil, "A scanned page is told when to read; it does not poll")
    precondition(bindingRequests == initialBindingRequests, "A valid binding code is kept")
    await model.setSceneActive(false)
    await model.refreshVisit()
    precondition(pageReads == readsAfterOpening, "Nothing is read in the background")
    failNextStatusRead = true
    await model.setSceneActive(true)
    precondition(model.errorMessage == nil && model.ticket != nil, "Resume network errors must not show an alert")
    precondition(pageReads == readsAfterOpening + 1 && sessionStarts == 1 && model.binding?.code == "ABC12345")
    htmlOutage = true
    await model.refreshVisit(silent: true)
    precondition(model.errorMessage == nil, "HTML 503 responses must remain retryable without alerts")
    htmlOutage = false

    // Bound: the page now asks to confirm billing. One button enters and gets the door code.
    member = true; scene = "entryDoor"; await model.refreshVisit()
    precondition(model.page?.asksConsent == true && !model.needsPlatformBinding && model.binding == nil)
    let entry = button("door")
    var values = model.page!.reconciledValues(from: [:])
    precondition(!model.page!.canSubmit(entry, values: values), "Confirming needs the consent ticked")
    values["consent"] = .bool(true)
    precondition(model.page!.canSubmit(entry, values: values))
    precondition(StoreVisitLiveActivityManager.shared.synced.isEmpty && LocationService.calls == 0)
    await model.press(entry, collected: model.page!.collectedPayload(for: entry, values: values))
    let confirmed = sent("entry")[0]["payload"] as! [String: Any]
    precondition(confirmed["consent"] as? Bool == true && confirmed["openDoor"] as? Bool == true)
    precondition(confirmed["expectedRevision"] as? String == "rev-1", "Confirming sends back the revision the page showed")
    precondition(sent("entry")[0]["location"] != nil && LocationService.calls == 1, "Entry checks that the player is there")
    precondition(model.pageCode?.value == "12345678" && model.page?.asksConsent == false)
    // The visit changed here, so the Live Activity follows at once, before the page's own refresh.
    await waitUntil { StoreVisitLiveActivityManager.shared.synced.contains("store") }
    precondition(StoreVisitLiveActivityManager.shared.synced.contains("store"))
    // The page is read again in the background after an action; nothing waits on it.
    await waitUntil { model.summary?.activeSession != nil && StoreVisitLiveActivityManager.shared.session != nil }
    precondition(model.summary?.activeSession != nil)
    precondition(StoreVisitLiveActivityManager.shared.session?.id == "entry")
    precondition(prismParsedDate(StoreVisitLiveActivityManager.shared.session!.startedAt) == milliseconds)

    // An action whose replies are lost is tried again under the same id, so it happens once. When every
    // try is lost the player is told beside the button, and pressing again still sends that id.
    scene = "doorCardsCoin"; await model.refreshVisit()
    precondition(model.page?.cards != nil && model.cards.count == 1)
    lostReplies = 5
    await model.press(button("coin"))
    precondition(sent("coin").count == 5 && Set(operationIds("coin")).count == 1)
    precondition(model.state == .ready && model.ticket != nil && model.errorMessage == nil && !model.slowNetwork)
    precondition(model.dialogNotice?.code == "DEVICE_RESULT_UNKNOWN")
    await model.press(button("coin"))
    precondition(sent("coin").count == 6 && Set(operationIds("coin")).count == 1, "A press with no answer is sent again as itself")
    precondition(model.inlineNotice?.code == "COIN_SENT" && model.inlineNoticeAnchor == "coin")
    // Once answered, the next press is a new one; "still running" is not an answer.
    pendingReplies = 1
    await model.press(button("coin"))
    precondition(sent("coin").count == 8 && operationIds("coin")[6] == operationIds("coin")[7] && operationIds("coin")[6] != operationIds("coin")[0])
    precondition(model.inlineNotice?.code == "COIN_SENT" && sent("coin").allSatisfy { $0["location"] == nil })
    await model.refreshVisit(); precondition(sessionStarts == 1)

    model.dismissNotice(retrying: false)
    pendingReplies = 5
    let beforePending = operationIds("coin").count
    await model.press(button("coin"))
    precondition(model.inlineNotice?.code == "OPERATION_PENDING" && model.dialogNotice == nil)
    precondition(Set(operationIds("coin").dropFirst(beforePending)).count == 1)
    await model.press(button("coin"))
    precondition(model.inlineNotice?.code == "COIN_SENT")
    precondition(Set(operationIds("coin").dropFirst(beforePending)).count == 1)
    let offline = model.present(URLError(.notConnectedToInternet))
    precondition(offline == model.page?.clientNotices?["CLIENT_NETWORK_ERROR"])
    // A card swipe is the page's own action, and its outcome goes on the card's row.
    await model.start(shopCode: "store", publicId: "device")
    await model.login(card: model.cards[0])
    precondition(model.state == .ready && model.ticket != nil)
    precondition((sent("card.swipe")[0]["payload"] as! [String: Any])["cardId"] as? String == "card")
    precondition(model.cardFeedback?.cardId == "card" && model.cardFeedback?.parts.first?.text == "已发送")
    // A refused swipe may mean the card is gone, so the cards are read again.
    swipeRefused = true
    let readsBeforeRefusal = cardReads
    await model.login(card: model.cards[0])
    precondition(cardReads == readsBeforeRefusal + 1 && model.cardFeedback?.parts.first?.level == "error" && model.state == .ready)
    swipeRefused = false
    precondition(historyReads == 0 && assetReads == 0 && sheetHistoryReads == 0, "Status, admission and device operations must not fetch wallet/history")
    // Account sheets are server-driven through `/player/page` and `/player/action`.
    await model.openAccountSheet(view: "bill")
    precondition(historyReads == 0 && assetReads == 0 && sheetHistoryReads == 0, "Bill sheet must not fetch unrelated account data")
    let liveBillBlock = model.sheetPage?.bill()
    precondition(liveBillBlock?.mode == "live" && liveBillBlock?.billingInputs?.billingSnapshot != nil)
    let localBillPreview = try PrismCheckoutEngine.preview(
      snapshot: liveBillBlock!.billingInputs!.billingSnapshot!,
      playerId: liveBillBlock!.billingInputs!.playerId
    ).view()
    precondition(localBillPreview.settlementPreview.total == 12 && localBillPreview.timeline.totals.first?.name == "入场计费",
                 "The phone computes the live bill block from billingInputs")
    clientBillingUnavailable = true
    await model.openAccountSheet(view: "bill")
    precondition(model.sheetPage?.bill()?.billingInputs == nil && model.sheetPage?.bill()?.preview?.settlementPreview.total == 12,
                 "A shop the phone cannot bill falls back to the server preview")
    clientBillingUnavailable = false
    await model.openAccountSheet(view: "history")
    precondition(sheetHistoryReads == 1 && assetReads == 0)
    let initialHistoryList = model.sheetPage?.list(id: "history-list")
    precondition(initialHistoryList?.items.count == 1 && initialHistoryList?.moreTarget == PrismPageTarget(view: "history", cursor: "30"))
    await model.loadMoreSheetList(blockId: "history-list", target: initialHistoryList!.moreTarget!)
    precondition(model.sheetPage?.list(id: "history-list")?.items.map(\.id) == ["bill:new", "bill:old"])
    precondition(model.sheetPage?.list(id: "history-list")?.moreTarget == nil)
    await model.openSheetTarget(PrismPageTarget(view: "history", item: "bill:new"))
    precondition(model.sheetStack.count == 2 && model.sheetPage?.title == "账单详情" && model.sheetPage?.backLabel == nil)
    precondition(model.sheetPage?.bill()?.balanceAfter == 88 && model.sheetPage?.bill()?.preview?.timeline != nil)
    await model.popSheetTarget()
    precondition(model.sheetStack.count == 1 && model.sheetPage?.title == "记录")
    await model.openSheetTarget(PrismPageTarget(view: "history", item: "bill:old"))
    precondition(model.sheetPage?.bill()?.balanceAfter == nil && model.sheetPage?.bill()?.preview?.timeline == nil && model.sheetPage?.bill()?.preview?.settlementPreview.total == 12)
    await model.openAccountSheet(view: "wallet")
    precondition(model.sheetPage?.title == "钱包")
    await model.openAccountSheet(view: "bindings")
    precondition(model.sheetPage?.title == "身份")
    precondition(model.sheetPage!.allBlocks().contains { if case .button = $0 { return true }; return false } == false)
    let pageRefreshBtn = PrismPageButton(id: "bindings-refresh", label: "刷新", againLabel: nil, icon: nil, style: nil, enabled: true, action: "page.refresh", answerOnButton: nil, payload: nil, requires: nil, needsLocation: false)
    let refreshBefore = bindingsRefreshReads
    await model.pressSheet(pageRefreshBtn)
    precondition(bindingsRefreshReads == refreshBefore + 1 && model.sheetPage?.title == "身份")
    await model.openAccountSheet(view: "redeem")
    let redeemBtn = model.sheetPage!.allBlocks().compactMap { if case .button(let b) = $0 { return b }; return nil }.first!
    await model.pressSheet(redeemBtn, collected: ["code": "BAD"])
    precondition(model.sheetInlineNotice?.body == "兑换码无效" && model.sheetInlineNoticeAnchor == "redeem-submit")
    await model.pressSheet(redeemBtn, collected: ["code": "GOOD"])
    precondition(redeemCalls == 2 && model.sheetPage?.allBlocks().contains { if case .banner(let b) = $0 { return b.id == "redeem-done" }; return false } == true)
    redeemed = false
    await model.openAccountSheet(view: "bill")
    let sheetCheckout = model.sheetPage!.allBlocks().compactMap { if case .button(let b) = $0, b.id == "checkout" { return b }; return nil }.first!
    await model.pressSheet(sheetCheckout)
    precondition(model.dialogNotice?.body == "余额不足，请充值后再结账，计费会继续")
    precondition(model.sheetPage?.billingActive == true && checkoutCalls == 1, "Balance rejection must retain the bill without retrying checkout")
    lostReplies = 5
    await model.pressSheet(sheetCheckout)
    precondition(model.dialogNotice?.code == "DEVICE_RESULT_UNKNOWN")
    await model.pressSheet(sheetCheckout)
    let sheetCheckoutIds = shopActions.filter { $0["action"] as? String == "checkout.confirm" }.map { $0["operationId"] as! String }
    precondition(sheetCheckoutIds.count == 8 && sheetCheckoutIds[0] != sheetCheckoutIds[1] && Set(sheetCheckoutIds.dropFirst()).count == 1)
    precondition(model.checkoutCelebrating && model.celebration?.title == "结账成功")
    precondition(model.sheetPage?.bill()?.mode == "live", "Checkout celebration must not flash the settled bill inside the sheet")
    precondition(StoreVisitLiveActivityManager.shared.finishedReceipt?.playerSettlement.total == 12)
    var postCheckoutRefresh: Task<Void, Never>?
    let celebrationCaller = Task { @MainActor in
      postCheckoutRefresh = model.finishCheckoutInBackground()
      try? await Task.sleep(nanoseconds: 5_000_000_000)
    }
    while postCheckoutRefresh == nil { await Task.yield() }
    celebrationCaller.cancel()
    await celebrationCaller.value
    await postCheckoutRefresh?.value
    precondition(model.isShopOnly && model.machine == nil && model.ticket == nil && !model.checkoutCelebrating && model.celebration == nil)
    precondition(model.playerStateLoaded && model.page?.bill()?.mode == "settled",
                 "Post-checkout shop refresh must survive celebration task cancellation and render the settled receipt")
    precondition(model.lastShopHero?.name == "Store", "Post-checkout transition must retain shop hero metadata")
    precondition(StoreVisitLiveActivityManager.shared.session == nil)
    // Confirming a checkout checks that the player is there, once per try, and so did entering.
    precondition(LocationService.calls == 4, "location calls: \(LocationService.calls)")

    // Unbound accounts cannot use shop sheets; hitting a sheet route closes it and refreshes to host binding.
    do {
      identityBindingRequired = true; identityBound = false
      await model.openAccountSheet(view: "wallet")
      await waitUntil {
        model.sheetStack.isEmpty
          && model.needsPlatformBinding
          && model.binding != nil
          && model.page?.accountMenu?.tabs.isEmpty == true
      }
      precondition(model.sheetError == nil && model.sheetPage == nil && model.binding?.code == "ABC12345",
                   "PLATFORM_BINDING_REQUIRED in a sheet must close the sheet and refresh the host binding block")
      identityBound = true
    }

    // Opening the bill sheet on a scanned machine page syncs billingActive back to the main page and Live Activity.
    do {
      identityBindingRequired = false; active = true
      await scan("doorCardsCoin")
      await waitUntil { model.summary?.activeSession != nil }
      active = false
      let syncedBeforeSheet = StoreVisitLiveActivityManager.shared.synced.count
      let readsBeforeSheet = statusReads
      await model.openAccountSheet(view: "bill")
      await waitUntil {
        model.summary?.activeSession == nil
          && StoreVisitLiveActivityManager.shared.synced.dropFirst(syncedBeforeSheet).contains("store")
          && statusReads > readsBeforeSheet
      }
      precondition(model.summary?.activeSession == nil && StoreVisitLiveActivityManager.shared.synced.dropFirst(syncedBeforeSheet).contains("store"),
                   "Opening bill sheet after an external checkout must sync main summary and Live Activity")
      model.closeAccountSheet()
      identityBindingRequired = true
    }
    // A page with only cards, and a shop that bills nothing: no visit card, no other controls.
    billing = false; member = false
    await scan("cards")
    precondition(model.page?.cards != nil && model.page?.buttonIds == [] && !model.showVisit)

    // Without the cards the page offers nothing but reading them again.
    cardsFail = true
    await scan("doorCardsCoin")
    precondition(model.state == .ready && model.cardsLoadFailed && model.cardsError == "服务暂时不可用")
    let failure = model.page!.cards!.loadError
    precondition(failure.title == "无法加载卡片" && failure.actions.map(\.action) == ["cards.reload"] && failure.actions[0].style == "primary")
    await model.refreshCards()
    precondition(model.cardsLoadFailed, "A retry that fails stays on the failure")
    cardsFail = false
    await model.refreshCards()
    precondition(!model.cardsLoadFailed && model.cardsError == nil && model.cards.count == 1)

    // Adding a card at the reader: a window opens, and what became of the card is worded by the page.
    await scan("cardsCapture")
    precondition(model.page?.cards?.captureUi?.waitingText == "请把卡片放在「Device」的读卡器上" && button("coin").hideDuringCapture == true)
    var adding = Task { await model.startCardCapture() }
    await waitUntil { model.cardCapture == .waiting && captureReads > 0 }
    precondition(model.cardCapture == .waiting && model.capturing)
    // Cancelling closes the window on the platform: left open, it would add the next card to this player.
    model.dismissCardCapture()
    await adding.value
    await waitUntil { captureCancels == 1 }
    precondition(model.cardCapture == nil && captureCancels == 1)
    // Once the app is in the background a card put down could be anyone's.
    adding = Task { await model.startCardCapture() }
    await waitUntil { model.cardCapture == .waiting }
    await model.setSceneActive(false)
    precondition(model.cardCapture == .done(level: "info", message: "离开页面后已取消添加，请重新添加"))
    await adding.value
    await waitUntil { captureCancels == 2 }
    precondition(captureCancels == 2)
    await model.setSceneActive(true)
    model.dismissCardCapture()
    captureStatus = "taken"
    await model.startCardCapture()
    precondition(model.cardCapture == .done(level: "error", message: "这张卡已绑定到本店的其他玩家"))
    model.dismissCardCapture()
    captureStatus = "added"
    let readsBeforeAdding = cardReads
    await model.startCardCapture()
    precondition(model.cardCapture == .done(level: "success", message: "已添加卡片") && cardReads == readsBeforeAdding + 1)
    precondition(captureCancels == 2, "A finished window has nothing left to close")
    model.dismissCardCapture()

    // A table is joined and left with the buttons the page offers.
    identityBindingRequired = false
    await scan("tableEmpty")
    precondition(table()?.seats.isEmpty == true && button("seat").action == "table.join")
    await model.press(button("seat"))
    precondition(table()?.seats.first?.mine == true && button("seat").action == "table.leave" && model.waitingButtonId == nil)
    await model.press(button("seat"))
    precondition(table()?.seats.isEmpty == true)

    // An air conditioner: each choice is an action, and the page's answer carries the state.
    await scan("climate")
    func air() -> PrismClimate? { model.page?.climate(id: "climate")?.state }
    precondition(air()?.isOn == false && air()?.choosableModes.first == "cool", "climate \(String(describing: air()))")
    precondition(model.page?.climate(id: "climate")?.roomText == "室温 28.5°" && model.page?.climate(id: "climate")?.label(forMode: "heat") == "制热")
    actions = []
    let locationsBeforeClimate = LocationService.calls
    await model.climate("climate.on")
    precondition(air()?.mode == "cool")
    await model.climate("climate.set_mode", ["mode":"heat"])
    await model.climate("climate.set_temperature", ["temperature":23.0])
    await model.climate("climate.set_fan_mode", ["fanMode":"high"])
    precondition(air() == PrismClimate(mode:"heat",modes:["off","cool","heat","dry","fan_only","auto"],temperature:23,
      currentTemperature:28.5,minTemperature:16,maxTemperature:30,temperatureStep:1,fanMode:"high",fanModes:["auto","low","high"]))
    precondition(actions.map { $0["action"] as! String } == ["climate.on","climate.set_mode","climate.set_temperature","climate.set_fan_mode"])
    let payloads = actions.map { $0["payload"] as! [String: Any] }
    precondition(payloads[2]["temperature"] as? Double == 23 && payloads[3]["fanMode"] as? String == "high")
    precondition(payloads.allSatisfy { $0["consent"] == nil } && LocationService.calls == locationsBeforeClimate)
    // Where the shop checks location, the climate block says so and the action carries it.
    await scan("climateOnSite")
    await model.climate("climate.off")
    precondition(LocationService.calls == locationsBeforeClimate + 1 && actions.last?["location"] != nil && air()?.mode == "off")
    await scan("climateUnknown")
    precondition(model.page?.climate(id: "climate") != nil && air() == nil)
    let ac = PrismClimate(mode:"cool",minTemperature:16,maxTemperature:30,temperatureStep:1)
    precondition(ac.nudged(23, by: 1) == 24 && ac.nudged(30, by: 1) == 30 && ac.nudged(16, by: -3) == 16)
    precondition(PrismClimate(mode:"cool",temperatureStep:0.5).nudged(25, by: -1) == 24.5)

    // Powering on: the button waits until the page moves off it.
    await scan("powerOff")
    precondition(model.page?.buttonIds == ["power"] && text("power-off") == "设备尚未开机")
    await model.press(button("power"))
    precondition(model.waitingButtonId == "power", "The machine has not said it is on yet")
    scene = "powerOn"
    await model.refreshVisit(silent: true, dynamicOnly: true)
    precondition(model.waitingButtonId == nil && model.page?.buttonIds == [])
    // If the machine never reports on, the button comes back with the page's own words.
    powerWaitMs = 300
    await scan("powerOff")
    await model.press(button("power"))
    precondition(model.waitingButtonId == "power")
    await waitUntil { model.waitingButtonId == nil }
    precondition(model.waitingButtonId == nil && model.inlineNotice?.body == "未检测到开机，请重试" && model.inlineNoticeAnchor == "power")
    // An answer already past the button waits for nothing.
    powerWaitMs = nil; powerComesOnAtOnce = true
    await scan("powerOff")
    await model.press(button("power"))
    precondition(model.waitingButtonId == nil && model.page?.buttonIds == [])
    powerComesOnAtOnce = false

    // A form: the same rules as the web's, and what is sent is the collected fields, then the button's
    // own payload over them, then the consent it required.
    await scan("components")
    let submit = button("submit")
    var form = model.page!.reconciledValues(from: ["gone": .string("x"), "pin": .bool(true)])
    precondition(form["gone"] == nil && form["pin"] == .string("") && form["remind"] == .bool(true) && form["agree"] == .bool(false))
    precondition(!model.page!.canSubmit(submit, values: form))
    form["agree"] = .bool(true); form["slot"] = .string("a")
    precondition(!model.page!.canSubmit(submit, values: form), "A required input is still empty")
    form["pin"] = .string("  ")
    precondition(!model.page!.canSubmit(submit, values: form))
    form["pin"] = .string("0520"); form["slot"] = .string("full")
    precondition(!model.page!.canSubmit(submit, values: form), "A disabled option does not satisfy a required choice")
    form["slot"] = .string("a")
    precondition(model.page!.canSubmit(submit, values: form))
    await model.press(submit, collected: model.page!.collectedPayload(for: submit, values: form))
    let booking = sent("booking.create")[0]["payload"] as! [String: Any]
    precondition(booking.keys.sorted() == ["code", "consent", "plan", "remind", "slot"], "\(booking)")
    precondition(booking["code"] as? String == "0520" && booking["slot"] as? String == "a" && booking["plan"] as? String == "vip")
    precondition(booking["remind"] as? Bool == false && booking["consent"] as? Bool == true, "The button's payload wins over what was typed")
    precondition(PrismPage.resolveImageURL("/assets/event.png", origin: origin)?.absoluteString == "https://link-beta.neri.moe/assets/event.png")
    for unsafe in ["//other.example/a.png", "http://other.example/a.png", "javascript:alert(1)", "data:image/png;base64,AA", "file:///etc/passwd"] {
      precondition(PrismPage.resolveImageURL(unsafe, origin: origin) == nil, unsafe)
    }

    // Nothing to operate is the page's to say.
    await scan("empty")
    precondition(model.state == .ready && model.page?.cards == nil && text("empty") == "这里没有可操作的设备")
    scene = "doorCardsCoin"
    await model.setSceneActive(false)
    // A bare shop link opens the server-driven shop surface: no machine, no ticket, no admission.
    billing = true; member = true; active = false; identityBindingRequired = true
    let shopOnly = MachineLoginViewModel(api: PrismAPI(configuration: config))
    let machineCardReads = cardReads
    let initialShopPageReads = shopPageReads
    // Before any data is in hand the shop link must sit on its loading state, not render the
    // session page without a card: that is what made the cover appear small and then grow.
    let pendingShop = Task { await shopOnly.handleResolvedInvocation(origin.appendingPathComponent("t/store")) }
    for _ in 0..<200 where shopOnly.state == .idle { await Task.yield() }
    precondition(shopOnly.state == .loadingShop, "The shop page must wait for its data")
    precondition(shopOnly.page == nil && shopOnly.lastShopHero == nil, "No card is rendered before the shop page is loaded")
    await pendingShop.value
    precondition(shopOnly.isShopOnly && shopOnly.ticket == nil && shopOnly.machine == nil)
    precondition(shopOnly.state == .ready && !shopOnly.shopHasActiveSession)
    precondition(shopPageReads == initialShopPageReads + 1, "Opening a shop reads /player/page once")
    precondition(cardReads == machineCardReads, "A shop must never depend on the machine card endpoint")
    precondition(shopOnly.page != nil && shopOnly.lastShopHero?.name == "Store", "The card data is present before the page is shown")
    precondition(shopOnly.page?.accountMenu?.tabs.map(\.id) == ["redeem", "history", "wallet", "bindings"])
    // The card's subtitle carries the billing state from page.resource.
    precondition(shopOnly.shopBillingState == "结账成功")
    precondition(shopOnly.canUseShopSurface && !shopOnly.shopHasActiveSession)
    precondition(shopOnly.page?.heroUrl == "/api/v1/shops/store/hero?v=abc123")

    // A player who has not verified with the Bot gets the server binding block.
    member = false
    await shopOnly.refreshVisit()
    precondition(shopOnly.needsPlatformBinding && !shopOnly.canUseShopSurface)
    precondition(shopOnly.page?.accountMenu?.tabs.isEmpty == true && shopOnly.page?.accountMenu?.billingBadge == nil)
    precondition(shopOnly.playerStateLoaded, "Binding page is a completed read, not a spinner")
    precondition(shopOnly.binding?.code == "ABC12345", "Shop platform binding must reuse the machine flow")
    // A registered player may still be unbound after optional admission.
    member = true; identityBound = false
    let requestsBeforeMembership = bindingRequests
    await shopOnly.refreshVisit()
    precondition(shopOnly.needsPlatformBinding)
    precondition(shopOnly.binding?.code == "ABC12345" && bindingRequests == requestsBeforeMembership,
                 "Existing unbound membership must retain the valid code")
    identityBindingRequired = false
    await shopOnly.refreshVisit()
    precondition(!shopOnly.needsPlatformBinding && shopOnly.binding == nil)
    precondition(bindingRequests == requestsBeforeMembership, "Optional identity binding must not request a code")
    identityBindingRequired = true
    await shopOnly.refreshVisit()
    precondition(shopOnly.needsPlatformBinding && bindingRequests == requestsBeforeMembership + 1)
    // Foreground/manual events must queue one follow-up behind an outstanding read.
    await shopOnly.api.invalidateReads()
    FixtureProtocol.holdNextShopPageResponse = true
    let outstandingRead = Task { await shopOnly.refreshVisit(silent: true) }
    await waitUntil { FixtureProtocol.heldShopPageReply != nil }
    precondition(FixtureProtocol.heldShopPageReply != nil)
    let beforeConcurrentEvents = shopPageReads
    await shopOnly.refreshVisit(silent: true)
    await shopOnly.refreshVisit(silent: true)
    precondition(shopPageReads == beforeConcurrentEvents, "An outstanding read must not overlap foreground reads")
    let reply = FixtureProtocol.heldShopPageReply!; FixtureProtocol.heldShopPageReply = nil; reply()
    await outstandingRead.value
    try await Task.sleep(nanoseconds: 100_000_000)
    precondition(shopPageReads > beforeConcurrentEvents, "Coalesced follow-up runs after the held read completes")
    // Manual foreground refresh must also retain the valid command.
    let requestsBeforeManualRefresh = bindingRequests
    await shopOnly.bindPlatformIdentity()
    precondition(bindingRequests == requestsBeforeManualRefresh)
    // Exercise actual expiration instead of replacing a still-valid command manually.
    identityBindingRequired = false; await shopOnly.refreshVisit()
    bindingExpiry = ISO8601DateFormatter().string(from: Date().addingTimeInterval(2))
    identityBindingRequired = true; await shopOnly.refreshVisit()
    bindingExpiry = "2999-01-01T00:00:00Z"
    try await Task.sleep(nanoseconds: 2_100_000_000)
    let requestsBeforeRenewal = bindingRequests
    await shopOnly.refreshVisit()
    precondition(bindingRequests == requestsBeforeRenewal + 1 && shopOnly.binding?.expiresAt == bindingExpiry)
    await shopOnly.refreshVisit()
    precondition(bindingRequests == requestsBeforeRenewal + 1)
    // Existing unbound members are polled, and an HTTP outage cannot break the loop.
    let beforeOutage = shopPageReads
    await shopOnly.api.invalidateReads()
    shopStatus = 503
    await shopOnly.refreshVisit(silent: true)
    precondition(shopOnly.errorMessage == nil && shopOnly.binding != nil)
    shopStatus = 200; identityBound = true
    await waitUntil({ shopPageReads > beforeOutage && !shopOnly.needsPlatformBinding && shopOnly.binding == nil }, seconds: 20)
    precondition(shopPageReads > beforeOutage, "Polling resumes after an outage")
    precondition(!shopOnly.needsPlatformBinding && shopOnly.binding == nil,
                 "A verified identity on any platform completes binding")
    let afterBinding = shopPageReads
    try await Task.sleep(nanoseconds: 3_300_000_000)
    precondition(shopPageReads == afterBinding, "Binding completion must stop binding polling")
    await shopOnly.setSceneActive(false)
    let beforeShopBackground = identityReads
    try await Task.sleep(nanoseconds: 3_300_000_000)
    precondition(identityReads == beforeShopBackground)
    await shopOnly.setSceneActive(true)
    precondition(identityReads > beforeShopBackground, "Foreground must refresh identity alongside the shop page")
    identityBound = false; bindingStatus = 500
    await shopOnly.refreshVisit()
    precondition(shopOnly.needsPlatformBinding && shopOnly.binding == nil && shopOnly.errorMessage != nil)
    bindingStatus = 200
    await shopOnly.bindPlatformIdentity()
    precondition(shopOnly.binding?.code == "ABC12345" && shopOnly.errorMessage == nil, "Failed generation must be retryable")
    // Admission comes from the machine flow, so the shop link reads the live bill page.
    active = true
    await shopOnly.refreshVisit()
    precondition(shopOnly.shopHasActiveSession && shopOnly.shopBillingState == "计费中")
    precondition(!shopOnly.needsPlatformBinding && shopOnly.binding == nil,
                 "An existing bill stays accessible when identity binding becomes required")
    identityBound = true
    precondition(StoreVisitLiveActivityManager.shared.session?.id == "entry")
    precondition(StoreVisitLiveActivityManager.shared.origin?.absoluteString == "https://link-beta.neri.moe")
    precondition(StoreVisitLiveActivityManager.shared.lastApi?.baseURL == origin, "Manager must receive origin-scoped API instance")
    precondition(StoreVisitLiveActivityManager.shared.trackingPushToStart, "Push-to-start tracking must be active for logged-in user")
    precondition(shopOnly.page?.bill()?.mode == "live" && shopOnly.page?.hasButton(id: "checkout") == true,
                 "A live shop page delivers its bill block and sticky footer checkout button")
    let liveBill = shopOnly.page!.bill()!
    let liveTotal = try PrismCheckoutEngine.preview(
      snapshot: liveBill.billingInputs!.billingSnapshot!,
      playerId: liveBill.billingInputs!.playerId
    ).view().settlementPreview.total
    precondition(liveTotal == 12)
    // Settling via the footer checkout button shows celebration, updates Live Activity, and retains the settled receipt page.
    checkoutCalls = 2
    let shopCheckoutButton = shopOnly.page!.allBlocks().compactMap { if case .button(let b) = $0, b.id == "checkout" { return b }; return nil }.first!
    await shopOnly.press(shopCheckoutButton)
    precondition(shopOnly.checkoutCelebrating && shopOnly.celebration?.title == "结账成功")
    precondition(shopOnly.page?.bill()?.mode == "live", "Checkout celebration must not flash the settled bill before the overlay hides")
    precondition(shopOnly.settlement?.playerSettlement.total == 12 && shopOnly.settlement?.wallet?.balanceAfter == 88)
    await shopOnly.finishCheckout()
    precondition(!shopOnly.checkoutCelebrating && shopOnly.shopBillingState == "结账成功")
    precondition(shopOnly.page?.bill()?.mode == "settled" && shopOnly.page?.bill()?.balanceAfter == 88)
    let reopenedShop = MachineLoginViewModel(api: PrismAPI(configuration: config, origin: origin))
    await reopenedShop.startShop(shopCode: "store")
    precondition(reopenedShop.page?.bill()?.mode == "settled" && reopenedShop.page?.bill()?.preview?.settlementPreview.total == 12,
                 "A fresh page must restore the server settled bill")
    active = true
    await reopenedShop.refreshVisit()
    precondition(reopenedShop.settlement == nil && reopenedShop.page?.bill()?.mode == "live",
                 "Admission supersedes the previous receipt")

    // A machine link afterwards must leave shop-only mode behind.
    await shopOnly.handleResolvedInvocation(origin.appendingPathComponent("t/store/device"))
    precondition(!shopOnly.isShopOnly && shopOnly.machine != nil && shopOnly.ticket != nil)
    precondition(shopOnly.shopBillingState == "", "A device link keeps the machine name, not the billing state")

    // Routing keeps where each delivery came from. A replayed App Clip invocation must not
    // displace a Live Activity tap in the same activation, whichever order they arrive in.
    let machineA = origin.appendingPathComponent("t/store/device")
    let shopB = URL(string: "https://link-beta.neri.moe/t/store")!

    // 1. appClipInvocation(machine A) then explicitOpenURL(shop B): B wins.
    do {
      let router = InvocationRouter()
      let target = MachineLoginViewModel(api: PrismAPI(configuration: config))
      await router.handle(machineA, source: .appClipInvocation, model: target)
      precondition(!target.isShopOnly)
      await router.handle(shopB, source: .explicitOpenURL, model: target)
      precondition(target.isShopOnly && target.shopCode == "store", "An explicit open must take over")
    }

    // 2. explicitOpenURL(shop B) then appClipInvocation(machine A): B still wins.
    do {
      let router = InvocationRouter()
      let target = MachineLoginViewModel(api: PrismAPI(configuration: config))
      await router.handle(shopB, source: .explicitOpenURL, model: target)
      await router.handle(machineA, source: .appClipInvocation, model: target)
      precondition(target.isShopOnly && target.shopCode == "store", "A replayed invocation must not take over")
    }

    // 3. A new activation accepts an App Clip invocation again.
    do {
      let router = InvocationRouter()
      let target = MachineLoginViewModel(api: PrismAPI(configuration: config))
      await router.handle(shopB, source: .explicitOpenURL, model: target)
      await router.handle(machineA, source: .appClipInvocation, model: target)
      precondition(target.isShopOnly)
      router.resetForNextActivation()
      await router.handle(machineA, source: .appClipInvocation, model: target)
      precondition(!target.isShopOnly && target.machine != nil, "A new activation must accept the invocation")
    }

    // 4. machine A, background, then machine C: C takes effect.
    do {
      let router = InvocationRouter()
      let target = MachineLoginViewModel(api: PrismAPI(configuration: config))
      await router.handle(machineA, source: .appClipInvocation, model: target)
      precondition(target.publicId == "device")
      router.resetForNextActivation()
      await router.handle(origin.appendingPathComponent("t/store/other"), source: .appClipInvocation, model: target)
      precondition(target.publicId == "other", "A later machine link must take effect in a new activation")
    }

    // 5. A bare shop link delivered as an App Clip invocation is a normal invocation, not a
    //    Live Activity, and must be routed on its own merits.
    do {
      let router = InvocationRouter()
      let target = MachineLoginViewModel(api: PrismAPI(configuration: config))
      await router.handle(shopB, source: .appClipInvocation, model: target)
      precondition(target.isShopOnly && target.shopCode == "store", "A shop link can be an invocation")
    }

    // 7. A Live Activity without a widgetURL ranks with an explicit open, above a replay.
    do {
      let router = InvocationRouter()
      let target = MachineLoginViewModel(api: PrismAPI(configuration: config))
      await router.handle(machineA, source: .appClipInvocation, model: target)
      await router.handle(shopB, source: .liveActivity, model: target)
      precondition(target.isShopOnly, "The live-activity fallback must outrank a replayed invocation")
    }

    // 6. Re-tapping the open link refreshes in place, so a settled receipt survives it.
    active = true
    await shopOnly.handleResolvedInvocation(shopB)
    checkoutCalls = 2
    let replayCheckoutBtn = shopOnly.page!.allBlocks().compactMap { if case .button(let b) = $0, b.id == "checkout" { return b }; return nil }.first!
    await shopOnly.press(replayCheckoutBtn)
    precondition(shopOnly.settlement != nil)
    await shopOnly.finishCheckout()
    await shopOnly.handleResolvedInvocation(shopB)
    precondition(shopOnly.page?.bill()?.mode == "settled", "A replayed link must not discard the settled receipt")

    // Observe actual state transitions instead of asserting source-code snippets.
    let freshShop = MachineLoginViewModel(api: PrismAPI(configuration: config))
    active = true
    var shopStates: [MachineLoginViewModel.State] = []
    let observation = freshShop.$state.sink { shopStates.append($0) }
    let readsBeforeOpen = shopPageReads
    await freshShop.handleResolvedInvocation(shopB)
    precondition(shopStates == [.idle, .loadingShop, .loadingCards, .ready])
    precondition(freshShop.playerStateLoaded && freshShop.page?.bill()?.mode == "live")
    precondition(shopPageReads == readsBeforeOpen + 1, "Opening a shop reads /player/page once")
    observation.cancel()
    // A missing shop or a failed read must be retryable, never a permanent loading state.
    shopStatus = 404
    let failedShop = MachineLoginViewModel(api: PrismAPI(configuration: config))
    await failedShop.handleResolvedInvocation(shopB)
    if case .failed = failedShop.state {} else { preconditionFailure("Public shop failure must be visible") }
    shopStatus = 200
    await failedShop.handleResolvedInvocation(shopB)
    precondition(failedShop.state == .ready && failedShop.page?.bill()?.mode == "live")
    let billFailure = MachineLoginViewModel(api: PrismAPI(configuration: config))
    previewStatus = 400
    await billFailure.handleResolvedInvocation(shopB)
    if case .failed = billFailure.state {} else { preconditionFailure("Shop page error must surface") }
    previewStatus = 200
    await billFailure.handleResolvedInvocation(shopB)
    precondition(billFailure.state == .ready && billFailure.page?.bill()?.mode == "live")

    let activating = MachineLoginViewModel(api: PrismAPI(configuration: config))
    FixtureProtocol.holdNextIdentityResponse = true
    let opening = Task { await activating.handleResolvedInvocation(shopB) }
    let activationDeadline = Date().addingTimeInterval(10)
    while (activating.state != .loadingCards || FixtureProtocol.heldIdentityReply == nil) && Date() < activationDeadline {
      try await Task.sleep(nanoseconds: 1_000_000)
    }
    precondition(activating.state == .loadingCards && FixtureProtocol.heldIdentityReply != nil, "Identity must still be loading")
    await activating.setSceneActive(false)
    await activating.setSceneActive(true)
    let activationReply = FixtureProtocol.heldIdentityReply!; FixtureProtocol.heldIdentityReply = nil; activationReply()
    await opening.value
    precondition(activating.state == .ready && activating.page?.bill()?.mode == "live",
                 "An activation transition during account loading must not strand the page")
    active = false; lastReceipt = nil
    await freshShop.refreshVisit()
    precondition(freshShop.playerStateLoaded && freshShop.page?.bill() == nil)
    precondition(freshShop.shopBillingState == "未入场")

    // Signing out on a shop page keeps the shop hero card and shows the server sign-in block.
    member = true
    await shopOnly.handleResolvedInvocation(shopB)
    await shopOnly.logout()
    precondition(StoreVisitLiveActivityManager.shared.unregisteredAll, "Logout must trigger unregisterAllPushTokens")
    precondition(StoreVisitLiveActivityManager.shared.lastApi?.baseURL == origin, "Unregister must use origin-scoped API")
    precondition(shopOnly.state == .unauthenticated)
    precondition(shopOnly.user == nil && shopOnly.summary == nil && shopOnly.settlement == nil, "Logout must clear private account state")
    precondition(shopOnly.lastShopHero?.name == "Store" && shopOnly.page?.asksToSignIn == true, "Sign-out must keep the shop card and show sign-in")
    precondition(shopOnly.lastShopHero?.heroUrl == "/api/v1/shops/store/hero?v=abc123")

    // Signing back in afterwards completes via reloadCards().
    signedIn = true
    await shopOnly.reloadCards()
    precondition(shopOnly.state == .ready && shopOnly.page != nil && !shopOnly.page!.asksToSignIn, "Sign-in on a shop page must complete")
    precondition(shopOnly.playerStateLoaded, "The signed-in shop page must have loaded the player's state")

    // Registration stays on the invocation: no new machine ticket or physical operation.
    scene = "cards"
    signedIn = false
    let onboarding = MachineLoginViewModel(api: PrismAPI(configuration: config, origin: origin))
    await onboarding.handleResolvedInvocation(origin.appendingPathComponent("t/store/device"))
    precondition(onboarding.state == .unauthenticated && onboarding.page?.asksToSignIn == true, "A stranger is shown the page's own sign-in")
    let onboardingTicket = onboarding.ticket
    let startsBeforeAuth = sessionStarts, actionsBeforeAuth = actions.count
    MunetAuthenticationService.result = .init(code: "oauth-code", suggestPasskey: true)
    await onboarding.authenticateWithMunet()
    precondition(onboarding.suggestPasskey && onboarding.user != nil && onboarding.state == .ready)
    precondition(passkeyRequests == 0, "The suggestion must not automatically register a credential")
    PasskeyAuthenticationService.cancelRegistration = true
    await onboarding.addSuggestedPasskey()
    precondition(onboarding.suggestPasskey && onboarding.errorMessage == nil && !onboarding.addingPasskey)
    precondition(passkeyRequests == 0, "System cancellation must not submit registration")
    PasskeyAuthenticationService.cancelRegistration = false; passkeyStatus = 500
    await onboarding.addSuggestedPasskey()
    precondition(onboarding.suggestPasskey && onboarding.errorMessage != nil && !onboarding.addingPasskey)
    onboarding.skipPasskeySetup()
    precondition(!onboarding.suggestPasskey && onboarding.errorMessage == nil)
    precondition(onboarding.ticket == onboardingTicket && onboarding.publicId == "device")
    precondition(sessionStarts == startsBeforeAuth && actions.count == actionsBeforeAuth)
    // Successful registration also resumes this exact invocation.
    await onboarding.logout()
    precondition(onboarding.state == .unauthenticated && onboarding.page?.asksToSignIn == true, "Signing out leaves the signed-out page")
    await onboarding.authenticateWithMunet()
    precondition(onboarding.suggestPasskey)
    passkeyStatus = 200
    await onboarding.addSuggestedPasskey()
    precondition(!onboarding.suggestPasskey && onboarding.errorMessage == nil)
    precondition(onboarding.ticket == onboardingTicket && sessionStarts == startsBeforeAuth)
    // Returning users are not prompted, and logging out clears the suggestion.
    await onboarding.logout()
    MunetAuthenticationService.result = .init(code: "oauth-code", suggestPasskey: false)
    await onboarding.authenticateWithMunet()
    precondition(!onboarding.suggestPasskey && onboarding.state == .ready)

    // An unusable link clears the shop and fails without touching the previous session.
    await shopOnly.handleResolvedInvocation(URL(string: "https://link-beta.neri.moe/not-a-link")!)
    precondition(!shopOnly.isShopOnly && shopOnly.shopCode == nil && shopOnly.ticket == nil)
    for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("prism.operation.\(origin.absoluteString).\(testUser).") { UserDefaults.standard.removeObject(forKey:key) }
    print("App Clip native visit checks passed")
  }
}
