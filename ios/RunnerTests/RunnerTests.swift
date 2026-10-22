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

      // UIKit selects the tapped tab itself; the shell hands the bars and the
      // Flutter surface over once it has, then tells Dart.
      XCTAssertTrue(try XCTUnwrap(delegate.tabBarController?(shell, shouldSelectTab: tab)))
      XCTAssertTrue(shell.selectedViewController === previouslySelected)

      // Both callback variants can fire; they must not start a second switch.
      XCTAssertTrue(try XCTUnwrap(delegate.tabBarController?(shell, shouldSelect: target)))
      let count = forwardedSelections.count

      shell.selectedIndex = index
      delegate.tabBarController?(shell, didSelectTab: tab, previousTab: nil)
      delegate.tabBarController?(shell, didSelect: target)
      XCTAssertEqual(shell.selectedIndex, index)
      XCTAssertTrue(flutter.parent === pageHost(in: target))
      XCTAssertEqual(forwardedSelections.count, count + 1)
      XCTAssertEqual(forwardedSelections.last, index)

      // Dart confirming the tab it was told about changes nothing.
      shell.nativeShell(setSelectedIndex: index)
      XCTAssertEqual(shell.selectedIndex, index)
      XCTAssertTrue(flutter.parent === pageHost(in: target))
      XCTAssertEqual(forwardedSelections.count, count + 1)

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
    XCTAssertTrue(shell.tabBarController(shell, shouldSelectTab: missingControllerTab))
    shell.selectedIndex = 2
    shell.tabBarController(shell, didSelect: settings)
    XCTAssertEqual(forwardedSelections.last, 2)
    XCTAssertTrue(flutter.parent === pageHost(in: settings))

    // Repeated taps on the active tab stay with UIKit's selection and reset
    // the branch in Flutter instead.
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
  func testNativeTopBarLargeTitleFollowsFlutterScroll() throws {
    let (_, bar, nav) = try nativeTopBar()
    defer { restoreTopBar(bar, nav) }
    let root = try XCTUnwrap(nav.viewControllers.first)

    // At the top Flutter draws the large title, so the bar shows none.
    bar.reset(
      ["token": 40, "title": "Settings", "largeTitle": true, "largeTitleHeight": 52,
       "largeTitleCollapseOffset": 8],
      scroll: ["offset": 0, "titleVisible": false])
    XCTAssertNil(root.navigationItem.title)
    // The bar animates the title view's own alpha, so the fade is on the view
    // inside it.
    let title = try XCTUnwrap(root.navigationItem.titleView?.subviews.first)
    XCTAssertEqual(title.alpha, 0, accuracy: 0.001)

    // The bar learns about Flutter's scroll from a proxy scroll view that
    // never takes touches away from Flutter.
    let proxy = try XCTUnwrap(root.contentScrollView(for: .top))
    XCTAssertFalse(proxy.isUserInteractionEnabled)
    XCTAssertFalse(proxy.scrollsToTop)
    root.view.layoutIfNeeded()
    XCTAssertEqual(
      proxy.contentOffset.y, -proxy.adjustedContentInset.top, accuracy: 0.5)

    // The bar stays clear until the top of the large title reaches it.
    bar.scroll(token: 40, ["offset": 6, "titleVisible": false], animated: false)
    XCTAssertEqual(
      proxy.contentOffset.y, -proxy.adjustedContentInset.top, accuracy: 0.5)

    bar.scroll(token: 40, ["offset": 30, "titleVisible": true], animated: false)
    XCTAssertEqual(title.alpha, 1, accuracy: 0.001)
    XCTAssertEqual(
      proxy.contentOffset.y, -proxy.adjustedContentInset.top + 22, accuracy: 0.5)

    // A stale page's report changes nothing.
    bar.scroll(token: 39, ["offset": 0, "titleVisible": false], animated: false)
    XCTAssertEqual(title.alpha, 1, accuracy: 0.001)

    // A page without a large title always shows its title.
    bar.reset(
      ["token": 41, "title": "Scan History Logs"],
      scroll: ["offset": 0, "titleVisible": true])
    XCTAssertEqual(root.navigationItem.title, "Scan History Logs")
    XCTAssertNil(root.navigationItem.titleView)
  }

  @MainActor
  func testNativeTopBarChipStripFollowsTheTopPage() throws {
    let (_, bar, nav) = try nativeTopBar()
    defer { restoreTopBar(bar, nav) }

    bar.reset(
      ["token": 50, "title": "Saved Cards", "largeTitle": true, "largeTitleHeight": 52,
       "chips": [["title": "Favorites", "selected": true],
                 ["title": "History", "selected": false]]],
      scroll: ["offset": 0, "titleVisible": false])
    let strip = try XCTUnwrap(bar.chipStrip)
    nav.view.layoutIfNeeded()
    XCTAssertFalse(strip.isHidden)
    XCTAssertEqual(strip.alpha, 1, accuracy: 0.001)
    XCTAssertEqual(buttons(in: strip).map { $0.configuration?.title }, ["Favorites", "History"])
    // Each chip is as wide as its own title, not stretched to a common width.
    let chipButtons = buttons(in: strip)
    let widths = chipButtons.map(\.frame.width)
    let fitting = chipButtons.map { $0.intrinsicContentSize.width }
    XCTAssertGreaterThan(widths[0], widths[1], "widths=\(widths) fitting=\(fitting)")
    for (width, fit) in zip(widths, fitting) {
      XCTAssertEqual(width, fit, accuracy: 1, "widths=\(widths) fitting=\(fitting)")
    }
    // Below the large title at the top, right under the bar once it collapsed.
    let barBottom = nav.navigationBar.frame.maxY
    XCTAssertEqual(strip.frame.minY, barBottom + 52, accuracy: 0.5)
    bar.scroll(token: 50, ["offset": 200, "titleVisible": true], animated: false)
    nav.view.layoutIfNeeded()
    XCTAssertEqual(strip.frame.minY, barBottom, accuracy: 0.5)

    // Covered by a Flutter modal it dims and stops taking touches.
    bar.setCovered(true, animated: false)
    XCTAssertEqual(strip.alpha, 0.45, accuracy: 0.001)
    XCTAssertFalse(strip.isUserInteractionEnabled)
    bar.setCovered(false, animated: false)

    // A page without chips hides it.
    bar.reset(["token": 51, "title": "Settings"], scroll: ["offset": 0, "titleVisible": true])
    XCTAssertTrue(strip.isHidden)
  }

  @MainActor
  func testTabSwitchHandsTheBarOverToTheIncomingPage() throws {
    let (shell, bar, nav) = try nativeTopBar()
    defer {
      shell.nativeShell(setSelectedIndex: 0)
      restoreTopBar(bar, nav)
    }
    bar.reset(["token": 60, "title": "Saved Cards", "actions": [["icon": "plus"]]])

    shell.nativeShell(setSelectedIndex: 2)
    let incoming = try XCTUnwrap(
      (shell.selectedViewController as? UINavigationController)?.topViewController)
    XCTAssertFalse(incoming === nav.topViewController)
    // Until Dart installs the incoming page, its bar shows what the outgoing
    // bar showed, so UIKit animates from there.
    XCTAssertEqual(incoming.navigationItem.title, "Saved Cards")
    XCTAssertEqual(incoming.navigationItem.rightBarButtonItems?.count, 1)

    bar.reset(["token": 61, "title": "Settings"])
    XCTAssertEqual(incoming.navigationItem.title, "Settings")
    XCTAssertEqual(incoming.navigationItem.rightBarButtonItems?.count ?? 0, 0)
  }

  @MainActor
  func testBarScrollsAwayBesideAVerticalBar() throws {
    let (shell, bar, nav) = try nativeTopBar()
    let original = bar.layout
    defer {
      bar.setLayout(original)
      restoreTopBar(bar, nav)
    }
    _ = shell
    var duo = NativeShellLayout()
    duo.verticalTabs = true
    bar.setLayout(duo)
    bar.reset(["token": 70, "title": "Settings"], scroll: ["offset": 0])
    nav.view.layoutIfNeeded()

    // Scrolling down past the bar takes it away; the safe area stays.
    let safeTop = nav.topViewController!.view.safeAreaInsets.top
    for offset in [40, 120, 200, 300] {
      bar.scroll(token: 70, ["offset": offset], animated: false)
    }
    XCTAssertNotEqual(nav.navigationBar.transform, .identity)
    XCTAssertEqual(nav.topViewController!.view.safeAreaInsets.top, safeTop)

    // Any scroll back up brings it back.
    for offset in [290, 270] {
      bar.scroll(token: 70, ["offset": offset], animated: false)
    }
    XCTAssertEqual(nav.navigationBar.transform, .identity)

    // Elsewhere the bar never moves.
    bar.setLayout(original)
    for offset in [300, 400, 600] {
      bar.scroll(token: 70, ["offset": offset], animated: false)
    }
    XCTAssertEqual(nav.navigationBar.transform, .identity)
  }

  func testShellLayoutFollowsSizeClasses() {
    func layout(_ width: UIUserInterfaceSizeClass, _ height: UIUserInterfaceSizeClass)
      -> NativeShellLayout
    {
      NativeShellLayout(
        traits: UITraitCollection { traits in
          traits.horizontalSizeClass = width
          traits.verticalSizeClass = height
        })
    }
    // iPhone portrait, or an iPad window narrow enough to put the tabs at the
    // bottom: large titles under a visible bar.
    let compact = layout(.compact, .regular)
    XCTAssertTrue(compact.largeTitles)
    XCTAssertFalse(compact.barHidden)
    XCTAssertFalse(compact.tabsInBar)
    // iPhone landscape: the app hides its bar.
    for width in [UIUserInterfaceSizeClass.compact, .regular] {
      let landscape = layout(width, .compact)
      XCTAssertTrue(landscape.barHidden)
      XCTAssertFalse(landscape.largeTitles)
      XCTAssertFalse(landscape.tabsInBar)
    }
    // iPad: the tabs share the bar, no large titles.
    let pad = layout(.regular, .regular)
    XCTAssertTrue(pad.tabsInBar)
    XCTAssertFalse(pad.largeTitles)
    XCTAssertFalse(pad.barHidden)
  }

  private func buttons(in view: UIView) -> [UIButton] {
    view.subviews.flatMap { ($0 as? UIButton).map { [$0] } ?? buttons(in: $0) }
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
