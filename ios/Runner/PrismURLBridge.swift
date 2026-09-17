import Foundation
import SwiftUI
import UIKit
// NSUserActivityTypeLiveActivity lives in WidgetKit, not UIKit.
import WidgetKit

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
    presentPending()
  }

  func handle(_ userActivity: NSUserActivity) {
    if let url = userActivity.webpageURL {
      handle(url)
      return
    }
    // NSUserActivityTypeLiveActivity: a Live Activity tap with no URL of its own. Reuse the
    // link that activity was started for instead of dropping the tap.
    if userActivity.activityType == NSUserActivityTypeLiveActivity,
       let stored = UserDefaults.standard.string(forKey: StoreVisitLiveActivityManager.lastLinkKey),
       let url = URL(string: stored) {
      handle(url)
    }
  }

  func handle(_ url: URL) {
    // Either a machine link (`/t/{shop}/{machine}`) or the shop-only link (`/t/{shop}`)
    // that a Live Activity tap produces.
    guard InvocationParser.invocation(from: url) != nil
      || InvocationParser.shopInvocation(from: url) != nil else { return }
    pendingURL = url
    presentPending()
  }

  /// Presents the pending link, or steers the sheet that is already open. A cold launch
  /// reaches here from `scene(_:willConnectTo:)`, before the window is on screen, so the
  /// presentation is deferred until a presenter actually exists.
  private func presentPending(attempt: Int = 0) {
    guard ready, let url = pendingURL else { return }
    // An open sheet keeps its model: steering it avoids dismissing and re-presenting, which
    // races with the window becoming visible and flashes the page.
    if let model = nativeModel, nativeController?.presentingViewController != nil {
      pendingURL = nil
      Task { await model.handleInvocation(url) }
      return
    }
    guard let presenter = topPresenter() else {
      // The window is not in the hierarchy yet. Retry briefly rather than dropping the link.
      guard attempt < 20 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.presentPending(attempt: attempt + 1)
      }
      return
    }
    let model = MachineLoginViewModel()
    nativeModel = model
    let controller = UIHostingController(rootView: MachineLoginView(allowsDismiss: true).environmentObject(model))
    controller.modalPresentationStyle = .pageSheet
    // The sheet carries an in-progress machine session, so a stray swipe must not take it down.
    // Closing stays available through the toolbar button, which calls `dismiss()`.
    controller.isModalInPresentation = true
    if let sheet = controller.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = false
    }
    nativeController = controller
    pendingURL = nil
    presenter.present(controller, animated: true) {
      Task { await model.handleInvocation(url) }
    }
  }

  private func topPresenter() -> UIViewController? {
    guard let root = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else { return nil }
    var presenter = root
    while let presented = presenter.presentedViewController { presenter = presented }
    return presenter
  }
}
