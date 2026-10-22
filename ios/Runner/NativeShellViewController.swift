import Flutter
import ObjectiveC
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
    FlutterSemanticsEdgeEffects.disable()
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
    installLaunchCover()
    topBar = NativeTopBarCoordinator(
      shell: self,
      messenger: bridge.messenger
    )
    syncLayout()
    var traits: [UITrait] = [UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]
    if #available(iOS 27.1, *) {
      traits += UITraitCollection.systemTraitsAffectingVerticalBarEdge
    }
    registerForTraitChanges(traits) { (self: Self, _: UITraitCollection) in
      self.syncLayout()
    }
  }

  /// Lays the chrome out for the window's current traits.
  private func syncLayout() {
    topBar?.setLayout(NativeShellLayout(traits: traitCollection))
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
    // The bar's title margin is only known once it is laid out.
    topBar?.sendLayout()
    (UIApplication.shared.delegate as? AppDelegate)?
      .deviceOrientationBridge.deviceTopOnRightChanged()
  }

  /// The launch screen, kept over the whole shell until Flutter has drawn its
  /// first frame.
  ///
  /// The system takes its own launch screen down as soon as this shell
  /// appears, while Flutter is still building the first page. Without the
  /// cover the empty, transparent shell would show for that moment: a black
  /// screen with only the native tab bar on it.
  private var launchCover: UIView?

  private func installLaunchCover() {
    guard !flutterViewController.isDisplayingFlutterUI,
      let name = Bundle.main.object(forInfoDictionaryKey: "UILaunchStoryboardName") as? String,
      let cover = UIStoryboard(name: name, bundle: nil).instantiateInitialViewController()?.view
    else { return }
    cover.frame = view.bounds
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(cover)
    launchCover = cover
    flutterViewController.setFlutterViewDidRenderCallback { [weak self] in
      self?.removeLaunchCover()
    }
    // Never leave the app hidden should the callback not come.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.removeLaunchCover()
    }
  }

  private func removeLaunchCover() {
    guard let cover = launchCover else { return }
    launchCover = nil
    // Flutter's own splash screen fades out the same way.
    UIView.animate(
      withDuration: 0.2,
      animations: { cover.alpha = 0 },
      completion: { _ in cover.removeFromSuperview() }
    )
  }

  /// One tab, as a real navigation controller.
  ///
  /// The navigation controller has to be the tab's view controller, not a
  /// view we lay out ourselves: only then does UIKit read its navigation
  /// item, which is what makes the system draw the bar horizontally on
  /// iPhone and move the same items into the vertical bar on iPhone Duo.
  private func makeSlot(title: String, symbol: String) -> UINavigationController {
    let content = NativeTopBarPageController()

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

  /// A switch from the selected tab to the tab at [index].
  private struct TabSwitch {
    let index: Int
    let forward: Bool
    let outgoing: UINavigationController?
  }

  /// A tab the user tapped, between UIKit asking whether it may select it and
  /// reporting that it did.
  private var userSwitch: TabSwitch?

  /// A tap on another tab switches right away, as in any system app: UIKit
  /// plays its own selection, the bars change over, and Flutter is told once
  /// the tab is selected. Its page transition follows a frame later, which
  /// reads as one switch; making UIKit wait for that frame stalled the tab bar.
  ///
  /// A tap on the selected tab is Flutter's alone: UIKit would pop the
  /// placeholder pages, while Flutter pops its branch and the bar follows.
  private func shouldSelectTab(at index: Int) -> Bool {
    guard !isApplyingFlutterSelection else { return true }
    // iOS 18+ may ask through both the legacy and the UITab callback.
    if let pending = userSwitch { return pending.index == index }
    guard index != selectedIndex else {
      requestFlutterSelection(index: index)
      return false
    }
    userSwitch = beginSwitch(to: index)
    // Should UIKit select without reporting it, finish once it has.
    DispatchQueue.main.async { [weak self] in self?.finishUserSwitch() }
    return true
  }

  private func finishUserSwitch() {
    guard let pending = userSwitch else { return }
    userSwitch = nil
    guard selectedIndex == pending.index else { return }
    finishSwitch(pending)
    NSLog("[NativeShell] user selected tab index=%d", pending.index)
    bridge.userSelected(index: pending.index)
  }

  /// Hands the bars over from the selected tab before UIKit leaves it.
  private func beginSwitch(to index: Int) -> TabSwitch {
    let outgoing = selectedViewController as? UINavigationController
    let tabSwitch = TabSwitch(index: index, forward: index > selectedIndex, outgoing: outgoing)
    topBar?.beginTabSwitch(from: outgoing, in: view, forward: tabSwitch.forward)
    // Older UIKit needs Flutter installed before forwarding tab appearance.
    if #unavailable(iOS 27.0), let nav = viewControllers?[index] as? UINavigationController {
      attachFlutter(to: nav)
    }
    return tabSwitch
  }

  private func finishSwitch(_ tabSwitch: TabSwitch) {
    guard let nav = viewControllers?[tabSwitch.index] as? UINavigationController else { return }
    // iOS 27 needs the visible slot or it can leave Flutter's surface paused.
    attachFlutter(to: nav)
    // The tab left behind keeps only its root page. Coming back, Dart puts
    // the page on top of its branch on that root (see the top bar's reset),
    // which then never has to move Flutter into a page outside the window:
    // done while the switch is under way, that left the surface paused.
    if let outgoing = tabSwitch.outgoing, outgoing !== nav, outgoing.viewControllers.count > 1 {
      outgoing.setViewControllers([outgoing.viewControllers[0]], animated: false)
    }
    topBar?.finishTabSwitch(to: nav, forward: tabSwitch.forward)
  }

  /// Asks Flutter to act on a tap on the selected tab.
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
    return shouldSelectTab(at: index)
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
    return shouldSelectTab(at: index)
  }

  @available(iOS 18.0, *)
  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelectTab selectedTab: UITab,
    previousTab: UITab?
  ) {
    guard !isApplyingFlutterSelection else { return }
    finishUserSwitch()
  }

  func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
  ) {
    guard !isApplyingFlutterSelection else { return }
    finishUserSwitch()
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
      syncLayout()
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
    // Flutter changed tabs on its own (a swipe, a deep link), or brings UIKit
    // back to the tab its router landed on.
    pendingUserSelectionIndex = nil
    NSLog("[NativeShell] Dart selected index=%d", index)
    guard selectedIndex != index else {
      if let nav = controllers[index] as? UINavigationController {
        attachFlutter(to: nav)
      }
      return
    }
    // Flutter slides and fades the pages of a tab switch; the bars follow,
    // instead of the system swapping them at once.
    let tabSwitch = beginSwitch(to: index)
    isApplyingFlutterSelection = true
    selectedIndex = index
    isApplyingFlutterSelection = false
    finishSwitch(tabSwitch)
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

  /// The chip strip of each tab's navigation controller, created the first
  /// time a page of that tab has chips.
  private var chipStrips: [ObjectIdentifier: NativeTopBarChipStrip] = [:]

  /// How the shell lays its chrome out; see [setLayout].
  private(set) var layout = NativeShellLayout()

  /// The navigation controller of every tab.
  private var navigationControllers: [UINavigationController] {
    shell?.viewControllers?.compactMap { $0 as? UINavigationController } ?? []
  }

  /// Applies [layout] to every tab's bar and page, and tells Dart, which lays
  /// the pages out for it.
  func setLayout(_ layout: NativeShellLayout) {
    let changed = layout != self.layout
    if changed { restoreScrolledAwayBar() }
    self.layout = layout
    for nav in navigationControllers {
      nav.setNavigationBarHidden(layout.barHidden, animated: false)
      guard changed else { continue }
      for case let page as NativeTopBarPageController in nav.viewControllers {
        page.largeTitlesEnabled = layout.largeTitles
        // The logo and the large title's small title depend on the layout.
        if !page.itemMap.isEmpty { configure(page.itemMap, on: page) }
      }
    }
    if changed { syncChips(.none) }
    sendLayout()
  }

  private var layoutMap: [String: Any] {
    var map: [String: Any] = [
      "largeTitles": layout.largeTitles,
      "barHidden": layout.barHidden,
      "verticalTabs": layout.verticalTabs,
    ]
    if let bar = navigationController?.navigationBar, bar.window != nil {
      map["titleMargin"] = Double(bar.directionalLayoutMargins.leading)
    }
    return map
  }

  func sendLayout() {
    channel.invokeMethod("layout", arguments: layoutMap)
  }

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
  private var rootController: NativeTopBarPageController? {
    navigationController?.viewControllers.first as? NativeTopBarPageController
  }

  /// The page of the selected tab's stack that Dart knows as [token].
  private func page(token: Int) -> NativeTopBarPageController? {
    navigationController?.viewControllers.lazy
      .compactMap { $0 as? NativeTopBarPageController }
      .first { $0.token == token }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "reset":
      guard let args = call.arguments as? [String: Any],
        let map = args["item"] as? [String: Any]
      else {
        return result(FlutterError(code: "bad_args", message: nil, details: nil))
      }
      reset(map, scroll: args["scroll"] as? [String: Any])
      result(nil)
    case "push":
      guard let args = call.arguments as? [String: Any],
        let map = args["item"] as? [String: Any]
      else {
        return result(FlutterError(code: "bad_args", message: nil, details: nil))
      }
      push(map, scroll: args["scroll"] as? [String: Any])
      result(nil)
    case "pop":
      if let nav = navigationController, nav.viewControllers.count > 1 {
        restoreScrolledAwayBar()
        nav.popViewController(animated: true)
        syncChips(.pop)
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
      configure(map, on: top)
      syncChips(.fade)
      result(nil)
    case "scroll":
      guard let args = call.arguments as? [String: Any],
        let token = args["token"] as? Int
      else {
        return result(FlutterError(code: "bad_args", message: nil, details: nil))
      }
      // A page that has already left the stack has nothing to update.
      scroll(token: token, args, animated: args["animated"] as? Bool ?? false)
      result(nil)
    case "getLayout":
      result(layoutMap)
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

  func reset(_ map: [String: Any], scroll: [String: Any]? = nil) {
    guard let nav = navigationController, let root = rootController else { return }
    nav.delegate = self

    // A tab switch starts a new stack; clear whatever the previous page left
    // on this controller before installing the new item. Flutter moves back
    // to the root first, or clearing the stack would take the surface with the
    // page UIKit removes.
    // A tab switch hands the bar over: it still shows the outgoing tab's
    // items, and UIKit animates them into this page's, as on a single bar.
    let handover = relay.flatMap { $0.nav == ObjectIdentifier(nav) ? $0 : nil }
    relay = nil
    if nav.viewControllers.count > 1 {
      shell?.moveFlutter(to: root)
      nav.setViewControllers([root], animated: false)
      if let source = handover?.source { show(source, on: root) }
    }

    restoreScrolledAwayBar()
    root.token = map["token"] as? Int ?? 0
    configure(map, on: root, animated: handover != nil)
    if let scroll { root.applyScroll(scroll, animated: false) }
    syncChips(.none)
  }

  func push(_ map: [String: Any], scroll: [String: Any]? = nil) {
    guard let nav = navigationController else { return }
    nav.delegate = self
    restoreScrolledAwayBar()
    let page = NativeTopBarPageController()
    page.token = map["token"] as? Int ?? 0
    configure(map, on: page)
    if let scroll { page.applyScroll(scroll, animated: false) }
    nav.pushViewController(page, animated: true)
    syncChips(.push)
  }

  /// Follows the scroll position Dart reports for the page [token]: the
  /// bar's scroll-edge effect, the small title of a large-title page, and
  /// the chip strip moving up with the large title.
  func scroll(token: Int, _ state: [String: Any], animated: Bool) {
    guard let page = page(token: token) else { return }
    let previous = page.scrollOffset
    page.applyScroll(state, animated: animated)
    if page === navigationController?.topViewController {
      followScrollDirection(of: page, from: previous)
      syncChips(.none)
    }
  }

  // MARK: Bar scrolled away

  /// Beside the iPhone Duo vertical bar height is short in every pose, so,
  /// like the system apps there, the bar slides away while the page scrolls
  /// down and comes back as soon as it scrolls up. The safe area does not
  /// change, so Flutter's content does not move; the bar just leaves the
  /// content it was covering.
  private var barScrolledAway = false

  /// The page whose scroll-edge effect was turned off with the bar.
  private weak var scrolledAwayPage: NativeTopBarPageController?

  private var scrollingDown = false
  private var scrollTurnOffset: CGFloat = 0

  /// How far a page scrolls in one direction before the bar follows, so a
  /// jitter of the finger does not toggle it.
  private static let barScrollThreshold: CGFloat = 16

  private func followScrollDirection(of page: NativeTopBarPageController, from previous: CGFloat) {
    guard layout.verticalTabs, let nav = navigationController else { return }
    let offset = page.scrollOffset
    if offset <= 0 {
      setBarScrolledAway(false)
      return
    }
    guard offset != previous else { return }
    let down = offset > previous
    if down != scrollingDown {
      scrollingDown = down
      scrollTurnOffset = previous
    }
    guard abs(offset - scrollTurnOffset) >= Self.barScrollThreshold else { return }
    // Away only once the content has gone under the bar.
    setBarScrolledAway(down && offset > nav.navigationBar.frame.maxY)
  }

  private func setBarScrolledAway(_ away: Bool, animated: Bool = true) {
    guard away != barScrolledAway, let nav = navigationController else { return }
    barScrolledAway = away
    let bar = nav.navigationBar
    let page = nav.topViewController as? NativeTopBarPageController
    if #available(iOS 26.0, *) {
      // Its glass would otherwise stay behind as a band with nothing on it.
      scrolledAwayPage?.scrollProxy.topEdgeEffect.isHidden = false
      page?.scrollProxy.topEdgeEffect.isHidden = away
    }
    scrolledAwayPage = away ? page : nil
    let transform =
      away ? CGAffineTransform(translationX: 0, y: -bar.frame.maxY) : .identity
    if animated {
      UIView.animate(
        withDuration: 0.3,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
      ) {
        bar.transform = transform
      }
    } else {
      bar.transform = transform
    }
    syncChips(animated ? .fade : .none)
  }

  /// A page change or a layout change brings the bar back.
  private func restoreScrolledAwayBar() {
    scrollingDown = false
    scrollTurnOffset = 0
    setBarScrolledAway(false, animated: false)
  }

  /// The selected tab's chip strip; nil when none of its pages had chips.
  var chipStrip: UIView? {
    navigationController.flatMap { chipStrips[ObjectIdentifier($0)] }
  }

  /// Shows the chips of the page on top of the selected tab in the strip
  /// under its bar, or takes the strip away when that page has none.
  /// [transition] is how the page on top changed.
  private func syncChips(_ transition: NativeTopBarChipStrip.Transition) {
    guard let nav = navigationController else { return }
    var transition = transition
    if case .none = transition, let entrance = tabEntrance,
      entrance.nav == ObjectIdentifier(nav), CACurrentMediaTime() < entrance.until
    {
      // The page's chips arrived just after its tab came in: they join the
      // tab's entrance instead of popping in.
      transition = .enter(shift: entrance.shift)
    }
    let page = nav.topViewController as? NativeTopBarPageController
    // The strip sits below the large title, so it comes and goes with them.
    let chips = layout.largeTitles && !barScrolledAway ? page?.chips ?? [] : []
    let existing = chipStrips[ObjectIdentifier(nav)]
    guard let page, !chips.isEmpty else {
      existing?.setShown(false, covered: isCovered, transition: transition)
      return
    }
    let strip = existing ?? makeChipStrip(in: nav)
    strip.update(chips: chips, animated: transition.isAnimated)
    strip.follow(page: page)
    strip.setShown(true, covered: isCovered, transition: transition)
  }

  /// The tab whose bar is coming in, so chips that arrive for it a moment
  /// later come in the same way.
  private var tabEntrance: (nav: ObjectIdentifier, shift: CGPoint, until: CFTimeInterval)?

  /// How far Flutter slides a tab's page while switching tabs, along the
  /// axis the tabs run on: down the iPhone Duo vertical bar, across
  /// elsewhere. [sign] is 1 for the incoming page, which comes from the side
  /// of the next tab, and -1 for the outgoing one.
  private func tabSlide(in size: CGSize, forward: Bool, sign: CGFloat) -> CGPoint {
    let direction = (forward ? 1 : -1) * sign * NativeTopBarChipStrip.tabSlide
    return layout.verticalTabs
      ? CGPoint(x: 0, y: direction * size.height)
      : CGPoint(x: direction * size.width, y: 0)
  }

  /// A tab switch in progress: the incoming tab's bar shows the outgoing
  /// page's content until Dart installs the new page's item.
  private var relay: (nav: ObjectIdentifier, source: NativeTopBarPageController)?

  /// The page on top of the outgoing tab, captured before the switch.
  private var outgoingPage: NativeTopBarPageController?

  /// Called by the shell just before it switches from [nav]'s tab. Each tab
  /// has its own bar, which the switch removes at once; the incoming bar takes
  /// over what this one shows (see [finishTabSwitch]). The chips are not part
  /// of the bar, so they are left behind as an image in [container] that
  /// fades and slides out the way Flutter moves the outgoing page.
  func beginTabSwitch(from nav: UINavigationController?, in container: UIView, forward: Bool) {
    // The outgoing tab's bar is put back before it leaves; it is out of sight
    // by then, and comes back in place when its tab does.
    restoreScrolledAwayBar()
    outgoingPage = nav?.topViewController as? NativeTopBarPageController
    guard let nav, nav.view.window != nil,
      let strip = chipStrips[ObjectIdentifier(nav)], strip.isOnScreen,
      let image = strip.snapshotView(afterScreenUpdates: false)
    else { return }
    image.frame = strip.convert(strip.bounds, to: container)
    image.alpha = strip.alpha
    image.isUserInteractionEnabled = false
    container.addSubview(image)
    let shift = tabSlide(in: container.bounds.size, forward: forward, sign: -1)
    let animator = NativeTopBarChipStrip.tabAnimator()
    animator.addAnimations {
      image.alpha = 0
      image.transform = CGAffineTransform(translationX: shift.x, y: shift.y)
    }
    animator.addCompletion { _ in image.removeFromSuperview() }
    animator.startAnimation()
  }

  /// Called by the shell once [nav]'s tab is selected. Its bar first shows
  /// exactly what the outgoing bar showed, in the same place, so the two read
  /// as one bar; [reset] then animates it to the incoming page's items with
  /// UIKit's own Liquid Glass transition. The chips slide in from the side the
  /// page comes from.
  func finishTabSwitch(to nav: UINavigationController?, forward: Bool) {
    let source = outgoingPage
    outgoingPage = nil
    guard let nav, nav.view.window != nil else { return }
    if let source, let page = nav.topViewController as? NativeTopBarPageController,
      page !== source
    {
      show(source, on: page)
      // UIKit animates from the items the bar has laid out, not from the
      // ones last assigned: lay the borrowed ones out now, or the change
      // would start from what this bar showed on its previous visit.
      nav.navigationBar.setNeedsLayout()
      nav.navigationBar.layoutIfNeeded()
      let id = ObjectIdentifier(nav)
      relay = (id, source)
      // Should Dart not install the incoming item, the page returns to its
      // own content rather than keeping the outgoing tab's.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak page] in
        guard let self, let page, let relay = self.relay, relay.nav == id else { return }
        self.relay = nil
        self.configure(page.itemMap, on: page, animated: true)
      }
    }
    let shift = tabSlide(in: nav.view.bounds.size, forward: forward, sign: 1)
    tabEntrance = (ObjectIdentifier(nav), shift, CACurrentMediaTime() + 0.3)
    chipStrips[ObjectIdentifier(nav)]?.playEntrance(shift: shift)
  }

  /// Shows [source]'s bar content on [page]'s navigation item, as [source]'s
  /// bar showed it, without changing [page]'s own state.
  private func show(_ source: NativeTopBarPageController, on page: NativeTopBarPageController) {
    let content = makeBarContent(source.itemMap)
    content.titleView?.content.alpha = source.isTitleShown ? 1 : 0
    // Scroll reports for [page] must not fade a title that is not its own.
    page.titleView = nil
    apply(content, to: page.navigationItem, in: nil, animated: false)
  }

  private func makeChipStrip(in nav: UINavigationController) -> NativeTopBarChipStrip {
    let strip = NativeTopBarChipStrip()
    strip.onTap = { [weak self, weak nav] index in
      guard let page = nav?.topViewController as? NativeTopBarPageController else { return }
      self?.channel.invokeMethod("onChip", arguments: ["token": page.token, "index": index])
    }
    strip.onLongPress = { [weak self, weak nav] index in
      guard let page = nav?.topViewController as? NativeTopBarPageController else { return }
      self?.channel.invokeMethod(
        "onChipLongPress",
        arguments: ["token": page.token, "index": index]
      )
    }
    strip.install(in: nav)
    chipStrips[ObjectIdentifier(nav)] = strip
    return strip
  }

  /// Hides or shows every tab's bar. UIKit adds or removes the matching safe
  /// area for us, so Flutter content follows without a manual inset.
  func setVisible(_ visible: Bool) {
    for nav in navigationControllers {
      nav.setNavigationBarHidden(!visible, animated: false)
    }
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
    chipStrips[ObjectIdentifier(nav)]?.setCovered(isCovered)

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

  private func configure(
    _ map: [String: Any],
    on page: NativeTopBarPageController,
    animated: Bool = false
  ) {
    page.itemMap = map
    page.largeTitlesEnabled = layout.largeTitles
    page.wantsLargeTitle = map["largeTitle"] as? Bool == true
    page.largeTitleBand = CGFloat(
      (map["largeTitleHeight"] as? NSNumber)?.doubleValue ?? 0
    )
    page.largeTitleCollapseOffset = CGFloat(
      (map["largeTitleCollapseOffset"] as? NSNumber)?.doubleValue
        ?? Double(page.largeTitleBand)
    )
    page.chips = (map["chips"] as? [[String: Any]] ?? []).map {
      NativeTopBarChip(
        title: $0["title"] as? String ?? "",
        selected: $0["selected"] as? Bool == true
      )
    }
    let content = makeBarContent(map)
    page.titleView = content.titleView
    apply(
      content,
      to: page.navigationItem,
      in: page.navigationController?.navigationBar,
      animated: animated
    )
  }

  /// What a page shows in the bar: its title and its buttons.
  private struct BarContent {
    var title: String?
    var titleView: NativeTopBarTitleView?
    var leading: [UIBarButtonItem]
    var trailing: [UIBarButtonItem]
  }

  private func makeBarContent(_ map: [String: Any]) -> BarContent {
    let token = map["token"] as? Int ?? 0
    let title = map["title"] as? String
    // Where the tabs share the bar (iPad) it shows no page title, and so not
    // the logo either.
    let logo = map["logo"] as? Bool == true && !layout.tabsInBar
    let largeTitle = map["largeTitle"] as? Bool == true && layout.largeTitles
    var titleView: NativeTopBarTitleView?
    if let title, !title.isEmpty, logo || largeTitle {
      // A large-title page shows this title only once Flutter's large title
      // has scrolled under the bar, so it has to be a view we can fade.
      // Beside the vertical bar a plain title sits at the leading edge, as
      // the system puts its own; the logo stays centred, as it is everywhere.
      titleView = NativeTopBarTitleView(
        content: logo ? Self.makeLogoTitleView(title: title) : Self.makeTitleView(title: title),
        leadingBesideVerticalBar: !logo
      )
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
      Self.identify(back, as: "back")
      leading.append(back)
    } else if map["leading"] as? String == "close" {
      let close = UIBarButtonItem(
        image: UIImage(systemName: "xmark"),
        primaryAction: UIAction { [weak self] _ in
          self?.channel.invokeMethod("onLeading", arguments: ["token": token])
        }
      )
      close.accessibilityLabel = "Close"
      Self.identify(close, as: "close")
      leading.append(close)
    }

    if let tint = map["tint"] as? NSNumber {
      let color = Self.colorFromARGB(tint.intValue)
      leading.forEach { $0.tintColor = color }
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
          // The same action on two pages is the same button: the bar morphs
          // it instead of replacing it.
          let key = action["icon"] as? String ?? action["title"] as? String
          Self.identify(button, as: "action.\(key ?? String(index))")
          trailing.append(button)

          if let spacerAfter = action["spacerAfter"] as? Int, spacerAfter == 1 {
            if #available(iOS 16.0, *) {
              trailing.append(.fixedSpace(12))
            }
          }
        }
      }
    }
    return BarContent(
      title: title,
      titleView: titleView,
      leading: leading,
      trailing: trailing.reversed()
    )
  }

  private func apply(
    _ content: BarContent,
    to item: UINavigationItem,
    in bar: UINavigationBar?,
    animated: Bool
  ) {
    // The title being replaced, if shown, fades out instead of vanishing. It
    // may never have been drawn (a tab switch has just put it there), so the
    // view itself moves over rather than an image of it.
    let previousTitle = (item.titleView as? NativeTopBarTitleView)?.content
    let outgoing = animated && (previousTitle?.alpha ?? 0) > 0.01 ? previousTitle : nil
    if let titleView = content.titleView {
      item.title = nil
      item.titleView = titleView
    } else {
      item.titleView = nil
      item.title = content.title
    }
    item.hidesBackButton = true
    if #available(iOS 27.1, *) {
      // The bar decides the axis; ask for the vertical one when both exist.
      item.verticalBarCompressionBehavior = .automatic
    }
    if animated, let titleView = content.titleView, let bar {
      // A new title view laid out inside the animated item change would grow
      // from an empty frame. Give it its frame first, then fade it in with
      // the buttons.
      bar.layoutIfNeeded()
      let title = titleView.content
      let target = title.alpha
      title.alpha = 0
      if let outgoing {
        let size = outgoing.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        outgoing.removeFromSuperview()
        outgoing.translatesAutoresizingMaskIntoConstraints = true
        outgoing.isUserInteractionEnabled = false
        outgoing.frame = CGRect(
          x: titleView.bounds.midX - size.width / 2,
          y: titleView.bounds.midY - size.height / 2,
          width: size.width,
          height: size.height
        )
        titleView.addSubview(outgoing)
      }
      UIView.animate(
        withDuration: 0.25,
        delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
        animations: {
          title.alpha = target
          outgoing?.alpha = 0
        },
        completion: { _ in outgoing?.removeFromSuperview() }
      )
    }
    item.setLeftBarButtonItems(content.leading, animated: animated)
    item.setRightBarButtonItems(content.trailing, animated: animated)
  }

  private static func identify(_ item: UIBarButtonItem, as identifier: String) {
    if #available(iOS 26.0, *) {
      item.identifier = identifier
    }
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
    label.font = titleFont
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .label

    let stack = UIStackView(arrangedSubviews: [imageView, label])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 6
    return stack
  }

  /// A plain title, styled like the bar's own inline title.
  private static func makeTitleView(title: String) -> UIView {
    let label = UILabel()
    label.text = title
    label.font = titleFont
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .label
    label.accessibilityTraits.insert(.header)
    return label
  }

  private static var titleFont: UIFont {
    UIFontMetrics(forTextStyle: .headline).scaledFont(
      for: .systemFont(ofSize: 17, weight: .semibold)
    )
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

/// One page of a tab's stack: the root page Flutter starts on, or a
/// placeholder pushed so the bar plays UIKit's own item transition. Flutter
/// draws the page itself; this controller only carries the navigation item
/// and the page's scroll position.
final class NativeTopBarPageController: UIViewController {
  var token: Int = 0

  /// The item Dart last described for this page.
  var itemMap: [String: Any] = [:]

  /// Whether the bar shows this page's small title right now.
  var isTitleShown: Bool { !largeTitle || scrollOffset >= collapseOffset }

  /// The page asks for a large title.
  var wantsLargeTitle = false {
    didSet { largeTitleChanged() }
  }

  /// The shell's layout has large titles (see `NativeShellLayout`).
  var largeTitlesEnabled = false {
    didSet { largeTitleChanged() }
  }

  /// Flutter draws this page's title large while its content is at the top,
  /// so the bar shows [titleView] only after that title has scrolled away.
  var largeTitle: Bool { wantsLargeTitle && largeTitlesEnabled }

  /// The custom title view of the navigation item, faded in and out here.
  weak var titleView: NativeTopBarTitleView? {
    didSet { updateTitleVisibility(animated: false) }
  }

  /// Height of the band Flutter's large title takes under the bar, as Dart
  /// describes it.
  var largeTitleBand: CGFloat = 0 {
    didSet { syncProxyOffset() }
  }

  /// How far the page scrolls before the top of the large title reaches the
  /// bar, as Dart describes it. The bar's glass starts there, as the large
  /// title fades out, so the glass never covers part of it.
  var largeTitleCollapseOffset: CGFloat = 0 {
    didSet { syncProxyOffset() }
  }

  /// The large title band in the current layout; content only reaches the
  /// bar once it has scrolled past it.
  var largeTitleHeight: CGFloat { largeTitle ? largeTitleBand : 0 }

  private var collapseOffset: CGFloat { largeTitle ? largeTitleCollapseOffset : 0 }

  /// The chips Dart describes; the strip under the bar shows them where the
  /// layout has large titles.
  var chips: [NativeTopBarChip] = []

  /// Whether content has scrolled past the large title band, under the bar
  /// and the chip strip.
  var contentIsUnderBar: Bool { scrollOffset > largeTitleHeight }

  /// How far Flutter's content has scrolled, as reported by Dart.
  private(set) var scrollOffset: CGFloat = 0

  let scrollProxy = NativeTopBarScrollProxy()

  override func loadView() {
    let view = UIView()
    view.backgroundColor = .clear
    view.isOpaque = false
    scrollProxy.frame = view.bounds
    scrollProxy.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    // Added before Flutter is inserted below it, so the proxy's scroll-edge
    // effect is drawn over Flutter's content.
    view.addSubview(scrollProxy)
    self.view = view
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    // Flutter's content is not a UIScrollView, so the bar would otherwise
    // never learn that content has scrolled under it.
    setContentScrollView(scrollProxy, for: .top)
  }

  /// Mirrors the page's scroll position sent by Dart: `offset`, how far the
  /// content has scrolled up.
  func applyScroll(_ state: [String: Any], animated: Bool) {
    guard let offset = (state["offset"] as? NSNumber)?.doubleValue else { return }
    scrollOffset = CGFloat(offset)
    syncProxyOffset()
    updateTitleVisibility(animated: animated)
  }

  private func largeTitleChanged() {
    syncProxyOffset()
    updateTitleVisibility(animated: false)
  }

  /// The bar fades its edge effect in as soon as the proxy leaves the top,
  /// wherever its content is, so the proxy stays at the top until the large
  /// title is about to go under the bar.
  private func syncProxyOffset() {
    scrollProxy.offsetFromTop = max(0, scrollOffset - collapseOffset)
  }

  private func updateTitleVisibility(animated: Bool) {
    guard let content = titleView?.content else { return }
    let alpha: CGFloat = isTitleShown ? 1 : 0
    guard content.alpha != alpha else { return }
    guard animated else {
      content.alpha = alpha
      return
    }
    UIView.animate(
      withDuration: 0.2,
      delay: 0,
      options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]
    ) {
      content.alpha = alpha
    }
  }
}

