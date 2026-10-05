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
  private func attach(_ app: XCUIApplication, name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name; attachment.lifetime = .keepAlways
    add(attachment)
  }
}
