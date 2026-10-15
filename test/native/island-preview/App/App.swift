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
      ForEach(["billing", "capped", "paused", "long-shop", "large-amount",
        "stale", "missing-previous", "awaiting-checkout", "settled", "preloaded"], id: \.self) { mode in
        Button(mode) { message = "启动中"; Task { await start(mode) } }.accessibilityIdentifier(mode)
      }
      Text(message).accessibilityIdentifier("result")
      Button("settle-preloaded") { Task { await settlePreloaded() } }
        .accessibilityIdentifier("settle-preloaded")
    }
  }
  func settlePreloaded() async {
    message = "结账中"
    for activity in Activity<StoreVisitAttributes>.activities {
      // Keep the old forecast deliberately: a final phase must override it.
      var state = activity.content.state
      state = .init(phase: "ended", startedAtUnix: state.startedAtUnix,
        endedAtUnix: Date().timeIntervalSince1970,
        bill: .init(amountCents: 2500, planLabel: "", asOfUnix: Date().timeIntervalSince1970),
        nextBill: state.nextBill)
      await activity.end(ActivityContent(state: state, staleDate: nil),
        dismissalPolicy: .after(Date().addingTimeInterval(60)))
    }
    message = "已结清"
  }
  func start(_ mode: String) async {
    for activity in Activity<StoreVisitAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    let now = Date()
    let terminal = mode == "awaiting-checkout" || mode == "settled"
    let boundary = now.addingTimeInterval(mode == "preloaded" ? 120 : 240)
    let bill = StoreVisitAttributes.Bill(amountCents: mode == "large-amount" ? 123456 : mode == "capped" ? 4800 : 2400,
      planLabel: "", asOfUnix: now.timeIntervalSince1970,
      remainingToCapCents: mode == "capped" ? 0 : 2400, billable: mode != "paused",
      nextEvent: terminal ? nil : .init(atUnix: boundary.timeIntervalSince1970,
        label: mode == "paused" ? "恢复计费" : mode == "capped" ? "规则切换" : "下次计费"),
      previousEvent: mode == "missing-previous" ? nil : .init(atUnix: now.addingTimeInterval(-180).timeIntervalSince1970, label: "计费"))
    let nextBill: StoreVisitAttributes.Bill? = mode == "preloaded" ? .init(
      amountCents: 2600, planLabel: "", asOfUnix: boundary.timeIntervalSince1970,
      remainingToCapCents: 2200, billable: true,
      nextEvent: .init(atUnix: boundary.addingTimeInterval(120).timeIntervalSince1970, label: "下次计费"),
      previousEvent: .init(atUnix: boundary.timeIntervalSince1970, label: "计费")) : nil
    let content = StoreVisitAttributes.ContentState(phase: mode == "settled" ? "settled" : "active",
      startedAtUnix: now.addingTimeInterval(-4980).timeIntervalSince1970,
      endedAtUnix: terminal ? now.addingTimeInterval(-120).timeIntervalSince1970 : nil, bill: bill, nextBill: nextBill)
    do {
      let activity = try Activity.request(attributes: StoreVisitAttributes(
        sessionId: UUID().uuidString, shopCode: "preview",
        shopName: mode == "long-shop" ? "HINATA 日向街机游戏中心超长店铺名称" : "HINATA 日向",
        origin: nil), content: ActivityContent(state: content,
          staleDate: mode == "stale" ? now.addingTimeInterval(60)
            : Date(timeIntervalSince1970: ceil(boundary.timeIntervalSince1970))), pushType: nil)
      message = "已启动 \(mode) \(activity.id)"
    } catch { message = String(describing: error) }
  }
}
