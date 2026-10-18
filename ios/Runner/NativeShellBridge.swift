import Flutter
import Foundation

/// Native services the Flutter app calls into over `dev.hinata.go/native_shell`.
final class NativeShellBridge {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "dev.hinata.go/native_shell",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: nil, details: nil))
        return
      }

      switch call.method {
      case "openPrismURL":
        guard let value = args["url"] as? String, let url = URL(string: value),
              url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              ["link.neri.moe", "link-beta.neri.moe"].contains(url.host?.lowercased() ?? "") else {
          result(FlutterError(code: "invalid_url", message: "Invalid Prism URL", details: nil))
          return
        }
        DispatchQueue.main.async {
          PrismURLBridge.shared.handle(url)
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