/// The navigation item's title view on pages that fade their title.
///
/// The bar animates the alpha of the title view it is given during its own
/// transitions, so the fade is applied to [content] inside it instead.
final class NativeTopBarTitleView: UIView {
  let content: UIView

  /// Whether the title takes the leading edge of the band beside the iPhone
  /// Duo vertical bar, where the system puts a plain title.
  private let leadingBesideVerticalBar: Bool

  init(content: UIView, leadingBesideVerticalBar: Bool = true) {
    self.content = content
    self.leadingBesideVerticalBar = leadingBesideVerticalBar
    super.init(frame: .zero)
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      content.topAnchor.constraint(equalTo: topAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    if #available(iOS 27.1, *) {
      registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
        (self: Self, _: UITraitCollection) in
        self.invalidateIntrinsicContentSize()
      }
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Beside the iPhone Duo vertical bar the system puts a plain title at the
  /// leading edge of the title band. A title view is centred instead, unless
  /// it takes the whole band, so it does, with its content at the start.
  private var fillsBand: Bool {
    guard leadingBesideVerticalBar else { return false }
    if #available(iOS 27.1, *) {
      return traitCollection.verticalBarEdge != .unspecified
    }
    return false
  }

  override var intrinsicContentSize: CGSize {
    let size = content.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    guard fillsBand else { return size }
    return CGSize(width: UIView.layoutFittingExpandedSize.width, height: size.height)
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    intrinsicContentSize
  }
}

