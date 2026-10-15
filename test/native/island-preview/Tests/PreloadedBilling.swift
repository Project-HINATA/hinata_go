import XCTest

final class PreloadedBilling: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testSwitchesWithoutAnUpdate() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    app.launch()
    app.buttons["preloaded"].tap()
    XCTAssertTrue(app.staticTexts["result"].waitForExistence(timeout: 20))
    let started = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "已启动 preloaded ")).firstMatch
    XCTAssertTrue(started.waitForExistence(timeout: 20), app.debugDescription)
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
      .press(forDuration: 0.1, thenDragTo:
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)))
    let allow = springboard.buttons.matching(NSPredicate(format:
      "label == %@ OR label == %@", "允许", "始终允许")).firstMatch
    if allow.waitForExistence(timeout: 5) { allow.tap() }
    let amount = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", "¥24")).firstMatch
    XCTAssertTrue(amount.waitForExistence(timeout: 20), springboard.debugDescription)
    attach("preloaded-before")
    // No app activation, local update or APNs push between these assertions.
    let projected = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", "¥26")).firstMatch
    XCTAssertTrue(projected.waitForExistence(timeout: 150), springboard.debugDescription)
    XCTAssertTrue(springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "计费中")).firstMatch.exists,
      springboard.debugDescription)
    attach("preloaded-after-without-push")
    XCUIDevice.shared.press(.home)
    let compact = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "26")).firstMatch
    XCTAssertTrue(compact.waitForExistence(timeout: 20), springboard.debugDescription)
    attach("preloaded-compact")
    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
      .press(forDuration: 1.5)
    XCTAssertTrue(projected.waitForExistence(timeout: 20), springboard.debugDescription)
    attach("preloaded-expanded")
    XCUIDevice.shared.press(.home)
    // Relaunch the fixture host; the ActivityKit activity must survive it.
    app.terminate()
    app.launch()
    XCTAssertTrue(app.buttons["settle-preloaded"].waitForExistence(timeout: 10))
    app.buttons["settle-preloaded"].tap()
    attach("settlement-requested")
    XCTAssertTrue(app.staticTexts["已结清"].waitForExistence(timeout: 30), app.debugDescription)
    XCUIDevice.shared.press(.home)
    springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
      .press(forDuration: 0.1, thenDragTo:
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.8)))
    let settled = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label CONTAINS %@", "¥25")).firstMatch
    XCTAssertTrue(settled.waitForExistence(timeout: 20), springboard.debugDescription)
    XCTAssertFalse(springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", "计费中")).firstMatch.exists)
    attach("settlement-overrides-forecast")
  }

  private func attach(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
