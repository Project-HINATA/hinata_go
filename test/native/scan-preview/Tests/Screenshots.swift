import XCTest

final class ScanScreenshots: XCTestCase {
  func testHeroBeforeIdentity() {
    let app = XCUIApplication()
    app.launchArguments = ["auth-held", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.staticTexts["测试店铺"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.staticTexts["测试机台"].exists)
    attach(app, name: "scan-auth-loading")
  }
  func testScannedPage() {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.staticTexts["测试 Aime"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.staticTexts["测试店铺"].exists)
    XCTAssertTrue(app.staticTexts["选择卡片"].exists && app.buttons["投币"].exists)
    XCTAssertFalse(app.alerts.firstMatch.exists)
    attach(app, name: "scan-page")
  }
  /// A page whose only content is its state: drawn as a whole-page message with its icon.
  func testStatusPages() {
    for (fixture, title) in [("disabled", "玩家资格已停用"), ("ioWaiting", "等待机台连接"), ("entryError", "暂时无法使用"), ("empty", "这里没有可操作的设备")] {
      let app = XCUIApplication()
      app.launchArguments = ["page=\(fixture)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 20), fixture)
      attach(app, name: "status-\(fixture)")
      app.terminate()
    }
  }
  /// An action's outcome where the player acted, one of each nature: news fades, an error stays.
  func testNoticeClassification() {
    let cases = [
      ("alert-rate", "door", "RATE_LIMITED", "获取开门密码", "操作过于频繁，请稍后再试", true),
      ("status-device", "door", "DEVICE_UNAVAILABLE", "获取开门密码", "设备连接失败，请联系店员", false),
      ("toast-door", "door", "DOOR_CODE_FAILED", "获取开门密码", "开门密码获取失败，请重试", false),
      ("coin-disabled", "cardsCapture", "COIN_COOLDOWN", "投币", "请稍后再投币", false),
    ]
    for (name, page, code, label, body, alert) in cases {
      let app = XCUIApplication()
      app.launchArguments = ["page=\(page)", "notice-codes=\(code)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      XCTAssertTrue(app.buttons[label].waitForExistence(timeout: 20))
      app.buttons[label].tap()
      XCTAssertTrue(app.staticTexts[body].waitForExistence(timeout: 10))
      XCTAssertEqual(app.alerts.firstMatch.exists, alert)
      if code == "COIN_COOLDOWN" {
        XCTAssertFalse(app.buttons.containing(.staticText, identifier: body).firstMatch.isEnabled)
      }
      if code == "DOOR_CODE_FAILED" {
        XCTAssertLessThan(app.staticTexts[body].frame.minY, app.frame.height * 0.15)
      }
      attach(app, name: name)
      if code == "DEVICE_UNAVAILABLE" || code == "REDEEM_CODE_NOT_FOUND" {
        Thread.sleep(forTimeInterval: 5)
        XCTAssertTrue(app.staticTexts[body].exists)
      }
      app.terminate()
    }
    let app = XCUIApplication()
    app.launchArguments = ["checkout-insufficient", "notice-codes=INSUFFICIENT_BALANCE", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.buttons["结账"].waitForExistence(timeout: 20))
    app.buttons["结账"].tap()
    XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
    attach(app, name: "alert-balance")
  }

  func testAllServerNotices() {
    let url = Bundle(for: Self.self).url(forResource: "pages", withExtension: "json")!
    let fixture = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let selected = ProcessInfo.processInfo.environment["PRISM_NOTICE_CODES"].map { Set($0.split(separator: ",").map(String.init)) }
    for item in fixture["screenshots"] as! [[String: Any]] {
      if let selected, !selected.contains(item["code"] as! String) { continue }
      let code = item["code"] as! String
      let app = XCUIApplication()
      app.launchArguments = ["audit-code=\(code)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      let action = item["action"] as! String
      if action == "none" {
        XCTAssertTrue(app.staticTexts["测试店铺"].waitForExistence(timeout: 20), code)
      } else {
        let target: XCUIElement
        switch action {
        case "card": target = app.buttons.containing(.staticText, identifier: "测试 Aime").firstMatch
        case "coin": target = app.buttons["投币"]
        case "capture": target = app.buttons["添加卡片"].firstMatch
        case "consent":
          let consent = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "确认开始计费")).firstMatch
          XCTAssertTrue(consent.waitForExistence(timeout: 20), code)
          consent.tap()
          target = app.buttons["入场并获取开门密码"]
        case "redeem":
          let input = app.textFields["兑换码"]
          XCTAssertTrue(input.waitForExistence(timeout: 20), code)
          input.tap()
          input.typeText("BAD")
          target = app.buttons["兑换"]
        default: target = app.buttons["获取开门密码"]
        }
        XCTAssertTrue(target.waitForExistence(timeout: 20), code)
        if action == "capture" {
          expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: target)
          waitForExpectations(timeout: 10)
        }
        target.tap()
        if code == "CAPTURE_WAITING", !app.buttons["取消"].waitForExistence(timeout: 3) {
          // The simulator can drop the first tap while the launch layout settles.
          target.tap()
        }
        if code == "CAPTURE_LEFT_PAGE" {
          XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "读卡器")).firstMatch.waitForExistence(timeout: 10))
          XCUIDevice.shared.press(.home)
          app.activate()
        }
        if code == "TICKET_EXPIRED" {
          XCTAssertTrue(app.staticTexts["本次会话已失效"].waitForExistence(timeout: 10), code)
        } else {
          if let body = item["body"] as? String, !body.isEmpty {
            XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", body)).firstMatch.waitForExistence(timeout: 10), code)
          }
          XCTAssertEqual(app.alerts.firstMatch.exists, item["display"] as? String == "dialog", code)
          if code == "DEVICE_UNAVAILABLE" { XCTAssertFalse(app.buttons["获取开门密码"].exists) }
          if ["DEVICE_RESULT_UNKNOWN", "OPERATION_PENDING", "OPERATION_IN_PROGRESS", "COIN_UNKNOWN"].contains(code) { XCTAssertFalse(app.alerts.firstMatch.exists) }
          if code == "LOCATION_REQUIRED" { XCTAssertTrue(app.alerts.buttons["前往设置"].exists) }
        }
      }
      if item["presentation"] as? String == "page", let body = item["body"] as? String, !body.isEmpty {
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", body)).firstMatch.waitForExistence(timeout: 10), code)
      }
      if code.hasPrefix("PRICING_") {
        XCTAssertTrue(app.staticTexts[item["body"] as! String].exists, code)
      }
      if code == "PLATFORM_BINDING_REQUIRED" {
        XCTAssertTrue(app.staticTexts["bind ABC12345"].waitForExistence(timeout: 10))
      }
      attach(app, name: "all-\(code)")
      app.terminate()
    }
  }

  func testToastSwipeDismissal() {
    for direction in ["left", "right", "up", "down"] {
      let app = XCUIApplication()
      app.launchArguments = ["page=door", "notice-codes=DOOR_CODE_FAILED", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      XCTAssertTrue(app.buttons["获取开门密码"].waitForExistence(timeout: 20))
      app.buttons["获取开门密码"].tap()
      let toast = app.descendants(matching: .any)["page-toast"].firstMatch
      XCTAssertTrue(toast.waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试玩家")).firstMatch.exists)
      switch direction {
      case "left": toast.swipeLeft()
      case "right": toast.swipeRight()
      case "up": toast.swipeUp()
      default: toast.swipeDown()
      }
      if direction == "down" {
        XCTAssertTrue(toast.exists)
        attach(app, name: "toast-over-controls")
      } else {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: toast)
        waitForExpectations(timeout: 2)
      }
      app.terminate()
    }
  }

  func testSheetNoticeClassification() {
    for view in ["兑换", "账单"] {
      let app = XCUIApplication()
      app.launchArguments = ["page=door", "sheet-preview=\(view == "兑换" ? "redeem" : "bill")", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      let menu = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试玩家")).firstMatch
      XCTAssertTrue(menu.waitForExistence(timeout: 20))
      menu.tap()
      app.buttons[view].tap()
      if view == "兑换" {
        let input = app.textFields["兑换码"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("BAD")
        app.buttons["兑换"].tap()
        XCTAssertTrue(app.staticTexts["兑换码无效"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.firstMatch.exists)
        attach(app, name: "alert-redeem")
        app.alerts.buttons["知道了"].tap()
        XCTAssertEqual(input.value as? String, "BAD")
      } else {
        XCTAssertTrue(app.buttons["结账"].waitForExistence(timeout: 10))
        app.buttons["结账"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        attach(app, name: "sheet-alert-balance")
      }
      app.terminate()
    }
  }

  func testInlineNotices() {
    let cases: [(name: String, page: String, notices: String, tap: (XCUIApplication) -> XCUIElement, shows: String)] = [
      ("door-error", "door", "error:开门密码获取失败，请重试", { $0.buttons["获取开门密码"] }, "开门密码获取失败，请重试"),
      ("door-info", "door", "info:操作过于频繁，请稍后再试", { $0.buttons["获取开门密码"] }, "操作过于频繁，请稍后再试"),
      ("coin-info", "cardsCapture", "info:请稍后再投币", { $0.buttons["投币"] }, "请稍后再投币"),
      ("coin-success", "cardsCapture", "success:已投币", { $0.buttons["投币"] }, "已投币"),
      ("card-mixed", "cardsCapture", "success:已刷卡;error:投币失败", { $0.buttons.containing(.staticText, identifier: "测试 Aime").firstMatch }, "投币失败"),
    ]
    for item in cases {
      let app = XCUIApplication()
      app.launchArguments = ["page=\(item.page)", "notices=\(item.notices)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      let target = item.tap(app)
      XCTAssertTrue(target.waitForExistence(timeout: 20), item.name)
      target.tap()
      XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", item.shows)).firstMatch.waitForExistence(timeout: 10), item.name)
      if item.name.hasPrefix("coin") {
        XCTAssertFalse(app.buttons.containing(.staticText, identifier: item.shows).firstMatch.isEnabled)
      }
      // The coin and the cards sit below the fold.
      if !item.name.hasPrefix("door") { app.swipeUp(velocity: .slow) }
      attach(app, name: "notice-\(item.name)")
      if item.name.hasPrefix("coin") {
        let ready = NSPredicate(format: "enabled == true")
        expectation(for: ready, evaluatedWith: app.buttons["投币"])
        waitForExpectations(timeout: 7)
      }
      app.terminate()
    }
    let app = XCUIApplication()
    app.launchArguments = ["checkout-insufficient", "notices=info:请离开店铺定位范围后再结账", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let checkout = app.buttons["结账"]
    XCTAssertTrue(checkout.waitForExistence(timeout: 20))
    checkout.tap()
    XCTAssertTrue(app.staticTexts["请离开店铺定位范围后再结账"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.alerts.firstMatch.exists)
    attach(app, name: "notice-checkout-info")
  }
  func testInsufficientBalanceChinese() {
    checkBalance(language: "zh-Hans", locale: "zh_CN", button: "结账", copy: "余额不足，请充值后再结账，计费会继续", dismiss: "知道了")
  }
  func testInsufficientBalanceEnglish() {
    checkBalance(language: "en", locale: "en_US", button: "Check out", copy: "Not enough balance. Top up and check out again; billing continues.", dismiss: "OK")
  }
  private func checkBalance(language: String, locale: String, button: String, copy: String, dismiss: String) {
    let app = XCUIApplication()
    app.launchArguments = ["checkout-insufficient", "-AppleLanguages", "(\(language))", "-AppleLocale", locale]
    app.launch()
    let checkout = app.buttons[button]
    XCTAssertTrue(checkout.waitForExistence(timeout: 20))
    checkout.tap()
    XCTAssertTrue(app.alerts.staticTexts[copy].waitForExistence(timeout: 10))
    XCTAssertFalse(app.staticTexts["Insufficient currency holdings for this operation."].exists)
    attach(app, name: "checkout-insufficient-\(language)")
    app.alerts.buttons[dismiss].tap()
    XCTAssertTrue(checkout.isEnabled)
  }
  /// Pages from a real local server, when the runner is given one (see App.swift); each screen
  /// of the page from the top, scrolling a screen at a time.
  func testLivePages() throws {
    let (app, name) = try launchLive()
    let screens = Int(ProcessInfo.processInfo.environment["PRISM_PREVIEW_SCREENS"] ?? "3") ?? 3
    for index in 1...screens {
      attach(app, name: "\(name ?? "live")-\(index)")
      app.swipeUp(velocity: .slow)
      sleep(1)
    }
  }
  /// The bill a billing player opens from the account menu, at both sheet heights.
  func testLiveBillSheet() throws {
    let (app, name) = try launchLive()
    let menu = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "计费中")).firstMatch
    XCTAssertTrue(menu.waitForExistence(timeout: 30))
    menu.tap()
    app.buttons["账单"].firstMatch.tap()
    XCTAssertTrue(app.staticTexts["合计"].waitForExistence(timeout: 30))
    sleep(2)
    attach(app, name: "\(name ?? "sheet")-medium")
    let title = app.staticTexts["账单"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    title.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
    sleep(2)
    attach(app, name: "\(name ?? "sheet")-large")
  }
  private func launchLive() throws -> (XCUIApplication, String?) {
    let environment = ProcessInfo.processInfo.environment
    guard let link = environment["PRISM_PREVIEW_LINK"] else { throw XCTSkip("No local server given") }
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    for key in ["PRISM_API_ORIGIN", "PRISM_PREVIEW_SESSION", "PRISM_PREVIEW_LINK", "TZ"] { app.launchEnvironment[key] = environment[key] }
    app.launch()
    let ready = environment["PRISM_PREVIEW_WAIT_FOR"] ?? "合计"
    XCTAssertTrue(app.staticTexts[ready].waitForExistence(timeout: 30), "\(link) did not show \(ready)")
    sleep(2)
    return (app, environment["PRISM_PREVIEW_NAME"])
  }
  private func attach(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways
    add(attachment)
  }
}