final class NativeTopBarScrollProxy: UIScrollView {
  var offsetFromTop: CGFloat = 0 {
    didSet { syncOffset() }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isUserInteractionEnabled = false
    // The status bar tap belongs to Flutter's own scroll-to-top view; UIKit
    // only honours it when exactly one scroll view asks for it.
    scrollsToTop = false
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .always
    // Tall enough that the offset is never clamped by the content.
    contentSize = CGSize(width: 1, height: 1_000_000)
    isAccessibilityElement = false
    accessibilityElementsHidden = true
    if #available(iOS 26.0, *) {
      // Only the top bar follows Flutter's scroll position.
      bottomEdgeEffect.isHidden = true
      leftEdgeEffect.isHidden = true
      rightEdgeEffect.isHidden = true
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// The inset changes when the bar is shown or hidden and on rotation; keep
  /// the same distance from the top.
  override func adjustedContentInsetDidChange() {
    super.adjustedContentInsetDidChange()
    syncOffset()
  }

  private func syncOffset() {
    let target = CGPoint(
      x: -adjustedContentInset.left,
      y: -adjustedContentInset.top + offsetFromTop
    )
    if contentOffset != target {
      contentOffset = target
    }
  }
}

/// One chip of a page's strip under the bar, as Dart describes it.
struct NativeTopBarChip: Equatable {
  let title: String
  let selected: Bool
}

/// A row of Liquid Glass chips under one tab's bar, such as the card folders.
///
/// It lives in the navigation controller's view, below the bar and above the
/// pages, so it stays put while pages change underneath and only fades when
/// the page on top has no chips. On a large-title page it sits under Flutter's
/// large title and moves up with it, then stays under the bar while content
/// scrolls beneath. The page's scroll-edge effect extends behind it, so that
/// content never shows sharply between the chips.
final class NativeTopBarChipStrip: UIView {
  var onTap: ((Int) -> Void)?
  var onLongPress: ((Int) -> Void)?

