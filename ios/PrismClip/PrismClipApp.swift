import SwiftUI
// NSUserActivityTypeLiveActivity lives in WidgetKit, not UIKit.
import WidgetKit

@main
struct PrismClipApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = MachineLoginViewModel()
  /// Not observable: it only ranks deliveries, and the page itself is driven by `model`.
  private let router = InvocationRouter()

  var body: some Scene {
    WindowGroup {
      MachineLoginView(presentsAppClipNotice: true)
        .environmentObject(model)
        .task {
          #if DEBUG
          if let url = ProcessInfo.processInfo.environment["PRISM_PREVIEW_DEVICE_URL"].flatMap(URL.init(string:)) {
            await router.handle(url, source: .explicitOpenURL, model: model)
          }
          #endif
        }
        .onChange(of: scenePhase) { phase in
          // Only a real background ends the activation. Resetting on `.inactive` would clear the
          // ranking part-way through an ordinary transition and let a replay win.
          if phase == .background { router.resetForNextActivation() }
          Task { await model.setSceneActive(phase == .active) }
        }
        // The App Clip invocation, replayed by the system whenever the clip is reactivated. It
        // carries the URL the clip was originally opened with, so it can be stale.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          guard let url = activity.webpageURL else { return }
          Task { await router.handle(url, source: .appClipInvocation, model: model) }
        }
        // A Live Activity tap whose activity carries no URL of its own: reuse the link it was
        // started for. That link is as current as an explicit open, so it ranks the same.
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
          guard let stored = UserDefaults.standard.string(forKey: StoreVisitLiveActivityManager.lastLinkKey),
                let url = URL(string: stored) else { return }
          Task { await router.handle(url, source: .liveActivity, model: model) }
        }
        // A URL the player opened just now. A Live Activity with a widgetURL arrives here.
        .onOpenURL { url in
          Task { await router.handle(url, source: .explicitOpenURL, model: model) }
        }
    }
  }
}
