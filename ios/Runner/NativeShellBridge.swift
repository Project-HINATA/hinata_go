import Flutter
import Foundation

protocol NativeShellBridgeDelegate: AnyObject {
  func nativeShell(setSelectedIndex index: Int)
  func nativeShell(setSettingsBadge visible: Bool)
  func nativeShell(setChromeVisibility tabBarVisible: Bool, dimmed: Bool)
  func nativeShell(setTabs tabs: [[String: Any]])
  func nativeShell(setActionButton config: [String: Any]?)
}

final class NativeShellBridge {
  weak var delegate: NativeShellBridgeDelegate?
  private let channel: FlutterMethodChannel
  // RunnerTests observes the notification before the platform-channel send.
  var onUserSelected: ((Int) -> Void)?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "dev.hinata.go/native_shell",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }

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
      case "setSelectedIndex":
        guard let index = args["index"] as? Int else {
          result(FlutterError(code: "invalid_args", message: nil, details: nil))
          return
        }
        self.delegate?.nativeShell(setSelectedIndex: index)
        result(nil)
      case "setSettingsBadge":
        guard let visible = args["visible"] as? Bool else {
          result(FlutterError(code: "invalid_args", message: nil, details: nil))
          return
        }
        self.delegate?.nativeShell(setSettingsBadge: visible)
        result(nil)
      case "setChromeVisibility":
        let tabBarVisible = args["tabBarVisible"] as? Bool ?? true
        let dimmed = args["dimmed"] as? Bool ?? false
        self.delegate?.nativeShell(setChromeVisibility: tabBarVisible, dimmed: dimmed)
        result(nil)
      case "setTabs":
        let tabs = args["tabs"] as? [[String: Any]] ?? []
        self.delegate?.nativeShell(setTabs: tabs)
        result(nil)
      case "setActionButton":
        let config = args["config"] as? [String: Any]
        self.delegate?.nativeShell(setActionButton: config)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func userSelected(index: Int) {
    onUserSelected?(index)
    channel.invokeMethod("selectTopLevel", arguments: ["index": index]) { response in
      NSLog("[NativeShell] Flutter selectTopLevel(%d) reply: %@", index,
        String(describing: response))
    }
  }

  func userRequested(action: String) {
    channel.invokeMethod("nativeAction", arguments: ["action": action])
  }
}