  private let scrollView = UIScrollView()
  private let stack = UIStackView()
  private var chips: [NativeTopBarChip] = []
  private var buttons: [UIButton] = []
  private var topConstraint: NSLayoutConstraint?
  private var shown = false
  private var covered = false
  private var edgeInteraction: AnyObject?

  /// Height of the strip; Dart insets the page by the same amount
  /// (`kTopBarAccessoryHeight`).
  static let height: CGFloat = 52

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    alpha = 0
    isHidden = true

    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.showsHorizontalScrollIndicator = false
    scrollView.showsVerticalScrollIndicator = false
    scrollView.alwaysBounceVertical = false
    scrollView.scrollsToTop = false
    // Glass draws a little outside each chip.
    scrollView.clipsToBounds = false
    scrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
    addSubview(scrollView)

    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    scrollView.addSubview(stack)

    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
    ])

    if #available(iOS 26.0, *) {
      let interaction = UIScrollEdgeElementContainerInteraction()
      interaction.edge = .top
      addInteraction(interaction)
      edgeInteraction = interaction
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Places the strip under [nav]'s bar, above its pages.
  func install(in nav: UINavigationController) {
    nav.view.insertSubview(self, belowSubview: nav.navigationBar)
    let top = topAnchor.constraint(equalTo: nav.navigationBar.bottomAnchor)
    topConstraint = top
    NSLayoutConstraint.activate([
      // Clear of the side strips, such as the iPhone Duo vertical bar.
      leadingAnchor.constraint(equalTo: nav.view.safeAreaLayoutGuide.leadingAnchor),
      trailingAnchor.constraint(equalTo: nav.view.safeAreaLayoutGuide.trailingAnchor),
      heightAnchor.constraint(equalToConstant: Self.height),
      top,
    ])
  }

  /// Sits below [page]'s large title and moves with it: up as it collapses,
  /// down when the content is pulled past the top.
  func follow(page: NativeTopBarPageController) {
    let band = page.largeTitleHeight
    topConstraint?.constant = band > 0 ? band - min(page.scrollOffset, band) : 0
    if #available(iOS 26.0, *) {
      // UIKit shows the edge effect as soon as the strip overlaps the proxy's
      // content, and the proxy, which cannot move with the large title, would
      // overlap it from the start and blur the title. Extend the effect
      // behind the chips only once content really is beneath them.
      (edgeInteraction as? UIScrollEdgeElementContainerInteraction)?.scrollView =
        page.contentIsUnderBar ? page.scrollProxy : nil
    }
  }

  func update(chips: [NativeTopBarChip], animated: Bool) {
    guard chips != self.chips else { return }
    let sameChips = chips.map(\.title) == self.chips.map(\.title)
    self.chips = chips
    if sameChips {
      let restyle = {
        for (button, chip) in zip(self.buttons, chips) {
          self.style(button, as: chip)
        }
      }
      if animated {
        UIView.animate(withDuration: 0.2, animations: restyle)
      } else {
        restyle()
      }
    } else {
      rebuild()
    }
    revealSelection(animated: animated && sameChips)
  }

  /// How the page that owns the chips changed, which decides how the strip
  /// comes and goes.
  enum Transition {
    /// No visible change of page (first install, a scroll report).
    case none
    /// The same page changed its chips.
    case fade
    /// A page was pushed: chips of the page underneath slide off to the left
    /// with it, as UIKit moves the outgoing page.
    case push
    /// A page was popped: chips of the revealed page slide back in.
    case pop
    /// Their tab is coming in, sliding by [shift] like Flutter's tab switch.
    case enter(shift: CGPoint)

    var isAnimated: Bool {
      if case .none = self { return false }
      return true
    }
  }

  /// How far Flutter slides a tab's page while switching tabs, as a fraction
  /// of the width.
  static let tabSlide: CGFloat = 0.1

  /// Flutter's tab switch: 250ms, ease-out cubic.
  static func tabAnimator() -> UIViewPropertyAnimator {
    UIViewPropertyAnimator(
      duration: 0.25,
      controlPoint1: CGPoint(x: 0.215, y: 0.61),
      controlPoint2: CGPoint(x: 0.355, y: 1)
    )
  }

  /// Whether the strip is drawn right now, mid-animation included.
  var isOnScreen: Bool { !isHidden && alpha > 0.01 && window != nil }

  private var targetAlpha: CGFloat { shown ? (covered ? 0.45 : 1) : 0 }

  /// Shows or hides the strip. Repeating the current state changes nothing,
  /// so a scroll report cannot cut a running transition short.
  func setShown(_ shown: Bool, covered: Bool, transition: Transition) {
    let appearing = shown && !self.shown
    let disappearing = !shown && self.shown
    let coverChanged = covered != self.covered
    self.shown = shown
    self.covered = covered
    isUserInteractionEnabled = shown && !covered
    if appearing {
      appear(transition)
    } else if disappearing {
      disappear(transition)
    } else if coverChanged {
      animate(toAlpha: targetAlpha, translation: .zero, .fade)
    }
  }

  /// Dimmed and inert while a Flutter modal covers the page, like the bar.
  func setCovered(_ covered: Bool) {
    setShown(shown, covered: covered, transition: .fade)
  }

  /// Brings a strip that is already shown in with its tab.
  func playEntrance(shift: CGPoint) {
    guard shown else { return }
    isHidden = false
    animate(toAlpha: targetAlpha, translation: .zero, from: (0, shift), .enter(shift: shift))
  }

  private func appear(_ transition: Transition) {
    let from: CGPoint
    switch transition {
    case .none:
      isHidden = false
      animate(toAlpha: targetAlpha, translation: .zero, .none)
      return
    case .fade: from = .zero
    case .push: from = CGPoint(x: bounds.width / 3, y: 0)
    case .pop: from = CGPoint(x: -bounds.width / 3, y: 0)
    case .enter(let shift): from = shift
    }
    let fromHidden = isHidden || alpha < 0.01
    isHidden = false
    animate(
      toAlpha: targetAlpha,
      translation: .zero,
      from: fromHidden ? (0, from) : nil,
      transition
    )
  }

  private func disappear(_ transition: Transition) {
    let to: CGFloat
    switch transition {
    case .none:
      animate(toAlpha: 0, translation: .zero, .none)
      isHidden = true
      return
    case .fade, .enter: to = 0
    case .push: to = -bounds.width / 3
    case .pop: to = bounds.width / 3
    }
    animate(toAlpha: 0, translation: CGPoint(x: to, y: 0), transition) {
      guard !self.shown else { return }
      self.isHidden = true
      self.transform = .identity
    }
  }

  /// Counts the animations started, so a superseded one does not complete.
  private var animationGeneration = 0

  /// Moves the strip to [alpha] and [translation] with the timing of
  /// [transition], starting from [from] or from wherever a running animation
  /// has got to.
  ///
  /// Animated on the layer: a UIKit animation of this view would configure an
  /// animation for every glass effect inside it, which costs a frame right as
  /// a page or tab changes.
  private func animate(
    toAlpha alpha: CGFloat,
    translation: CGPoint,
    from: (alpha: CGFloat, translation: CGPoint)? = nil,
    _ transition: Transition,
    completion: (() -> Void)? = nil
  ) {
    let current = layer.presentation() ?? layer
    let fromOpacity = from.map { Float($0.alpha) } ?? current.opacity
    let fromTransform =
      from.map { CATransform3DMakeTranslation($0.translation.x, $0.translation.y, 0) }
      ?? current.transform
    layer.removeAnimation(forKey: "visibility")
    animationGeneration += 1
    let generation = animationGeneration
    self.alpha = alpha
    transform = CGAffineTransform(translationX: translation.x, y: translation.y)
    guard transition.isAnimated else {
      completion?()
      return
    }

    let fade = Self.animation(keyPath: "opacity", for: transition)
    fade.fromValue = fromOpacity
    fade.toValue = Float(alpha)
    let slide = Self.animation(keyPath: "transform", for: transition)
    slide.fromValue = fromTransform
    slide.toValue = CATransform3DMakeTranslation(translation.x, translation.y, 0)
    let group = CAAnimationGroup()
    group.animations = [fade, slide]
    group.duration = max(fade.duration, slide.duration)

    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self] in
      guard let self, self.animationGeneration == generation else { return }
      completion?()
    }
    layer.add(group, forKey: "visibility")
    CATransaction.commit()
  }

  private static func animation(keyPath: String, for transition: Transition) -> CABasicAnimation {
    switch transition {
    case .push, .pop:
      // The navigation bar's own push and pop: critically damped.
      let spring = CASpringAnimation(perceptualDuration: 0.35, bounce: 0)
      spring.keyPath = keyPath
      spring.duration = spring.settlingDuration
      return spring
    case .enter:
      // Flutter's tab switch: 250ms, ease-out cubic.
      let animation = CABasicAnimation(keyPath: keyPath)
      animation.duration = 0.25
      animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
      return animation
    case .none, .fade:
      let animation = CABasicAnimation(keyPath: keyPath)
      animation.duration = 0.2
      animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      return animation
    }
  }

  /// Touches between the chips reach Flutter's content below.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hit = super.hitTest(point, with: event)
    return hit === self || hit === scrollView || hit === stack ? nil : hit
  }

  private func rebuild() {
    buttons.forEach { $0.removeFromSuperview() }
    buttons = chips.enumerated().map { index, chip in
      let button = UIButton(type: .system)
      button.tag = index
      // Each chip keeps its own title's width; the stack must not even them
      // out.
      button.setContentHuggingPriority(.required, for: .horizontal)
      button.setContentCompressionResistancePriority(.required, for: .horizontal)
      style(button, as: chip)
      button.addAction(
        UIAction { [weak self] _ in self?.onTap?(index) },
        for: .primaryActionTriggered
      )
      button.addGestureRecognizer(
        UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
      )
      stack.addArrangedSubview(button)
      return button
    }
    layoutIfNeeded()
  }

  private func style(_ button: UIButton, as chip: NativeTopBarChip) {
    var configuration: UIButton.Configuration
    if #available(iOS 26.0, *) {
      configuration = chip.selected ? .prominentGlass() : .glass()
    } else {
      configuration = chip.selected ? .filled() : .gray()
    }
    configuration.title = chip.title
    configuration.cornerStyle = .capsule
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
      var attributes = $0
      attributes.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
        for: .systemFont(ofSize: 15, weight: .medium)
      )
      return attributes
    }
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 8, leading: 14, bottom: 8, trailing: 14
    )
    if !chip.selected {
      configuration.baseForegroundColor = .label
    }
    button.configuration = configuration
    if chip.selected {
      button.accessibilityTraits.insert(.selected)
    } else {
      button.accessibilityTraits.remove(.selected)
    }
  }

  private func revealSelection(animated: Bool) {
    guard let index = chips.firstIndex(where: \.selected),
      buttons.indices.contains(index)
    else { return }
    layoutIfNeeded()
    scrollView.scrollRectToVisible(
      buttons[index].frame.insetBy(dx: -16, dy: 0),
      animated: animated
    )
  }

  @objc private func longPressed(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let index = recognizer.view?.tag else { return }
    onLongPress?(index)
  }
}

