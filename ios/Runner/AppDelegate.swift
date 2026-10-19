import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  let flutterEngine = FlutterEngine(name: "dev.hinata.go.main")
  lazy var nativeShellBridge = NativeShellBridge(messenger: flutterEngine.binaryMessenger)
  lazy var deviceOrientationBridge = DeviceOrientationBridge(
    messenger: flutterEngine.binaryMessenger
  )

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    flutterEngine.run(withEntrypoint: "nativeMain")
    GeneratedPluginRegistrant.register(with: flutterEngine)
    PrismURLBridge.shared.attach()
    StoreVisitLiveActivityManager.shared.startGlobalActivityTracking()
    _ = nativeShellBridge
    _ = deviceOrientationBridge
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
