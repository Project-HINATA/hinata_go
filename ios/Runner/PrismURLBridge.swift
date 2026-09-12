import Flutter
import Foundation

final class PrismURLBridge {
  static let shared = PrismURLBridge()

  private var channel: FlutterMethodChannel?
  private var pendingURL: URL?

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "moe.neri.hinatago/prism", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialURL" else { result(FlutterMethodNotImplemented); return }
      result(self?.pendingURL?.absoluteString)
      self?.pendingURL = nil
    }
  }

  func handle(_ userActivity: NSUserActivity) {
    guard let url = userActivity.webpageURL else { return }
    handle(url)
  }

  func handle(_ url: URL) {
    guard InvocationParser.invocation(from: url) != nil else {
      return
    }
    pendingURL = url
    guard channel != nil else { return }
    emit(url)
  }

  private func emit(_ url: URL) {
    channel?.invokeMethod("invocation", arguments: url.absoluteString)
  }
}