/// Keeps Flutter's accessibility scroll views from drawing a scroll-edge
/// effect.
///
/// While semantics are on (VoiceOver, Voice Control, Switch Control...)
/// Flutter mirrors every scrollable with an invisible
/// `FlutterSemanticsScrollView` that follows its offset. iOS 26 gives those
/// real scroll views their own edge effect under the bar, which paints the bar
/// white as soon as a page scrolls, ignoring where its content is. The page's
/// own proxy scroll view is what draws the bar's effect, so theirs is hidden
/// as each one enters the window.
private enum FlutterSemanticsEdgeEffects {
  static func disable() {
    _ = installed
  }

  private static let installed: Void = {
    guard #available(iOS 26.0, *),
      let semanticsClass = NSClassFromString("FlutterSemanticsScrollView"),
      let method = class_getInstanceMethod(semanticsClass, #selector(UIView.didMoveToWindow))
    else { return }
    typealias DidMoveToWindow = @convention(c) (AnyObject, Selector) -> Void
    let original = unsafeBitCast(method_getImplementation(method), to: DidMoveToWindow.self)
    let replacement: @convention(block) (UIScrollView) -> Void = { scrollView in
      original(scrollView, #selector(UIView.didMoveToWindow))
      scrollView.topEdgeEffect.isHidden = true
      scrollView.bottomEdgeEffect.isHidden = true
      scrollView.leftEdgeEffect.isHidden = true
      scrollView.rightEdgeEffect.isHidden = true
    }
    let implementation = imp_implementationWithBlock(replacement)
    // Overrides the method on Flutter's class only; when the class does not
    // define it, the inherited one is still called first.
    if !class_addMethod(
      semanticsClass,
      #selector(UIView.didMoveToWindow),
      implementation,
      method_getTypeEncoding(method)
    ) {
      method_setImplementation(method, implementation)
    }
  }()
}

/// How the shell lays its chrome out, decided from the window's traits rather
/// than from the device: the system itself places the bars and tabs, and this
/// only covers what the app adds on top of them.
struct NativeShellLayout: Equatable {
  /// Pages draw their large title, which the bar collapses into its small
  /// title, and get the chip strip below it. Only where the window is compact
  /// in width and the tab bar therefore sits at the bottom, apart from the bar.
  var largeTitles = false

  /// The app has no top bar where height is compact (an iPhone in landscape),
  /// except beside a vertical bar, which keeps the items.
  var barHidden = false

  /// A regular-width window puts the tabs inside the top bar (iPad), which
  /// then shows no page title.
  var tabsInBar = false

  /// The tabs run down a vertical bar (iPhone Duo).
  var verticalTabs = false

  init() {}

  init(traits: UITraitCollection) {
    if #available(iOS 27.1, *) {
      verticalTabs = traits.verticalBarEdge != .unspecified
    }
    barHidden = traits.verticalSizeClass == .compact && !verticalTabs
    tabsInBar = traits.horizontalSizeClass == .regular && !verticalTabs && !barHidden
    largeTitles = traits.horizontalSizeClass == .compact && !barHidden
  }
}
