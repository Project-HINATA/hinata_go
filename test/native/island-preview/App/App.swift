import SwiftUI
import ActivityKit
@main
struct PreviewApp: App {
  var body: some Scene {
    WindowGroup { PreviewControls() }
  }
}
struct PreviewControls: View {
  @State private var message = "选择状态，返回主屏幕后长按灵动岛"
  var body: some View {
    VStack(spacing: 24) {
      Text("真实 Live Activity 预览").font(.title2)
      ForEach(["billing", "capped", "paused", "long-shop"], id: \.self) { mode in
        Button(mode) { message = "启动中"; Task { await start(mode) } }.accessibilityIdentifier(mode)
      }
      Text(message).accessibilityIdentifier("result")
    }
  }
  func start(_ mode: String) async {
    for activity in Activity<StoreVisitAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    let now = Date()
    let bill = StoreVisitAttributes.Bill(amountCents: mode == "capped" ? 4800 : 2400,
      planLabel: "", asOfUnix: now.timeIntervalSince1970,
      remainingToCapCents: mode == "capped" ? 0 : 2400, billable: mode != "paused",
      nextEvent: .init(atUnix: now.addingTimeInterval(240).timeIntervalSince1970, label: mode == "billing" ? "下次计费" : "规则切换"),
      previousEvent: .init(atUnix: now.addingTimeInterval(-180).timeIntervalSince1970, label: "计费"))
    let content = StoreVisitAttributes.ContentState(phase: "active",
      startedAtUnix: now.addingTimeInterval(-4980).timeIntervalSince1970, endedAtUnix: nil, bill: bill)
    do {
      _ = try Activity.request(attributes: StoreVisitAttributes(
        sessionId: UUID().uuidString, shopCode: "preview",
        shopName: mode == "long-shop" ? "HINATA 日向街机游戏中心超长店铺名称" : "HINATA 日向",
        origin: nil), content: ActivityContent(state: content, staleDate: now.addingTimeInterval(240)), pushType: nil)
      message = "已启动"
    } catch { message = String(describing: error) }
  }
}
