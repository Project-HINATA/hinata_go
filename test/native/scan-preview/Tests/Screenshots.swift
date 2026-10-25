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
  func testCardsBeforePower() {
    let app = XCUIApplication()
    app.launchArguments = ["power-held", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    XCTAssertTrue(app.staticTexts["测试 Aime"].waitForExistence(timeout: 20))
    XCTAssertTrue(app.staticTexts["测试店铺"].exists)
    XCTAssertFalse(app.alerts.firstMatch.exists)
    attach(app, name: "scan-cards-before-power")
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
    let environment = ProcessInfo.processInfo.environment
    guard let link = environment["PRISM_PREVIEW_LINK"] else { throw XCTSkip("No local server given") }
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    for key in ["PRISM_API_ORIGIN", "PRISM_PREVIEW_SESSION", "PRISM_PREVIEW_LINK", "TZ"] { app.launchEnvironment[key] = environment[key] }
    app.launch()
    let ready = environment["PRISM_PREVIEW_WAIT_FOR"] ?? "合计"
    XCTAssertTrue(app.staticTexts[ready].waitForExistence(timeout: 30), "\(link) did not show \(ready)")
    sleep(2)
    let screens = Int(environment["PRISM_PREVIEW_SCREENS"] ?? "3") ?? 3
    for index in 1...screens {
      attach(app, name: "\(environment["PRISM_PREVIEW_NAME"] ?? "live")-\(index)")
      app.swipeUp(velocity: .slow)
      sleep(1)
    }
  }
  private func attach(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways
    add(attachment)
  }
}
