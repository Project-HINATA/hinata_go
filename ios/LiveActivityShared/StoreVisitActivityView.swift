import SwiftUI
import WidgetKit

struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  private var start: Date { Date(timeIntervalSince1970: context.state.startedAtUnix) }
  private var end: Date? {
    guard let value = context.state.endedAtUnix else { return nil }
    return Date(timeIntervalSince1970: value)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(context.attributes.shopName).font(.headline)
      Text(context.state.phase == "active" ? "在店计费中" : "本次计费已结束")
        .font(.subheadline)
      if let end {
        Text(timerInterval: start...end, countsDown: false, showsHours: true)
          .monospacedDigit()
      } else {
        Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: true)
          .monospacedDigit()
      }
    }
    .padding()
    .activityBackgroundTint(.black)
    .activitySystemActionForegroundColor(.white)
  }
}

struct StoreVisitActivityLiveConfiguration: Widget {
  static let kind = "StoreVisitActivity"

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: StoreVisitAttributes.self) { context in
      StoreVisitActivityView(context: context)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.shopName).font(.headline)
        }
        DynamicIslandExpandedRegion(.trailing) {
          StoreVisitTimer(context: context)
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.phase == "active" ? "在店计费中" : "本次计费已结束")
        }
      } compactLeading: {
        Image(systemName: "clock")
      } compactTrailing: {
        StoreVisitTimer(context: context)
      } minimal: {
        Image(systemName: "clock")
      }
    }
  }
}

private struct StoreVisitTimer: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  var body: some View {
    let start = Date(timeIntervalSince1970: context.state.startedAtUnix)
    if let endedAtUnix = context.state.endedAtUnix {
      Text(timerInterval: start...Date(timeIntervalSince1970: endedAtUnix), countsDown: false)
    } else {
      Text(timerInterval: start...Date.distantFuture, countsDown: false)
    }
  }
}
