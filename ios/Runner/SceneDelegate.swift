import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions,
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    guard let windowScene = scene as? UIWindowScene,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    else { return }

    let flutterViewController = FlutterViewController(
      engine: appDelegate.flutterEngine,
      nibName: nil,
      bundle: nil
    )
    let shell = NativeShellViewController(
      flutterViewController: flutterViewController,
      bridge: appDelegate.nativeShellBridge
    )
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = shell
    self.window = window
    window.makeKeyAndVisible()
    connectionOptions.userActivities.forEach { PrismURLBridge.shared.handle($0) }
    connectionOptions.urlContexts.forEach { PrismURLBridge.shared.handle($0.url) }
  }

  override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    PrismURLBridge.shared.handle(userActivity)
    super.scene(scene, continue: userActivity)
  }

  /// A Live Activity tap can be delivered as a plain URL open rather than a user activity.
  /// Without this the main app silently dropped those taps.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    URLContexts.forEach { PrismURLBridge.shared.handle($0.url) }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
