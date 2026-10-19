import Flutter
import Foundation
import UIKit

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

/// Reports which screen edge carries the device's NFC antenna.
///
/// Most phones put the NFC antenna at the top, next to the front camera, so
/// the edge is the side the device's top points to. The window scene's
/// landscape value tracks that side on the tested runtime, while
/// `UIDevice.orientation` is unreliable on the Duo (it reports portrait while
/// the window is landscape). Safe-area insets are not used either: iPhones
/// keep symmetric landscape insets, and the Duo's vertical bar makes the
/// right side look like the top.
final class DeviceOrientationBridge {
  static let channelName = "moe.neri.hinatago/device_orientation"
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getDeviceTopOnRight":
        result(Self.currentDeviceTopOnRight())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// True when the device's top edge is on the right. Nil in portrait or when
  /// no window scene has connected yet.
  static func currentDeviceTopOnRight() -> Bool? {
    let scenes = UIApplication.shared.connectedScenes.compactMap {
      $0 as? UIWindowScene
    }
    let scene =
      scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    let result: Bool?
    switch scene?.interfaceOrientation {
    case .landscapeLeft:
      // The interface turned left, so the device's top edge is on the right.
      result = true
    case .landscapeRight:
      result = false
    default:
      result = nil
    }
    return result
  }

  func deviceTopOnRightChanged() {
    channel.invokeMethod(
      "deviceTopOnRightChanged",
      arguments: Self.currentDeviceTopOnRight()
    )
  }
}
