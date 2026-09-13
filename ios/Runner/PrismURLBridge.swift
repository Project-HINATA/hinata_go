import Foundation
import SwiftUI
import UIKit

@MainActor
final class PrismURLBridge {
  static let shared = PrismURLBridge()
  private var ready = false
  private var pendingURL: URL?
  private var nativeModel: MachineLoginViewModel?
  private var nativeController: UIViewController?
  private init() {}

  func attach() {
    ready = true
    if let url = pendingURL { presentNative(url) }
  }

  func handle(_ userActivity: NSUserActivity) {
    guard let url = userActivity.webpageURL else { return }
    handle(url)
  }

  func handle(_ url: URL) {
    guard InvocationParser.invocation(from: url) != nil else { return }
    pendingURL = url
    if ready { presentNative(url) }
  }

  private func presentNative(_ url: URL) {
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    if nativeController?.presentingViewController != nil { nativeController?.dismiss(animated: false) }
    let model = MachineLoginViewModel()
    nativeModel = model
    let controller = UIHostingController(rootView: MachineLoginView(allowsDismiss: true).environmentObject(model))
    controller.modalPresentationStyle = .pageSheet
    if let sheet = controller.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
    }
    nativeController = controller
    presenter.present(controller, animated: true) {
      Task { await model.handleInvocation(url); self.pendingURL = nil }
    }
  }
}
