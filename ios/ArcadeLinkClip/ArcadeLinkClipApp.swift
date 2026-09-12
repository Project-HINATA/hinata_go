import SwiftUI

@main
struct ArcadeLinkClipApp: App {
  @StateObject private var model = MachineLoginViewModel()

  var body: some Scene {
    WindowGroup {
      MachineLoginView()
        .environmentObject(model)
        .task {
          #if DEBUG
          if let url = ProcessInfo.processInfo.environment["PRISM_PREVIEW_DEVICE_URL"].flatMap(URL.init(string:)) { await model.handleInvocation(url) }
          #endif
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
          guard let url = activity.webpageURL else { return }
          Task { await model.handleInvocation(url) }
        }
        .onOpenURL { url in
          Task { await model.handleInvocation(url) }
        }
    }
  }
}
