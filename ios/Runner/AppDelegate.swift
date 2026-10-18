import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "dev.hinata.go.main")
  lazy var nativeShellBridge = NativeShellBridge(messenger: flutterEngine.binaryMessenger)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run(withEntrypoint: "nativeMain")
    GeneratedPluginRegistrant.register(with: flutterEngine)
    PrismURLBridge.shared.attach()
    StoreVisitLiveActivityManager.shared.startGlobalActivityTracking()
    _ = nativeShellBridge
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
