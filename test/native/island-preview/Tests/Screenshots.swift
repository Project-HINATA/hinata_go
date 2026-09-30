import XCTest

final class Screenshots: XCTestCase {
  func testBilling() throws { try capture(["billing"]) }
  func testCapped() throws { try capture(["capped"]) }
  func testPaused() throws { try capture(["paused"]) }
  func testLongShop() throws { try capture(["long-shop"]) }

  private func capture(_ modes: [String]) throws {
    let app = XCUIApplication()
    app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    if app.state == .notRunning { app.launch() } else { app.activate() }
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for mode in modes {
      app.activate()
      app.buttons[mode].tap()
      XCTAssertTrue(app.staticTexts["已启动"].waitForExistence(timeout: 10))
      XCUIDevice.shared.press(.home)
      sleep(10)
      springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04))
        .press(forDuration: 1.5)
      let timeline = springboard.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@", "上一事件")).firstMatch
      XCTAssertTrue(timeline.waitForExistence(timeout: 20), springboard.debugDescription)
      sleep(3)
      attach("\(mode)-expanded")
      if mode == "billing" {
        sleep(15)
        attach("billing-expanded-later")
      }
      springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
      let amount = springboard.descendants(matching: .any)
        .matching(NSPredicate(format: "label == %@", mode == "capped" ? "48" : "24")).firstMatch
      XCTAssertTrue(amount.waitForExistence(timeout: 30), springboard.debugDescription)
      sleep(3)
      attach("\(mode)-compact")
    }
  }

  private func attach(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
