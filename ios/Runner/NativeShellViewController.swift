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
  fileprivate static let chromeFadeDuration: TimeInterval = 0.22
  private var chromeFadeToken = 0
  private var isChromeFading = false
  private var currentActionConfig: [String: Any]? = nil
  private(set) var topBar: NativeTopBarCoordinator?

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
    // Flutter draws every page and shows it through the transparent tab
    // content, so the shell itself has nothing to paint.
    view.backgroundColor = .clear

    let scan = makeSlot(title: String(localized: "Scan"), symbol: "wave.3.right")
    let cards = makeSlot(title: String(localized: "Cards"), symbol: "creditcard")
    let settings = makeSlot(title: String(localized: "Settings"), symbol: "gearshape")
    setViewControllers([scan, cards, settings], animated: false)
    selectedIndex = 0
    attachFlutter(to: scan)
    installActionButton()
    topBar = NativeTopBarCoordinator(
      shell: self,
      messenger: bridge.messenger
    )
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncSafeAreaInsets()
    syncActionButtonPosition()
    if isDimmed {
      if !isChromeFading { applyChromeDimming(animated: false) }
    } else {
      // Keeps a bar recreated by the system tappable while no modal covers it.
      for bar in chromeBarViews() {
        bar.isUserInteractionEnabled = isTabBarVisible
      }
    }
  }

  /// A turn between the two landscape poses changes the scene orientation but
  /// not its size, and UIKit only exposes the new value while the transition
  /// runs. Publish it once the rotation settles so Dart never keeps the scan
  /// target on the previous edge.
  override func viewWillTransition(
    to size: CGSize,
    with coordinator: any UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: nil) { _ in
      (UIApplication.shared.delegate as? AppDelegate)?
        .deviceOrientationBridge.deviceTopOnRightChanged()
    }
  }

  /// The scene may report portrait during the first Flutter frame of a launch
  /// that is already landscape; re-publish once the shell is on screen.
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    (UIApplication.shared.delegate as? AppDelegate)?
      .deviceOrientationBridge.deviceTopOnRightChanged()
  }

  /// One tab, as a real navigation controller.
  ///
  /// The navigation controller has to be the tab's view controller, not a
  /// view we lay out ourselves: only then does UIKit read its navigation
  /// item, which is what makes the system draw the bar horizontally on
  /// iPhone and move the same items into the vertical bar on iPhone Duo.
  private func makeSlot(title: String, symbol: String) -> UINavigationController {
    let content = UIViewController()
    content.view.backgroundColor = .clear

    let nav = UINavigationController(rootViewController: content)
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    appearance.backgroundColor = .clear
    appearance.shadowColor = .clear
    nav.navigationBar.standardAppearance = appearance
    nav.navigationBar.scrollEdgeAppearance = appearance
    nav.navigationBar.compactAppearance = appearance
    nav.navigationBar.compactScrollEdgeAppearance = appearance
    nav.navigationBar.prefersLargeTitles = false
    nav.navigationBar.tintColor = .label
    // Back swipes are Flutter's: it reports the pop, and the bar plays its own
    // transition. UIKit's interactive pop would move the shared surface.
    nav.interactivePopGestureRecognizer?.isEnabled = false
    nav.view.backgroundColor = .clear
    nav.tabBarItem = UITabBarItem(
      title: title,
      image: UIImage(systemName: symbol),
      selectedImage: nil
    )
    return nav
  }

  /// Installs the Flutter view in the selected tab.
  ///
  /// Flutter is a child of the page on top of the stack. A page transition
  /// moves it to the incoming page before the switch, and the custom animator
  /// keeps that page at its final frame, so the surface never moves or leaves
  /// the window while the bar plays UIKit's own item transition.
  private func attachFlutter(to target: UINavigationController) {
    // Follow whatever page the tab is showing; if the bridge then resets the
    // stack, reset moves the surface back to the root before clearing.
    guard let host = target.topViewController else { return }
    moveFlutter(to: host)
  }

  /// Reparents the shared Flutter surface under [host], filling its view.
  func moveFlutter(to host: UIViewController) {
    if flutterViewController.parent === host,
      flutterViewController.view.superview === host.view
    {
      return
    }
    NSLayoutConstraint.deactivate(flutterConstraints)

    flutterViewController.willMove(toParent: nil)
    flutterViewController.view.removeFromSuperview()
    flutterViewController.removeFromParent()

    host.addChild(flutterViewController)
    let flutterView = flutterViewController.view!
    flutterView.translatesAutoresizingMaskIntoConstraints = false
    host.view.insertSubview(flutterView, at: 0)
    flutterConstraints = [
      flutterView.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
      flutterView.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
      flutterView.topAnchor.constraint(equalTo: host.view.topAnchor),
      flutterView.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
    ]
    NSLayoutConstraint.activate(flutterConstraints)
    flutterViewController.didMove(toParent: host)
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
  /// hidden directly. Apply that workaround only to the tab hosting Flutter.
  private func syncSafeAreaInsets() {
    let adjustment: CGFloat
    if #available(iOS 18.0, *) {
      // setTabBarHidden updates the content safe area for both top and bottom tabs.
      adjustment = 0
    } else {
      adjustment = isTabBarVisible ? 0 : -bottomTabBarOverlap()
    }
    let host = flutterViewControllerHost

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

  /// The tab that owns Flutter: the page's navigation controller.
  private var flutterViewControllerHost: UIViewController? {
    flutterViewController.parent?.parent
  }

  /// The Flutter surface every tab shares. Its parent is the selected tab's
  /// navigation controller; exposed so tests can follow it across tabs.
  var flutterSurface: FlutterViewController { flutterViewController }

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
      let controllers = tabs.map { tab -> UINavigationController in
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
    // Older UIKit needs Flutter installed before forwarding tab appearance.
    if #unavailable(iOS 27.0) {
      if let nav = controllers[index] as? UINavigationController {
        attachFlutter(to: nav)
      }
    }
    if selectedIndex != index {
      isApplyingFlutterSelection = true
      defer { isApplyingFlutterSelection = false }
      selectedIndex = index
    }
    // iOS 27 needs the visible slot or it can leave Flutter's surface paused.
    if let nav = controllers[index] as? UINavigationController {
      attachFlutter(to: nav)
    }
  }

  func nativeShell(setSettingsBadge visible: Bool) {
    guard let controllers = viewControllers, controllers.count > 2 else { return }
    controllers[2].tabBarItem.badgeValue = visible ? "1" : nil
  }

  func nativeShell(setChromeVisibility tabBarVisible: Bool, dimmed: Bool) {
    isTabBarVisible = tabBarVisible
    isDimmed = dimmed

    // The top bar dims here, in the same update that dims the tab bar, so the
    // two bars start together. Letting the Dart toolbar bridge drive it
    // separately made the top bar arrive ~50ms late: that bridge runs after
    // the registry's post-frame pass.
    topBar?.setCovered(dimmed)

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
    let current = chromeBarViews()
    let bars: [UIView]
    let targetAlpha: CGFloat
    if isDimmed {
      bars = current
      dimmedBarViews = current
      targetAlpha = 0.45
      for bar in bars { bar.isUserInteractionEnabled = false }
    } else {
      // Restore the views dimmed earlier *and* whatever is on screen now. A
      // bar the system recreated while dimmed, or one dimmed while its page
      // was covered, would otherwise stay inert after the modal closes.
      var targets = current
      for bar in dimmedBarViews where !targets.contains(where: { $0 === bar }) {
        targets.append(bar)
      }
      dimmedBarViews = []
      bars = targets
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


// MARK: - Native top bar

/// Drives the system navigation bar of the selected tab from the page stack
/// Dart publishes.
///
/// It does not draw a bar of its own: each tab is a real
/// `UINavigationController`, so UIKit owns the bar and decides where it goes —
/// horizontally at the top on iPhone, inside the vertical bar on iPhone Duo.
/// This class only installs navigation items and pushes the transparent
/// placeholder pages that make UIKit play its own push/pop transition.
final class NativeTopBarCoordinator: NSObject, UINavigationControllerDelegate {
  private static let channelName = "moe.neri.hinatago/native_top_bar"

  private weak var shell: NativeShellViewController?
  private let channel: FlutterMethodChannel
  private var isCovered = false

  init(shell: NativeShellViewController, messenger: FlutterBinaryMessenger) {
    self.shell = shell
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    super.init()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      self.handle(call, result: result)
    }
  }

  /// The navigation controller of the tab Flutter is showing.
  private var navigationController: UINavigationController? {
    guard let shell else { return nil }
    return shell.selectedViewController as? UINavigationController
  }

  /// The content controller Flutter is attached to. Pushing placeholder pages
  /// above it moves no Flutter content; the transition happens in the bar.
  private var rootController: UIViewController? {
    navigationController?.viewControllers.first
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "reset":
      guard let args = call.arguments as? [String: Any],
        let map = args["item"] as? [String: Any]
      else {
        return result(FlutterError(code: "bad_args", message: nil, details: nil))
      }
      reset(map)
      if let visible = args["visible"] as? Bool {
        setVisible(visible)
      }
      result(nil)
    case "push":
      guard let args = call.arguments as? [String: Any],
        let map = args["item"] as? [String: Any]
      else {
        return result(FlutterError(code: "bad_args", message: nil, details: nil))
      }
      push(map)
      result(nil)
    case "pop":
      if let nav = navigationController, nav.viewControllers.count > 1 {
        nav.popViewController(animated: true)
      }
      result(nil)
    case "update":
      guard let args = call.arguments as? [String: Any],
        let map = args["item"] as? [String: Any],
        let token = map["token"] as? Int,
        let top = navigationController?.topViewController as? NativeTopBarPageController,
        top.token == token
      else {
        return result(FlutterError(code: "bad_args", message: nil, details: nil))
      }
      configureItem(map, on: top.navigationItem)
      result(nil)
    case "setVisible":
      if let args = call.arguments as? [String: Any],
        let visible = args["visible"] as? Bool {
        setVisible(visible)
      }
      result(nil)
    case "setCovered":
      if let args = call.arguments as? [String: Any],
        let covered = args["covered"] as? Bool {
        setCovered(covered)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func reset(_ map: [String: Any]) {
    guard let nav = navigationController, let root = rootController else { return }
    nav.delegate = self

    // A tab switch starts a new stack; clear whatever the previous page left
    // on this controller before installing the new item. Flutter moves back
    // to the root first, or clearing the stack would take the surface with the
    // page UIKit removes.
    if nav.viewControllers.count > 1 {
      shell?.moveFlutter(to: root)
      nav.setViewControllers([root], animated: false)
    }

    configureItem(map, on: root.navigationItem)
  }

  func push(_ map: [String: Any]) {
    guard let nav = navigationController else { return }
    nav.delegate = self
    let page = makePage(map)
    nav.pushViewController(page, animated: true)
  }

  private func makePage(_ map: [String: Any]) -> NativeTopBarPageController {
    let page = NativeTopBarPageController()
    page.token = map["token"] as? Int ?? 0
    configureItem(map, on: page.navigationItem)
    return page
  }

  /// Hides or shows the bar. UIKit adds or removes the matching safe area for
  /// us, so Flutter content follows without a manual inset.
  func setVisible(_ visible: Bool) {
    guard let nav = navigationController else { return }
    nav.setNavigationBarHidden(!visible, animated: false)
  }

  func setCovered(_ covered: Bool, animated: Bool = true) {
    guard covered != isCovered else { return }
    isCovered = covered
    applyCoveredAppearance(animated: animated)
  }

  private func applyCoveredAppearance(animated: Bool = false) {
    let barAlpha: CGFloat = isCovered ? 0.45 : 1
    guard let nav = navigationController else { return }
    nav.navigationBar.isUserInteractionEnabled = !isCovered

    guard animated else {
      nav.navigationBar.alpha = barAlpha
      return
    }

    // 150ms is the Flutter dialog barrier's duration, so the strip dims in
    // step with the rest of the screen instead of lagging behind it.
    UIView.animate(
      withDuration: isCovered ? 0.15 : NativeShellViewController.chromeFadeDuration,
      delay: 0,
      options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
    ) {
      nav.navigationBar.alpha = barAlpha
    }
  }

  private func configureItem(
    _ map: [String: Any],
    on item: UINavigationItem
  ) {
    let token = map["token"] as? Int ?? 0
    let title = map["title"] as? String
    if map["logo"] as? Bool == true, let title, !title.isEmpty {
      item.title = nil
      item.titleView = Self.makeLogoTitleView(title: title)
    } else {
      item.titleView = nil
      item.title = title
    }
    item.hidesBackButton = true
    if #available(iOS 27.1, *) {
      // The bar decides the axis; ask for the vertical one when both exist.
      item.verticalBarCompressionBehavior = .automatic
    }

    var leading: [UIBarButtonItem] = []
    if map["back"] as? Bool == true {
      let back = UIBarButtonItem(
        image: UIImage(systemName: "chevron.left"),
        primaryAction: UIAction { [weak self] _ in
          self?.channel.invokeMethod("onBack", arguments: ["token": token])
        }
      )
      back.accessibilityLabel = "Back"
      leading.append(back)
    } else if map["leading"] as? String == "close" {
      let close = UIBarButtonItem(
        image: UIImage(systemName: "xmark"),
        primaryAction: UIAction { [weak self] _ in
          self?.channel.invokeMethod("onLeading", arguments: ["token": token])
        }
      )
      close.accessibilityLabel = "Close"
      leading.append(close)
    }
    item.leftBarButtonItems = leading

    if let tint = map["tint"] as? NSNumber {
      let color = Self.colorFromARGB(tint.intValue)
      item.leftBarButtonItems?.forEach { $0.tintColor = color }
    }

    var trailing: [UIBarButtonItem] = []
    if let actions = map["actions"] as? [[String: Any]] {
      for (index, action) in actions.enumerated() {
        let button: UIBarButtonItem?

        if let entries = action["menu"] as? [[String: Any]] {
          let menu = makeMenu(entries, actionIndex: index, token: token)
          if let icon = action["icon"] as? String {
            button = UIBarButtonItem(
              image: UIImage(systemName: icon) ?? UIImage(named: icon),
              menu: menu
            )
          } else {
            button = UIBarButtonItem(title: action["title"] as? String, menu: menu)
          }
        } else if let icon = action["icon"] as? String {
          button = UIBarButtonItem(
            image: UIImage(systemName: icon) ?? UIImage(named: icon),
            primaryAction: UIAction { [weak self] _ in
              self?.channel.invokeMethod(
                "onAction",
                arguments: ["token": token, "index": index]
              )
            }
          )
        } else if let title = action["title"] as? String {
          button = UIBarButtonItem(
            title: title,
            primaryAction: UIAction { [weak self] _ in
              self?.channel.invokeMethod(
                "onAction",
                arguments: ["token": token, "index": index]
              )
            }
          )
        } else {
          button = nil
        }

        if let button {
          if let label = action["label"] as? String {
            button.accessibilityLabel = label
          }
          if action["prominent"] as? Bool == true, #available(iOS 26.0, *) {
            button.style = .prominent
          }
          if let tint = action["tint"] as? NSNumber {
            button.tintColor = Self.colorFromARGB(tint.intValue)
          }
          trailing.append(button)

          if let spacerAfter = action["spacerAfter"] as? Int, spacerAfter == 1 {
            if #available(iOS 16.0, *) {
              trailing.append(.fixedSpace(12))
            }
          }
        }
      }
    }
    item.rightBarButtonItems = trailing.reversed()
  }

  private func makeMenu(
    _ entries: [[String: Any]],
    actionIndex: Int,
    token: Int
  ) -> UIMenu {
    var groups: [[UIMenuElement]] = []
    var current: [UIMenuElement] = []

    for (itemIndex, entry) in entries.enumerated() {
      if entry["divider"] as? Bool == true {
        if !current.isEmpty {
          groups.append(current)
          current = []
        }
        continue
      }

      let title = entry["title"] as? String ?? ""
      let image = (entry["icon"] as? String).flatMap {
        UIImage(systemName: $0) ?? UIImage(named: $0)
      }
      var attributes: UIMenuElement.Attributes = []
      if entry["enabled"] as? Bool == false {
        attributes.insert(.disabled)
      }
      if entry["destructive"] as? Bool == true {
        attributes.insert(.destructive)
      }

      let action = UIAction(
        title: title,
        subtitle: entry["subtitle"] as? String,
        image: image,
        attributes: attributes
      ) { [weak self] _ in
        self?.channel.invokeMethod(
          "onMenu",
          arguments: ["token": token, "action": actionIndex, "item": itemIndex]
        )
      }
      current.append(action)
    }
    if !current.isEmpty {
      groups.append(current)
    }

    return UIMenu(
      title: "",
      children: groups.map { UIMenu(title: "", options: .displayInline, children: $0) }
    )
  }

  private static func makeLogoTitleView(title: String) -> UIView {
    let imageView = UIImageView(
      image: UIImage(named: "HinataLogo")?.withRenderingMode(.alwaysTemplate)
    )
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .label
    imageView.isAccessibilityElement = false
    imageView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      imageView.widthAnchor.constraint(equalToConstant: 22),
      imageView.heightAnchor.constraint(equalToConstant: 22),
    ])

    let label = UILabel()
    label.text = title
    label.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
      for: .systemFont(ofSize: 17, weight: .semibold)
    )
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .label

    let stack = UIStackView(arrangedSubviews: [imageView, label])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 6
    return stack
  }

  private static func colorFromARGB(_ argb: Int) -> UIColor {
    let a = CGFloat((argb >> 24) & 0xFF) / 255.0
    let r = CGFloat((argb >> 16) & 0xFF) / 255.0
    let g = CGFloat((argb >> 8) & 0xFF) / 255.0
    let b = CGFloat(argb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }

  /// UIKit gives a pushed page a rounded card and a drop shadow. The card
  /// holds no content — the visible page is Flutter's — and it would cut
  /// across the bar as a stray edge, so the content transition is suppressed
  /// while the bar keeps animating its items. Flutter moves to the incoming
  /// page first, so the surface stays in the window throughout.
  func navigationController(
    _ navigationController: UINavigationController,
    animationControllerFor operation: UINavigationController.Operation,
    from fromVC: UIViewController,
    to toVC: UIViewController
  ) -> (any UIViewControllerAnimatedTransitioning)? {
    NativeTopBarContentAnimator { [weak self] host in
      self?.shell?.moveFlutter(to: host)
    }
  }
}

