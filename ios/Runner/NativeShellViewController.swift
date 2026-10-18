import Flutter
import UIKit

final class NativeShellViewController: UITabBarController,
  UITabBarControllerDelegate, NativeShellBridgeDelegate
{
  private let flutterViewController: FlutterViewController
  private let bridge: NativeShellBridge
  private var flutterConstraints: [NSLayoutConstraint] = []
  private var actionButton: UIButton!
  private var actionButtonBottomToSafeArea: NSLayoutConstraint!
  private var isApplyingFlutterSelection = false
  // Deduplicates legacy/modern callbacks from the same physical tap.
  private var pendingUserSelectionIndex: Int?

  private var isTabBarVisible = true
  private var isDimmed = false
  /// The bar views dimmed while a Flutter modal covers the shell. On iPhone
  /// Duo the vertical bar is not the `tabBar` property view, so the views are
  /// discovered from the window instead of assuming one.
  private var dimmedBarViews: [UIView] = []

  /// Same duration the plugin uses to fade its own chrome, so the tab bar and
  /// the toolbar return together instead of the bar snapping back.
  private static let chromeFadeDuration: TimeInterval = 0.22
  private var chromeFadeToken = 0
  private var isChromeFading = false
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
    syncActionButtonPosition()
    if isDimmed, !isChromeFading { applyChromeDimming(animated: false) }
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
      actionButtonBottomToSafeArea,
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

  /// iOS 17 keeps the legacy bottom bar's safe-area reservation when it is
  /// hidden directly. Apply that workaround only to the slot hosting Flutter.
  private func syncSafeAreaInsets() {
    let adjustment: CGFloat
    if #available(iOS 18.0, *) {
      // setTabBarHidden updates the content safe area for both top and bottom tabs.
      adjustment = 0
    } else {
      adjustment = isTabBarVisible ? 0 : -bottomTabBarOverlap()
    }
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

  /// iPad's top tab bar may not be in this view hierarchy. Never constrain our
  /// button to it; measure only a bottom bar that actually overlaps our safe area.
  private func bottomTabBarOverlap() -> CGFloat {
    guard tabBar.isDescendant(of: view) else { return 0 }
    let barFrame = tabBar.convert(tabBar.bounds, to: view)
    let safeBottom = view.safeAreaLayoutGuide.layoutFrame.maxY
    guard barFrame.maxY >= safeBottom else { return 0 }
    return max(0, safeBottom - barFrame.minY)
  }

  private func syncActionButtonPosition() {
    let overlap = isTabBarVisible ? bottomTabBarOverlap() : 0
    actionButtonBottomToSafeArea?.constant = -16 - overlap
  }

  /// UIKit must not select and hide the current Flutter host before Dart
  /// navigates. Instead let Flutter own the selection; the Dart route change
  /// will call nativeShell(setSelectedIndex:) to commit the UIKit tab.
  private func requestFlutterSelection(index: Int) {
    guard !isApplyingFlutterSelection else { return }
    // iOS 18+ may invoke both legacy and UITab selection callbacks.
    guard pendingUserSelectionIndex != index else { return }
    pendingUserSelectionIndex = index
    NSLog("[NativeShell] user requested tab index=%d", index)
    bridge.userSelected(index: index)
    // The matching callbacks run in one UI event. Later taps, including a
    // repeat tap on the current tab, must be handled independently.
    DispatchQueue.main.async { [weak self] in
      if self?.pendingUserSelectionIndex == index {
        self?.pendingUserSelectionIndex = nil
      }
    }
  }

  @available(iOS 18.0, *)
  private func indexForTab(_ tab: UITab, in controller: UITabBarController) -> Int? {
    // UITab.viewController is optional and can be unavailable before selection.
    if let target = tab.viewController,
      let index = controller.viewControllers?.firstIndex(where: { $0 === target })
    {
      return index
    }
    // With UIKit-managed tabs we can still resolve the tab by identity.
    if let index = controller.tabs.firstIndex(where: { $0 === tab }),
      controller.viewControllers?.indices.contains(index) == true
    {
      return index
    }
    // Some UIKit versions supply a tab without an instantiated controller.
    // Our three shell titles are distinct, even if UIKit's tabs array is empty.
    guard !tab.title.isEmpty else { return nil }
    return controller.viewControllers?.firstIndex {
      $0.tabBarItem.title == tab.title
    }
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    shouldSelect viewController: UIViewController
  ) -> Bool {
    guard !isApplyingFlutterSelection else { return true }
    guard let index = tabBarController.viewControllers?.firstIndex(
      where: { $0 === viewController }
    ) else { return false }
    requestFlutterSelection(index: index)
    // Keep Flutter visible in the old slot until Dart commits the new route.
    return false
  }

  @available(iOS 18.0, *)
  func tabBarController(
    _ tabBarController: UITabBarController,
    shouldSelectTab tab: UITab
  ) -> Bool {
    guard !isApplyingFlutterSelection else { return true }
    guard let index = indexForTab(tab, in: tabBarController) else {
      NSLog("[NativeShell] Unknown UITab: %@", tab.identifier)
      return false
    }
    requestFlutterSelection(index: index)
    return false
  }

  @available(iOS 18.0, *)
  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelectTab selectedTab: UITab,
    previousTab: UITab?
  ) {
    // Fallback for systems that deliver selection despite shouldSelect=false.
    guard !isApplyingFlutterSelection,
      let index = indexForTab(selectedTab, in: tabBarController) else { return }
    requestFlutterSelection(index: index)
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    guard !isApplyingFlutterSelection,
      let index = tabBarController.viewControllers?.firstIndex(
        where: { $0 === viewController }
      ) else { return }
    requestFlutterSelection(index: index)
  }

  // MARK: - NativeShellBridgeDelegate

  func nativeShell(setTabs tabs: [[String: Any]]) {
    guard !tabs.isEmpty else { return }

    // The tab bar follows the app's accent colour, dynamic colour included,
    // instead of UIKit's default system blue.
    if let argb = (tabs.first?["tint"] as? NSNumber)?.uint32Value {
      let alpha = CGFloat((argb >> 24) & 0xFF) / 255.0
      let red = CGFloat((argb >> 16) & 0xFF) / 255.0
      let green = CGFloat((argb >> 8) & 0xFF) / 255.0
      let blue = CGFloat(argb & 0xFF) / 255.0
      let accent = UIColor(red: red, green: green, blue: blue, alpha: alpha)
      tabBar.tintColor = accent
      view.tintColor = accent
    }

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
    // Dart-driven selection is the only place that commits the UIKit tab.
    pendingUserSelectionIndex = nil
    NSLog("[NativeShell] Dart committed selected index=%d", index)
    // Older UIKit needs Flutter installed before forwarding tab appearance.
    if #unavailable(iOS 27.0) {
      attachFlutter(to: controllers[index])
    }
    if selectedIndex != index {
      isApplyingFlutterSelection = true
      defer { isApplyingFlutterSelection = false }
      selectedIndex = index
    }
    // iOS 27 needs the visible slot or it can leave Flutter's surface paused.
    attachFlutter(to: controllers[index])
  }

  func nativeShell(setSettingsBadge visible: Bool) {
    guard let controllers = viewControllers, controllers.count > 2 else { return }
    controllers[2].tabBarItem.badgeValue = visible ? "1" : nil
  }

  func nativeShell(setChromeVisibility tabBarVisible: Bool, dimmed: Bool) {
    isTabBarVisible = tabBarVisible
    isDimmed = dimmed

    if #available(iOS 18.0, *) {
      setTabBarHidden(!tabBarVisible, animated: false)
    } else {
      tabBar.isHidden = !tabBarVisible
    }

    applyChromeDimming(animated: true)

    syncSafeAreaInsets()
    syncActionButtonPosition()
    updateActionVisibility()
    view.layoutIfNeeded()
  }

  /// Dims and disarms the tab bar while a Flutter modal covers the shell.
  ///
  /// The bottom bar is `tabBar`; the iPhone Duo vertical bar is a different
  /// system view, so every tab bar/sidebar view in the window is handled the
  /// same way. The state is re-applied after layout because the system lays
  /// its bar out again on rotation and when the device folds.
  private func applyChromeDimming(animated: Bool) {
    let bars: [UIView]
    let targetAlpha: CGFloat
    if isDimmed {
      bars = chromeBarViews()
      dimmedBarViews = bars
      targetAlpha = 0.45
      for bar in bars { bar.isUserInteractionEnabled = false }
    } else {
      bars = dimmedBarViews
      dimmedBarViews = []
      targetAlpha = 1.0
      for bar in bars { bar.isUserInteractionEnabled = isTabBarVisible }
    }
    guard !bars.isEmpty else { return }

    let update = {
      for bar in bars { bar.alpha = targetAlpha }
    }
    guard animated else {
      update()
      return
    }

    chromeFadeToken += 1
    let token = chromeFadeToken
    isChromeFading = true
    // Same fade the plugin runs on its own chrome, so both return together.
    UIView.animate(
      withDuration: Self.chromeFadeDuration,
      delay: 0,
      options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
      animations: update
    ) { [weak self] _ in
      guard let self, self.chromeFadeToken == token else { return }
      self.isChromeFading = false
      // Catch bars the system recreated while the fade ran.
      self.applyChromeDimming(animated: false)
    }
  }

  /// The tab bar views of the current presentation: the controller's own bar
  /// and, on iPhone Duo, the vertical bar/sidebar the system draws instead.
  private func chromeBarViews() -> [UIView] {
    var result: [UIView] = []
    var seen = Set<ObjectIdentifier>()

    func add(_ view: UIView) {
      let id = ObjectIdentifier(view)
      guard !seen.contains(id) else { return }
      seen.insert(id)
      result.append(view)
    }

    if tabBar.window != nil, tabBar.superview != nil {
      add(tabBar)
    }

    func visit(_ node: UIView) {
      if node !== tabBar, node.window != nil {
        let name = String(describing: type(of: node))
        if name.contains("TabBar") || name.contains("Sidebar") {
          let frame = node.convert(node.bounds, to: view)
          if frame.width > 1, frame.height > 1, frame.intersects(view.bounds) {
            add(node)
          }
        }
      }
      for sub in node.subviews { visit(sub) }
    }

    if let window = view.window { visit(window) }

    // Keep only the outermost matching view of each hierarchy: dimming both a
    // container and the bar inside it would multiply their alphas and make
    // one presentation fade twice as much as the other.
    return result.filter { candidate in
      !result.contains {
        $0 !== candidate && candidate.isDescendant(of: $0)
      }
    }
  }

  func nativeShell(setActionButton config: [String: Any]?) {
    currentActionConfig = config
    updateActionButton()
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
