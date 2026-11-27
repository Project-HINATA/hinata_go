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
  func testInlineNotices() {
    let cases: [(name: String, page: String, notices: String, tap: (XCUIApplication) -> XCUIElement, shows: String)] = [
      ("door-error", "doorCardsCoin", "error:开门密码获取失败，请重试", { $0.buttons["获取开门密码"] }, "开门密码获取失败，请重试"),
      ("door-info", "doorCardsCoin", "info:操作过于频繁，请稍后再试", { $0.buttons["获取开门密码"] }, "操作过于频繁，请稍后再试"),
      ("coin-info", "doorCardsCoin", "info:请稍后再投币", { $0.buttons["投币"] }, "请稍后再投币"),
      ("coin-success", "doorCardsCoin", "success:已投币", { $0.buttons["投币"] }, "已投币"),
      ("card-mixed", "doorCardsCoin", "success:已刷卡;error:投币失败", { $0.buttons.containing(.staticText, identifier: "测试 Aime").firstMatch }, "投币失败"),
    ]
    for item in cases {
      let app = XCUIApplication()
      app.launchArguments = ["page=\(item.page)", "notices=\(item.notices)", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
      app.launch()
      let target = item.tap(app)
      XCTAssertTrue(target.waitForExistence(timeout: 20), item.name)
      target.tap()
      XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", item.shows)).firstMatch.waitForExistence(timeout: 10), item.name)
      // The coin and the cards sit below the fold.
      if !item.name.hasPrefix("door") { app.swipeUp(velocity: .slow) }
      attach(app, name: "notice-\(item.name)")
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
    checkBalance(language: "zh-Hans", locale: "zh_CN", button: "结账", copy: "余额不足，请充值后重试", dismiss: "知道了")
  }
  func testInsufficientBalanceEnglish() {
    checkBalance(language: "en", locale: "en_US", button: "Check out", copy: "Insufficient balance. Please top up and try again.", dismiss: "OK")
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
