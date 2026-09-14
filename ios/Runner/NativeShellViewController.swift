import Flutter
import UIKit

final class NativeShellViewController: UITabBarController,
  UITabBarControllerDelegate, NativeShellBridgeDelegate
{
  private let flutterViewController: FlutterViewController
  private let bridge: NativeShellBridge
  private var flutterConstraints: [NSLayoutConstraint] = []
  private var actionButton: UIButton!
  private var actionButtonBottomToTabBar: NSLayoutConstraint!
  private var actionButtonBottomToSafeArea: NSLayoutConstraint!

  private var isTabBarVisible = true
  private var isDimmed = false
  private var currentActionConfig: [String: Any]? = nil

  init(flutterViewController: FlutterViewController, bridge: NativeShellBridge) {
    self.flutterViewController = flutterViewController
    self.bridge = bridge
    super.init(nibName: nil, bundle: nil)
    bridge.delegate = self
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    delegate = self

    let scan = makeSlot(title: String(localized: "Scan"), symbol: "wave.3.right")
    let cards = makeSlot(title: String(localized: "Cards"), symbol: "creditcard")
    let settings = makeSlot(title: String(localized: "Settings"), symbol: "gearshape")
    setViewControllers([scan, cards, settings], animated: false)
    selectedIndex = 0
    attachFlutter(to: scan)
    installActionButton()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncSafeAreaInsets()
  }

  private func makeSlot(title: String, symbol: String) -> UIViewController {
    let controller = UIViewController()
    controller.view.backgroundColor = .systemBackground
    controller.tabBarItem = UITabBarItem(
      title: title,
      image: UIImage(systemName: symbol),
      selectedImage: nil
    )
    return controller
  }

  private func attachFlutter(to target: UIViewController) {
    if flutterViewController.parent === target { return }
    NSLayoutConstraint.deactivate(flutterConstraints)

    if flutterViewController.parent != nil {
      flutterViewController.willMove(toParent: nil)
      flutterViewController.view.removeFromSuperview()
      flutterViewController.removeFromParent()
    }

    target.addChild(flutterViewController)
    let flutterView = flutterViewController.view!
    flutterView.translatesAutoresizingMaskIntoConstraints = false
    target.view.addSubview(flutterView)
    flutterConstraints = [
      flutterView.leadingAnchor.constraint(equalTo: target.view.leadingAnchor),
      flutterView.trailingAnchor.constraint(equalTo: target.view.trailingAnchor),
      flutterView.topAnchor.constraint(equalTo: target.view.topAnchor),
      flutterView.bottomAnchor.constraint(equalTo: target.view.bottomAnchor),
    ]
    NSLayoutConstraint.activate(flutterConstraints)
    flutterViewController.didMove(toParent: target)
    syncSafeAreaInsets()
  }

  private func installActionButton() {
    actionButton = makeGlassButton(symbol: "plus", accessibilityLabel: "")
    view.addSubview(actionButton)

    actionButtonBottomToTabBar = actionButton.bottomAnchor.constraint(
      equalTo: tabBar.topAnchor,
      constant: -16
    )
    actionButtonBottomToSafeArea = actionButton.bottomAnchor.constraint(
      equalTo: view.safeAreaLayoutGuide.bottomAnchor,
      constant: -16
    )

    NSLayoutConstraint.activate([
      actionButton.widthAnchor.constraint(equalToConstant: 56),
      actionButton.heightAnchor.constraint(equalToConstant: 56),
      actionButton.trailingAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.trailingAnchor,
        constant: -16
      ),
      actionButtonBottomToTabBar,
    ])

    updateActionVisibility()
  }

  private func makeGlassButton(symbol: String, accessibilityLabel: String) -> UIButton {
    let button = UIButton(type: .system)
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) {
      configuration = .glass()
      configuration.cornerStyle = .capsule
    } else {
      configuration = .plain()
      button.backgroundColor = .secondarySystemBackground
      button.layer.cornerRadius = 28
      button.layer.cornerCurve = .circular
      button.clipsToBounds = true
    }
    if #available(iOS 16.0, *) {
      configuration.indicator = .none
    }
    configuration.image = UIImage(systemName: symbol)
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: 21,
      weight: .semibold
    )
    button.configuration = configuration
    button.tintColor = .label
    button.accessibilityLabel = accessibilityLabel
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
  }

  /// The tab bar reserves part of the bottom safe area for the Flutter content it sits next to.
  /// Once the chrome goes away that reservation has to go with it, or pages keep leaving a band the
  /// height of a tab bar at the bottom.
  ///
  /// The adjustment belongs to the slot that hosts the Flutter view, not to the Flutter view
  /// controller itself: UIKit ignores a negative `additionalSafeAreaInsets` on that controller, so
  /// the value never reaches the engine and the content below the hidden chrome stays inset.
  private func syncSafeAreaInsets() {
    let adjustment = isTabBarVisible ? 0 : -tabBarHeightAboveSafeArea()
    let host = flutterViewController.parent

    for slot in viewControllers ?? [] {
      let bottom = slot === host ? adjustment : 0
      guard slot.additionalSafeAreaInsets.bottom != bottom else { continue }
      slot.additionalSafeAreaInsets = UIEdgeInsets(
        top: 0,
        left: 0,
        bottom: bottom,
        right: 0
      )
    }
  }

  /// How much height the tab bar takes up on top of the home-indicator strip, which is the part of
  /// the bottom safe area that has to disappear together with the chrome.
  private func tabBarHeightAboveSafeArea() -> CGFloat {
    max(0, tabBar.frame.height - view.safeAreaInsets.bottom)
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    guard let controllers = viewControllers,
      let index = controllers.firstIndex(of: viewController)
    else { return }
    attachFlutter(to: viewController)
    bridge.userSelected(index: index)
  }

  // MARK: - NativeShellBridgeDelegate

  func nativeShell(setTabs tabs: [[String: Any]]) {
    guard !tabs.isEmpty else { return }

    if viewControllers?.count != tabs.count {
      let controllers = tabs.map { tab -> UIViewController in
        let title = tab["label"] as? String ?? ""
        let symbol = tab["symbol"] as? String ?? "circle"
        return makeSlot(title: title, symbol: symbol)
      }
      setViewControllers(controllers, animated: false)
      if let first = controllers.first {
        attachFlutter(to: first)
      }
    }

    for (i, tab) in tabs.enumerated() {
      guard let controller = viewControllers?[i] else { continue }
      let title = tab["label"] as? String ?? ""
      let symbol = tab["symbol"] as? String ?? "circle"
      let hasBadge = tab["hasBadge"] as? Bool ?? false

      controller.tabBarItem.title = title
      controller.tabBarItem.image = UIImage(systemName: symbol)
      controller.tabBarItem.badgeValue = hasBadge ? "1" : nil
    }
  }

  func nativeShell(setSelectedIndex index: Int) {
    guard let controllers = viewControllers, controllers.indices.contains(index) else { return }
    if selectedIndex != index { selectedIndex = index }
    attachFlutter(to: controllers[index])
  }

  func nativeShell(setSettingsBadge visible: Bool) {
    guard let controllers = viewControllers, controllers.count > 2 else { return }
    controllers[2].tabBarItem.badgeValue = visible ? "1" : nil
  }

  func nativeShell(setChromeVisibility tabBarVisible: Bool, dimmed: Bool) {
    isTabBarVisible = tabBarVisible
    isDimmed = dimmed

    tabBar.isHidden = !tabBarVisible
    tabBar.isUserInteractionEnabled = tabBarVisible && !dimmed
    tabBar.alpha = dimmed ? 0.20 : 1.0

    actionButtonBottomToTabBar.isActive = tabBarVisible
    actionButtonBottomToSafeArea.isActive = !tabBarVisible

    syncSafeAreaInsets()
    updateActionVisibility()
    view.layoutIfNeeded()
  }

  func nativeShell(setScaffoldCovered covered: Bool, hideNativeChrome: Bool) {
    nativeShell(setChromeVisibility: !hideNativeChrome, dimmed: covered && !hideNativeChrome)
  }

  func nativeShell(setActionButton config: [String: Any]?) {
    currentActionConfig = config
    updateActionButton()
  }

  func nativeShell(setLocalizedStrings strings: [String: String]) {
    guard let controllers = viewControllers else { return }
    if let scan = strings["scan"], controllers.indices.contains(0) {
      controllers[0].tabBarItem.title = scan
    }
    if let cards = strings["cards"], controllers.indices.contains(1) {
      controllers[1].tabBarItem.title = cards
    }
    if let settings = strings["settings"], controllers.indices.contains(2) {
      controllers[2].tabBarItem.title = settings
    }
  }

  // MARK: - Action Button Helpers

  private func updateActionButton() {
    guard let config = currentActionConfig else {
      updateActionVisibility()
      return
    }

    let symbol = config["symbol"] as? String ?? "plus"
    let accessibilityLabel = config["label"] as? String ?? ""
    let items = config["items"] as? [[String: String]] ?? []
    let actionId = config["actionId"] as? String

    actionButton.accessibilityLabel = accessibilityLabel

    var buttonConfig = actionButton.configuration
    buttonConfig?.image = UIImage(systemName: symbol)
    actionButton.configuration = buttonConfig

    if !items.isEmpty {
      let actions = items.map { item -> UIAction in
        let id = item["id"] ?? ""
        let title = item["title"] ?? ""
        return UIAction(title: title) { [weak self] _ in
          self?.bridge.userRequested(action: id)
        }
      }
      actionButton.menu = UIMenu(title: "", children: actions)
      actionButton.showsMenuAsPrimaryAction = true
      actionButton.removeTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    } else if let _ = actionId {
      actionButton.menu = nil
      actionButton.showsMenuAsPrimaryAction = false
      actionButton.removeTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
      actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    }

    updateActionVisibility()
  }

  @objc private func actionButtonTapped() {
    if let actionId = currentActionConfig?["actionId"] as? String {
      bridge.userRequested(action: actionId)
    }
  }

  private func updateActionVisibility() {
    let hasConfig = currentActionConfig != nil
    actionButton?.isHidden = !hasConfig
    actionButton?.alpha = isDimmed ? 0.46 : 1.0
    actionButton?.isUserInteractionEnabled = hasConfig && !isDimmed
  }
}
