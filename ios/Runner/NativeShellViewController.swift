import Flutter
import UIKit

final class NativeShellViewController: UITabBarController,
  UITabBarControllerDelegate, NativeShellBridgeDelegate
{
  private let flutterViewController: FlutterViewController
  private let bridge: NativeShellBridge
  private var flutterConstraints: [NSLayoutConstraint] = []
  private var cardsActionButton: UIButton!
  private var scaffoldCovered = false
  private var nativeChromeHidden = false
  private var localizedStrings = [
    "scan": "Scan",
    "cards": "Cards",
    "settings": "Settings",
    "addCard": "Add Card",
    "newFolder": "New Folder",
  ]

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
    installCardsActions()
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
  }

  private func installCardsActions() {
    cardsActionButton = makeGlassButton(
      symbol: "plus",
      accessibilityLabel: localizedStrings["addCard"] ?? "Add Card"
    )
    cardsActionButton.menu = makeCardsMenu()
    cardsActionButton.showsMenuAsPrimaryAction = true
    view.addSubview(cardsActionButton)
    NSLayoutConstraint.activate([
      cardsActionButton.widthAnchor.constraint(equalToConstant: 56),
      cardsActionButton.heightAnchor.constraint(equalToConstant: 56),
      cardsActionButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      cardsActionButton.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -16),
    ])
    updateCardsActionsVisibility()
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

  private func makeCardsMenu() -> UIMenu {
    UIMenu(title: "", children: [
      UIAction(title: localizedStrings["addCard"] ?? "Add Card") { [weak self] _ in
        self?.bridge.userRequested(action: "addCard")
      },
      UIAction(title: localizedStrings["newFolder"] ?? "New Folder") { [weak self] _ in
        self?.bridge.userRequested(action: "addFolder")
      },
    ])
  }

  private func applyLocalizedStrings(_ strings: [String: String]) {
    localizedStrings.merge(strings) { _, new in new }
    viewControllers?[0].tabBarItem.title = localizedStrings["scan"]
    viewControllers?[1].tabBarItem.title = localizedStrings["cards"]
    viewControllers?[2].tabBarItem.title = localizedStrings["settings"]
    cardsActionButton?.accessibilityLabel = localizedStrings["addCard"]
    cardsActionButton?.menu = makeCardsMenu()
  }

  private func updateCardsActionsVisibility() {
    cardsActionButton?.isHidden = selectedIndex != 1 || nativeChromeHidden
    cardsActionButton?.alpha = scaffoldCovered ? 0.46 : 1
    cardsActionButton?.isUserInteractionEnabled = !scaffoldCovered && !nativeChromeHidden
  }

  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
    guard let controllers = viewControllers,
      let index = controllers.firstIndex(of: viewController)
    else { return }
    attachFlutter(to: viewController)
    updateCardsActionsVisibility()
    bridge.userSelected(index: index)
  }

  func nativeShell(setSelectedIndex index: Int) {
    guard let controllers = viewControllers, controllers.indices.contains(index) else { return }
    if selectedIndex != index { selectedIndex = index }
    attachFlutter(to: controllers[index])
    updateCardsActionsVisibility()
  }

  func nativeShell(setSettingsBadge visible: Bool) {
    viewControllers?[2].tabBarItem.badgeValue = visible ? "1" : nil
  }

  func nativeShell(setScaffoldCovered covered: Bool, hideNativeChrome: Bool) {
    scaffoldCovered = covered
    nativeChromeHidden = hideNativeChrome || (nativeChromeHidden && covered)
    tabBar.isHidden = nativeChromeHidden
    tabBar.isUserInteractionEnabled = !covered && !hideNativeChrome
    tabBar.alpha = covered ? 0.20 : 1
    updateCardsActionsVisibility()
  }

  func nativeShell(setLocalizedStrings strings: [String: String]) {
    applyLocalizedStrings(strings)
  }
}
