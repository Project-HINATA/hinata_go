import Flutter
import Foundation

protocol NativeShellBridgeDelegate: AnyObject {
  func nativeShell(setSelectedIndex index: Int)
  func nativeShell(setSettingsBadge visible: Bool)
  func nativeShell(setScaffoldCovered covered: Bool)
  func nativeShell(setLocalizedStrings strings: [String: String])
}

final class NativeShellBridge {
  weak var delegate: NativeShellBridgeDelegate?
  private let channel: FlutterMethodChannel

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
      case "setScaffoldCovered":
        guard let covered = args["covered"] as? Bool else {
          result(FlutterError(code: "invalid_args", message: nil, details: nil))
          return
        }
        self.delegate?.nativeShell(setScaffoldCovered: covered)
        result(nil)
      case "setLocalizedStrings":
        let strings = args.compactMapValues { $0 as? String }
        self.delegate?.nativeShell(setLocalizedStrings: strings)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func userSelected(index: Int) {
    channel.invokeMethod("selectTopLevel", arguments: ["index": index])
  }

  func userRequested(action: String) {
    channel.invokeMethod("nativeAction", arguments: ["action": action])
  }
}
