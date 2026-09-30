import XCTest

final class LockScreenScreenshots: XCTestCase {
  func testBilling() throws { try capture("billing", status: "计费中") }
  func testCapped() throws { try capture("capped", status: "本时段已封顶") }
  func testPaused() throws { try capture("paused", status: "暂停计费") }
  func testLongShop() throws { try capture("long-shop", status: "计费中") }
  func testLargeAmount() throws { try capture("large-amount", status: "计费中") }
  func testMissingPrevious() throws { try capture("missing-previous", status: "计费中") }
  func testAwaitingCheckout() throws { try capture("awaiting-checkout", status: "待结账", terminal: true) }
  func testSettled() throws { try capture("settled", status: "已结清", terminal: true) }

  private func capture(_ mode: String, status: String, terminal: Bool = false) throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    if app.state == .notRunning { app.launch() } else { app.activate() }
    sleep(2) // Let Notification Center dismissal / app activation finish.
    let previousResult = app.staticTexts["result"].label
    app.buttons[mode].tap()
    let started = app.staticTexts.matching(NSPredicate(format:
      "label BEGINSWITH %@ AND label != %@", "已启动 \(mode) ", previousResult)).firstMatch
    if !started.waitForExistence(timeout: 5) {
      app.buttons[mode].tap()
    }
    XCTAssertTrue(started.waitForExistence(timeout: 30), app.debugDescription)
    XCUIDevice.shared.press(.home)
    sleep(3)

    // Notification Center renders ActivityConfiguration's real Lock Screen
    // presentation, including system background and rounded-corner clipping.
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
      .press(forDuration: 0.1, thenDragTo:
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)))
    // A fresh simulator may show its one-time Live Activity consent prompt.
    let allow = springboard.buttons.matching(NSPredicate(format:
      "label == %@ OR label == %@", "允许", "始终允许")).firstMatch
    if allow.waitForExistence(timeout: 3) { allow.tap() }
    let statusLabel = element(containing: status, in: springboard)
    XCTAssertTrue(statusLabel.waitForExistence(timeout: 20), springboard.debugDescription)
    let amount = mode == "large-amount" ? "1,234.56" : mode == "capped" ? "¥48" : "¥24"
    XCTAssertTrue(element(containing: amount, in: springboard).waitForExistence(timeout: 20),
      springboard.debugDescription)
    // Consent can arrive with the first rendered card, after the early check.
    if allow.exists { allow.tap() }
    if terminal {
      XCTAssertTrue(element(containing: mode == "settled" ? "支付完成" : "本次费用已确定",
        in: springboard).exists, springboard.debugDescription)
      XCTAssertFalse(element(containing: "距下次事件", in: springboard).exists)
    } else {
      XCTAssertTrue(element(containing: "上一事件", in: springboard).exists,
        springboard.debugDescription)
      if mode == "missing-previous" {
        XCTAssertTrue(element(containing: "待更新", in: springboard).exists)
      } else if mode == "long-shop" {
        XCTAssertTrue(element(containing: "超长店铺名称", in: springboard)
          .waitForExistence(timeout: 20), springboard.debugDescription)
      }
    }
    sleep(2)
    attach("\(mode)-lock-screen")
    if mode == "billing" {
      sleep(15)
      attach("billing-lock-screen-later")
    }
    XCUIDevice.shared.press(.home)
  }

  private func element(containing text: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
  }

  private func attach(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
