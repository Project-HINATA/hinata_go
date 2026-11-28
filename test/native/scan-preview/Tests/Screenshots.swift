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

  func testAccountNavigationAndFloatingFooters() {
    let app = XCUIApplication()
    app.launchArguments = ["page=door", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    let menu = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "测试玩家")).firstMatch
    XCTAssertTrue(menu.waitForExistence(timeout: 20))
    menu.tap()
    app.buttons["账单"].tap()
    XCTAssertTrue(app.buttons["结账"].waitForExistence(timeout: 10))
    attach(app, name: "bill-floating-footer")
    app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["关闭", "Close"])).firstMatch.tap()
    menu.tap()
    app.buttons["记录"].tap()
    let record = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "11:00 – 12:00")).firstMatch
    XCTAssertTrue(record.waitForExistence(timeout: 10))
    record.tap()
    XCTAssertTrue(app.navigationBars["账单详情"].waitForExistence(timeout: 10))
    XCTAssertTrue(app.navigationBars.buttons["记录"].exists)
    attach(app, name: "history-native-detail")
    app.navigationBars.buttons["记录"].tap()
    XCTAssertTrue(record.waitForExistence(timeout: 10))
    XCTAssertTrue(app.navigationBars["记录"].exists)
    attach(app, name: "history-native-return")
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
  /// The recharge sheet against a local server whose shop sells "50 元余额" and has a photo of a
  /// receipt as the newest one in the simulator's library (`simctl addmedia`). Grants that product once.
  /// Run with `PRISM_PREVIEW_WAIT_FOR` set to the shop's name.
  func testLiveRecharge() throws {
    guard ProcessInfo.processInfo.environment["PRISM_PREVIEW_RECHARGE"] != nil else { throw XCTSkip("No local store given") }
    let (app, _) = try launchLive()
    continueAfterFailure = true

    func text(_ label: String) -> XCUIElement { app.staticTexts[label].firstMatch }
    func button(containing label: String) -> XCUIElement {
      app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
    func settle() { sleep(2) }
    /// Where the sheet's title sits tells its height: near the top when full, lower half when not.
    func titleHeight(_ title: String) -> CGFloat { app.navigationBars[title].frame.minY / app.frame.height }
    func assertClear(_ element: XCUIElement, of footer: XCUIElement, _ what: String) {
      XCTAssertTrue(element.exists, "\(what) is missing")
      XCTAssertFalse(element.frame.intersects(footer.frame), "\(what) \(element.frame) is under the footer \(footer.frame)")
      XCTAssertLessThanOrEqual(element.frame.maxY, app.frame.maxY, "\(what) is off screen")
    }
    func openAccount(_ entry: String) {
      let menu = button(containing: "用户")
      XCTAssertTrue(menu.waitForExistence(timeout: 15))
      menu.tap()
      let item = app.buttons[entry].firstMatch
      XCTAssertTrue(item.waitForExistence(timeout: 10))
      item.tap()
    }

    button(containing: "用户").tap()
    XCTAssertTrue(app.buttons["充值"].firstMatch.waitForExistence(timeout: 10))
    attach(app, name: "r1-account-menu")
    app.buttons["充值"].firstMatch.tap()

    XCTAssertTrue(app.buttons["自助购买"].waitForExistence(timeout: 20))
    settle()
    XCTAssertGreaterThan(titleHeight("充值"), 0.35, "The sheet starts at half height")
    attach(app, name: "r2-code-tab")

    app.buttons["自助购买"].tap()
    let product = button(containing: "50 元余额")
    XCTAssertTrue(product.waitForExistence(timeout: 20))
    settle()
    attach(app, name: "r3-products")

    // The tabs are a segmented control a finger can drag along.
    app.buttons["自助购买"].press(forDuration: 0.3, thenDragTo: app.buttons["兑换码"], withVelocity: .slow, thenHoldForDuration: 0.3)
    XCTAssertTrue(app.buttons["兑换"].waitForExistence(timeout: 10), "Dragging the selection switches tabs")
    XCTAssertTrue(app.buttons["兑换码"].isSelected)
    app.buttons["自助购买"].tap()
    XCTAssertTrue(product.waitForExistence(timeout: 10))
    settle()

    product.tap()
    XCTAssertTrue(app.navigationBars["确认购买"].waitForExistence(timeout: 20))
    settle()
    attach(app, name: "r4-confirm-empty")
    XCTAssertLessThan(titleHeight("确认购买"), 0.2, "The confirm step opens the sheet fully")
    let submit = app.buttons["提交凭证并领取"]
    XCTAssertFalse(submit.isEnabled)
    assertClear(text("PNG / JPEG / WebP · ≤ 1 MB"), of: submit, "The upload hint")
    XCTAssertGreaterThan(app.navigationBars["确认购买"].buttons.count, 1, "The confirm step keeps its way back")

    app.buttons["复制"].tap()
    XCTAssertTrue(app.buttons["已复制"].waitForExistence(timeout: 3))

    button(containing: "上传转账凭证").tap()
    // The system picker runs out of process; its photos still answer as elements of this app. Its
    // first opening on a new simulator takes a while, and only the grid's cells carry this identifier.
    let photos = app.images.matching(identifier: "PXGGridLayout-Info")
    XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 90), app.debugDescription)
    settle()
    attach(app, name: "r5-photo-picker")
    // The newest photo, the receipt, is the first in the grid.
    // Another process's cell is not "hittable" to XCTest; a touch at its centre reaches it.
    photos.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    XCTAssertTrue(app.buttons["更换"].waitForExistence(timeout: 30), app.debugDescription)
    settle()
    attach(app, name: "r6-confirm-picked")
    XCTAssertTrue(submit.isEnabled)
    assertClear(app.buttons["更换"], of: submit, "Replace")
    assertClear(app.buttons["移除"], of: submit, "Remove")
    assertClear(app.images["转账凭证预览"].exists ? app.images["转账凭证预览"] : button(containing: "转账凭证预览"), of: submit, "The thumbnail")

    submit.tap()
    XCTAssertTrue(text("充值成功").waitForExistence(timeout: 30), app.debugDescription)
    settle()
    attach(app, name: "r7-receipt")
    XCTAssertLessThan(titleHeight("充值"), 0.2)
    let done = app.buttons["完成"]
    for label in ["本次到账", "+50", "项目", "金额", "订单号", "¥50.00"] { assertClear(text(label), of: done, label) }
    XCTAssertFalse(app.navigationBars["充值"].buttons["BackButton"].exists, "A receipt offers no way back")
    XCTAssertEqual(app.navigationBars["充值"].buttons.count, 1, "Only closing is offered")
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.6))
      .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.6)))
    settle()
    XCTAssertTrue(text("充值成功").exists, "Swiping from the edge must not leave the receipt")

    done.tap()
    XCTAssertTrue(text("充值成功").waitForNonExistence(timeout: 10))
    settle()

    openAccount("充值")
    XCTAssertTrue(app.buttons["兑换"].waitForExistence(timeout: 20), "Reopening starts at the code tab")
    settle()
    XCTAssertGreaterThan(titleHeight("充值"), 0.35, "Reopening starts at half height")
    app.buttons["自助购买"].tap()
    XCTAssertTrue(button(containing: "50 元余额").waitForExistence(timeout: 20))
    button(containing: "50 元余额").tap()
    XCTAssertTrue(app.navigationBars["确认购买"].waitForExistence(timeout: 20))
    settle()
    app.navigationBars["确认购买"].buttons.element(boundBy: 0).tap()
    XCTAssertTrue(button(containing: "100 元余额").waitForExistence(timeout: 20), "Back returns to the products")
    XCTAssertTrue(app.buttons["自助购买"].isSelected)
    settle()
    attach(app, name: "r8-back-to-products")
    app.navigationBars["充值"].buttons.firstMatch.tap()
    settle()

    openAccount("钱包")
    XCTAssertTrue(app.navigationBars["钱包"].waitForExistence(timeout: 20))
    settle()
    attach(app, name: "r9-wallet")

    // A redeemed code ends on the same receipt, with what is held now counting both.
    guard let code = ProcessInfo.processInfo.environment["PRISM_PREVIEW_REDEEM_CODE"] else { return }
    app.navigationBars["钱包"].buttons.firstMatch.tap()
    settle()
    openAccount("充值")
    let field = app.textFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 20))
    field.tap()
    field.typeText(code)
    app.buttons["兑换"].tap()
    XCTAssertTrue(text("兑换成功").waitForExistence(timeout: 20), app.debugDescription)
    settle()
    attach(app, name: "r10-redeem-receipt")
    XCTAssertLessThan(titleHeight("充值"), 0.2)
    for label in ["本次到账", "+50", "项目"] { assertClear(text(label), of: done, label) }
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "现有 100")).firstMatch.exists, app.debugDescription)
    XCTAssertEqual(app.navigationBars["充值"].buttons.count, 1, "Only closing is offered")
    done.tap()
    XCTAssertTrue(text("兑换成功").waitForNonExistence(timeout: 10))
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
