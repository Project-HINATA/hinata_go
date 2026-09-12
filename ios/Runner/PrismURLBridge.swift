import Flutter
import Foundation

final class PrismURLBridge {
  static let shared = PrismURLBridge()

  private var channel: FlutterMethodChannel?
  private var pendingURL: URL?

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "moe.neri.hinatago/prism", binaryMessenger: messenger)
    if let pendingURL {
      emit(pendingURL)
      self.pendingURL = nil
    }
  }

  func handle(_ userActivity: NSUserActivity) {
    guard let url = userActivity.webpageURL else { return }
    handle(url)
  }

  func handle(_ url: URL) {
    guard url.scheme?.lowercased() == "https",
          url.host?.lowercased() == "link.neri.moe" else {
      return
    }
    guard channel != nil else {
      pendingURL = url
      return
    }
    emit(url)
  }

  private func emit(_ url: URL) {
    channel?.invokeMethod("invocation", arguments: url.absoluteString)
  }
}
