import SwiftUI
// NSUserActivityTypeLiveActivity lives in WidgetKit, not UIKit.
import WidgetKit

@main
struct PrismClipApp: App {
  @Environment(\.scenePhase) private var scenePhase
  @StateObject private var model = MachineLoginViewModel()

  var body: some Scene {
    WindowGroup {
      MachineLoginView(presentsAppClipNotice: true)
        .environmentObject(model)
        .task {
          #if DEBUG
          if let url = ProcessInfo.processInfo.environment["PRISM_PREVIEW_DEVICE_URL"].flatMap(URL.init(string:)) { await model.handleInvocation(url) }
          #endif
        }
        .onChange(of: scenePhase) { phase in
          Task { await model.setSceneActive(phase == .active) }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          guard let url = activity.webpageURL else { return }
          Task { await model.handleInvocation(url) }
        }
        // A Live Activity tap with no URL of its own: reuse the link that activity started for.
        .onContinueUserActivity(NSUserActivityTypeLiveActivity) { _ in
          guard let stored = UserDefaults.standard.string(forKey: StoreVisitLiveActivityManager.lastLinkKey),
                let url = URL(string: stored) else { return }
          Task { await model.handleInvocation(url) }
        }
        .onOpenURL { url in
          Task { await model.handleInvocation(url) }
        }
    }
  }
}
