import AuthenticationServices
import Flutter
import XCTest
import UIKit
@testable import Runner

class RunnerTests: XCTestCase {
  func testAuthenticationCancellationUsesSystemCodes() {
    XCTAssertTrue(isAuthenticationCancellation(NSError(domain: ASAuthorizationError.errorDomain, code: 1001)))
    XCTAssertTrue(isAuthenticationCancellation(NSError(domain: ASWebAuthenticationSessionError.errorDomain, code: 1)))
    XCTAssertTrue(isAuthenticationCancellation(CancellationError()))
    XCTAssertFalse(isAuthenticationCancellation(NSError(domain: ASAuthorizationError.errorDomain, code: 1004)))
    XCTAssertFalse(isAuthenticationCancellation(NSError(domain: ASWebAuthenticationSessionError.errorDomain, code: 2)))
    XCTAssertFalse(isAuthenticationCancellation(NSError(domain: "server", code: 1001,
      userInfo: [NSLocalizedDescriptionKey: "Unable to cancel the request"])))
  }

  @MainActor
  func testFlutterSurfaceStaysVisibleAcrossTabChanges() async throws {
    let window = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
    let shell = try XCTUnwrap(window.rootViewController as? NativeShellViewController)
    let flutter = shell.flutterSurface
    defer { shell.nativeShell(setSelectedIndex: 0) }

    for index in [0, 1, 2, 0] {
      shell.nativeShell(setSelectedIndex: index)
      shell.view.layoutIfNeeded()
      let rendering = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in flutter.isDisplayingFlutterUI }, object: flutter)
      await fulfillment(of: [rendering], timeout: 10)
      XCTAssertTrue(flutter.parent === pageHost(in: shell.viewControllers?[index]))
    }
  }

  /// Lets a UIKit push/pop finish before the next assertion: the coordinator
  /// uses its own content animator, so the stack settles a moment later. The
  /// extra drain also covers UIKit writing the popped page's item back onto
  /// the root, which happens after the coordinator reports completion.
  @MainActor
  private func waitForTransition(_ nav: UINavigationController) {
    for _ in 0..<60 {
      RunLoop.current.run(until: Date().addingTimeInterval(0.02))
      if nav.transitionCoordinator == nil { break }
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.45))
  }

  /// Flutter is a child of whichever page is on top; the page's navigation
  /// controller is the tab that owns the surface.
  @MainActor
  private func pageHost(in slot: UIViewController?) -> UIViewController? {
    (slot as? UINavigationController)?.viewControllers.first ?? slot
  }

  @MainActor
  func testFlutterSurfaceStaysVisibleWithUITabSelection() async throws {
    guard #available(iOS 18.0, *) else { throw XCTSkip("UITab requires iOS 18") }
    let window = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
    let shell = try XCTUnwrap(window.rootViewController as? NativeShellViewController)
    let selected = try XCTUnwrap(shell.selectedViewController)
    let flutter = shell.flutterSurface
    XCTAssertTrue(flutter.parent === pageHost(in: selected))
    let delegate = try XCTUnwrap(shell.delegate)
    let appDelegate = try XCTUnwrap(UIApplication.shared.delegate as? AppDelegate)
    var forwardedSelections: [Int] = []
    appDelegate.nativeShellBridge.onUserSelected = { forwardedSelections.append($0) }
    defer {
      appDelegate.nativeShellBridge.onUserSelected = nil
      shell.nativeShell(setSelectedIndex: 0)
    }

    for index in [1, 2, 0] {
      let target = try XCTUnwrap(shell.viewControllers?[index])
      let previouslySelected = try XCTUnwrap(shell.selectedViewController)
      let tab: UITab
      if shell.tabs.indices.contains(index) {
        tab = shell.tabs[index]
      } else {
        tab = UITab(title: target.tabBarItem.title ?? "Tab \(index)",
          image: nil, identifier: "test-\(index)") { _ in target }
      }

      // UIKit should cancel selection, leaving Flutter active while Dart navigates.
      let allowed = try XCTUnwrap(delegate.tabBarController?(shell, shouldSelectTab: tab))
      XCTAssertFalse(allowed)
      XCTAssertTrue(flutter.parent === pageHost(in: previouslySelected))
      XCTAssertTrue(shell.selectedViewController === previouslySelected)
      XCTAssertEqual(forwardedSelections.last, index)

      // Both callback variants can fire; they must not issue two commands.
      let count = forwardedSelections.count
      XCTAssertFalse(try XCTUnwrap(delegate.tabBarController?(shell, shouldSelect: target)))
      XCTAssertEqual(forwardedSelections.count, count)

      // Simulate Dart's MethodChannel callback once goBranch has changed route.
      shell.nativeShell(setSelectedIndex: index)
      XCTAssertEqual(shell.selectedIndex, index)
      XCTAssertTrue(flutter.parent === pageHost(in: target))
      XCTAssertEqual(forwardedSelections.count, count)

      shell.view.layoutIfNeeded()
      let rendering = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in flutter.isDisplayingFlutterUI }, object: flutter)
      await fulfillment(of: [rendering], timeout: 10)
    }

    // A UITab may have no viewController during preselection.
    let settings = try XCTUnwrap(shell.viewControllers?[2])
    let title = try XCTUnwrap(settings.tabBarItem.title)
    let missingControllerTab = UITab(title: title, image: nil, identifier: "test-nil-vc")
    XCTAssertNil(missingControllerTab.viewController)
    let previous = try XCTUnwrap(shell.selectedViewController)
    XCTAssertFalse(shell.tabBarController(shell, shouldSelectTab: missingControllerTab))
    XCTAssertEqual(forwardedSelections.last, 2)
    XCTAssertTrue(flutter.parent === pageHost(in: previous))
    shell.nativeShell(setSelectedIndex: 2)
    XCTAssertTrue(flutter.parent === pageHost(in: settings))

    // Repeated taps on the active tab should still reset its branch in Flutter.
    let count = forwardedSelections.count
    XCTAssertFalse(shell.tabBarController(shell, shouldSelect: settings))
    XCTAssertEqual(forwardedSelections.count, count + 1)
    XCTAssertEqual(forwardedSelections.last, 2)
  }

  @MainActor
  func testNativeShellActionLayoutAcrossTabsAndChromeChanges() throws {
    let window = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
    let shell = try XCTUnwrap(window.rootViewController as? NativeShellViewController)
    shell.loadViewIfNeeded()
    shell.nativeShell(setActionButton: [
      "symbol": "plus", "label": "Layout regression action", "actionId": "test",
    ])
    let button = try XCTUnwrap(shell.view.subviews.compactMap { $0 as? UIButton }
      .first { $0.accessibilityLabel == "Layout regression action" })
    defer {
      shell.nativeShell(setChromeVisibility: true, dimmed: false)
      shell.nativeShell(setSelectedIndex: 0)
      shell.nativeShell(setActionButton: nil)
    }

    for visible in [true, false, true] {
      shell.nativeShell(setChromeVisibility: visible, dimmed: false)
      for index in 0..<3 {
        shell.nativeShell(setSelectedIndex: index)
        shell.view.setNeedsLayout()
        shell.view.layoutIfNeeded()
        XCTAssertEqual(shell.selectedIndex, index)
        XCTAssertFalse(button.isHidden)
        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertFalse(button.hasAmbiguousLayout)
        let safeFrame = shell.view.safeAreaLayoutGuide.layoutFrame
        XCTAssertGreaterThan(button.frame.width, 0)
        XCTAssertGreaterThanOrEqual(button.frame.minY, safeFrame.minY)
        XCTAssertLessThanOrEqual(button.frame.maxY, safeFrame.maxY - 16 + 0.5)
        XCTAssertEqual(button.frame.maxX, safeFrame.maxX - 16, accuracy: 0.5)

        if !visible {
          XCTAssertEqual(button.frame.maxY, safeFrame.maxY - 16, accuracy: 0.5)
        } else if shell.tabBar.isDescendant(of: shell.view) {
          let barFrame = shell.tabBar.convert(shell.tabBar.bounds, to: shell.view)
          if barFrame.maxY >= safeFrame.maxY {
            XCTAssertLessThanOrEqual(button.frame.maxY, barFrame.minY - 16 + 0.5)
          }
        }
        if #available(iOS 18.0, *) {
          XCTAssertEqual(shell.isTabBarHidden, !visible)
          XCTAssertTrue((shell.viewControllers ?? []).allSatisfy {
            $0.additionalSafeAreaInsets.bottom == 0
          })
        }
      }
    }
  }

  @MainActor
  func testNativeTopBarUsesLogoOnlyOnTheRootPage() throws {
    let (shell, bar, nav) = try nativeTopBar()
    defer { restoreTopBar(bar, nav) }
    let root = try XCTUnwrap(nav.viewControllers.first)
    XCTAssertTrue(
      pageHost(in: nav) === shell.flutterSurface.parent,
      "Flutter must start on the selected tab (selected=\(shell.selectedIndex))")

    bar.reset(["token": 1, "title": "HINATA Go", "logo": true])
    XCTAssertEqual(nav.viewControllers.count, 1)
    XCTAssertNil(root.navigationItem.title)
    XCTAssertNotNil(root.navigationItem.titleView)

    bar.push(["token": 2, "title": "Scan History Logs", "back": true,
              "actions": [["icon": "trash", "label": "Delete"]]])
    waitForTransition(nav)
    XCTAssertEqual(
      nav.viewControllers.count, 2,
      "selected=\(shell.selectedIndex) sameNav=\(shell.selectedViewController === nav) "
        + "parent=\(String(describing: shell.flutterSurface.parent))")
    let top = try XCTUnwrap(nav.topViewController)
    XCTAssertEqual(top.navigationItem.title, "Scan History Logs")
    XCTAssertNil(top.navigationItem.titleView)
    XCTAssertEqual(top.navigationItem.leftBarButtonItems?.count, 1)
    XCTAssertEqual(top.navigationItem.rightBarButtonItems?.count, 1)
    // The push runs UIKit's own transition, so the stack settles asynchronously.
    waitForTransition(nav)
    XCTAssertTrue(
      shell.selectedViewController === nav,
      "the selected tab changed mid-test (selected=\(shell.selectedIndex))")
    // The placeholder transition moves no Flutter content: the surface must
    // stay in the window even though its root controller is no longer on top.
    let flutter = shell.flutterSurface
    XCTAssertTrue(
      flutter.parent === nav.topViewController,
      "Flutter left the top page during the push (parent=\(String(describing: flutter.parent)))")
    XCTAssertNotNil(flutter.view.window)
    XCTAssertFalse(flutter.view.isHidden)
    XCTAssertGreaterThan(flutter.view.frame.width, 0)
    XCTAssertGreaterThan(flutter.view.frame.height, 0)
    XCTAssertTrue(flutter.view.isDescendant(of: nav.view))
    nav.popViewController(animated: false)
    waitForTransition(nav)
    XCTAssertEqual(nav.viewControllers.count, 1)
    XCTAssertNotNil(root.navigationItem.titleView)

    // The custom close leading (NDEF editor, firmware update) and an action
    // menu are built as real bar items.
    XCTAssertTrue(
      shell.selectedViewController === nav,
      "the selected tab changed mid-test (selected=\(shell.selectedIndex))")
    bar.reset(["token": 3, "title": "Edit NDEF", "leading": "close",
               "actions": [[
                 "icon": "ellipsis",
                 "menu": [["title": "One"], ["divider": true],
                          ["title": "Two", "destructive": true]],
               ]]])
    XCTAssertEqual(nav.viewControllers.count, 1)
    XCTAssertEqual(root.navigationItem.leftBarButtonItems?.count, 1)
    XCTAssertEqual(root.navigationItem.rightBarButtonItems?.count, 1)
  }

  @MainActor
  func testNativeTopBarVisibilityAndCoverage() throws {
    let (_, bar, nav) = try nativeTopBar()
    defer { restoreTopBar(bar, nav) }

    bar.reset(["token": 1, "title": "Scan History Logs", "back": true])

    bar.setVisible(true)
    XCTAssertFalse(nav.isNavigationBarHidden)
    XCTAssertEqual(nav.navigationBar.alpha, 1, accuracy: 0.001)

    bar.setCovered(true)
    XCTAssertEqual(nav.navigationBar.alpha, 0.45, accuracy: 0.001)
    XCTAssertFalse(nav.navigationBar.isUserInteractionEnabled)

    // The shell applies the dim itself in the same update as the tab bar; a
    // late report from the toolbar bridge must not restart it.
    bar.setCovered(true)
    XCTAssertEqual(nav.navigationBar.alpha, 0.45, accuracy: 0.001)

    bar.setCovered(false)
    XCTAssertEqual(nav.navigationBar.alpha, 1, accuracy: 0.001)
    XCTAssertTrue(nav.navigationBar.isUserInteractionEnabled)

    bar.setVisible(false)
    XCTAssertTrue(nav.isNavigationBarHidden)
  }

  @MainActor
  private func nativeTopBar() throws -> (
    NativeShellViewController, NativeTopBarCoordinator, UINavigationController
  ) {
    let window = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
    let shell = try XCTUnwrap(window.rootViewController as? NativeShellViewController)
    shell.loadViewIfNeeded()
    let bar = try XCTUnwrap(shell.topBar)
    // The suite shares one live Flutter app: let pending navigation from an
    // earlier test land before pinning the tab this test works on.
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    shell.nativeShell(setSelectedIndex: 0)
    // A tab change may animate; let it and the pending Flutter attachment
    // settle before the test starts touching the stack.
    shell.view.layoutIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    let nav = try XCTUnwrap(shell.selectedViewController as? UINavigationController)
    return (shell, bar, nav)
  }
  @MainActor
  private func restoreTopBar(
    _ bar: NativeTopBarCoordinator,
    _ nav: UINavigationController
  ) {
    bar.setCovered(false)
    bar.setVisible(true)
    waitForTransition(nav)
    nav.popToRootViewController(animated: false)
    waitForTransition(nav)
    bar.reset(["token": 0, "title": ""])
    nav.setNavigationBarHidden(false, animated: false)
  }

}