private final class NativeTopBarContentAnimator: NSObject,
  UIViewControllerAnimatedTransitioning
{
  private let duration: TimeInterval = 0.35
  private let prepare: (UIViewController) -> Void

  init(prepare: @escaping (UIViewController) -> Void) {
    self.prepare = prepare
  }

  func transitionDuration(
    using transitionContext: (any UIViewControllerContextTransitioning)?
  ) -> TimeInterval {
    duration
  }

  func animateTransition(
    using transitionContext: any UIViewControllerContextTransitioning
  ) {
    guard
      let toViewController = transitionContext.viewController(forKey: .to),
      let toView = transitionContext.view(forKey: .to)
    else {
      transitionContext.completeTransition(false)
      return
    }

    // The incoming page holds Flutter and stays exactly where the old one
    // was: only the bar animates.
    toView.frame = transitionContext.finalFrame(for: toViewController)
    transitionContext.containerView.addSubview(toView)
    prepare(toViewController)

    let fromView = transitionContext.view(forKey: .from)
    let fromWasHidden = fromView?.isHidden ?? false
    fromView?.isHidden = true

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
      fromView?.isHidden = fromWasHidden
      self?.finish(transitionContext)
    }
  }

  private func finish(_ transitionContext: any UIViewControllerContextTransitioning) {
    transitionContext.completeTransition(
      !transitionContext.transitionWasCancelled
    )
  }
}

private final class NativeTopBarPageController: UIViewController {
  var token: Int = 0

  override func loadView() {
    let view = UIView()
    view.backgroundColor = .clear
    view.isOpaque = false
    self.view = view
  }
}
