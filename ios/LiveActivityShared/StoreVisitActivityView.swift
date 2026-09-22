import SwiftUI
import WidgetKit

struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        StoreVisitHeading(context: context)
        Spacer(minLength: 12)
        StoreVisitAmount(context: context)
      }
      StoreVisitDetails(context: context)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .widgetURL(context.attributes.shopURL)
  }
}

struct StoreVisitActivityLiveConfiguration: Widget {
  static let kind = "StoreVisitActivity"

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: StoreVisitAttributes.self) { context in
      StoreVisitActivityView(context: context)
    } dynamicIsland: { context in
      let active = context.state.phase == "active"
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          StoreVisitHeading(context: context).padding(.leading, 6)
        }
        DynamicIslandExpandedRegion(.trailing) {
          StoreVisitAmount(context: context).padding(.trailing, 6)
        }
        DynamicIslandExpandedRegion(.bottom) {
          StoreVisitDetails(context: context)
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
      } compactLeading: {
        Image(systemName: active ? "storefront.fill" : "checkmark.circle.fill")
          .foregroundStyle(active ? Color.green : Color.secondary)
      } compactTrailing: {
        StoreVisitTimer(context: context, size: 13)
          .frame(maxWidth: 56, alignment: .trailing)
      } minimal: {
        Image(systemName: active ? "storefront.fill" : "checkmark.circle.fill")
          .foregroundStyle(active ? Color.green : Color.secondary)
      }
      .widgetURL(context.attributes.shopURL)
    }
  }
}

private struct StoreVisitHeading: View {
  let context: ActivityViewContext<StoreVisitAttributes>
  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: context.state.phase == "active" ? "storefront.fill" : "checkmark.circle.fill")
        .font(.title3).foregroundStyle(.green)
      VStack(alignment: .leading, spacing: 3) {
        Text(context.attributes.shopName).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(context.state.phase != "active" ? "计费已结束" : context.state.endedAtUnix == nil ? "在店计费中" : "待结账")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

private struct StoreVisitAmount: View {
  let context: ActivityViewContext<StoreVisitAttributes>
  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      if let bill = context.state.bill {
        Text(context.state.phase == "active" ? "账单金额" : "本次消费")
          .font(.caption2).foregroundStyle(.secondary)
        Text((Double(bill.amountCents) / 100).formatted(.number.precision(.fractionLength(2))))
          .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
          .lineLimit(1).minimumScaleFactor(0.7)
      } else {
        StoreVisitTimer(context: context, size: 22)
      }
    }
  }
}

private struct StoreVisitDetails: View {
  let context: ActivityViewContext<StoreVisitAttributes>
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let bill = context.state.bill, !bill.planLabel.isEmpty {
        Text(bill.planLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        if context.state.phase == "active", !context.isStale,
           let bill = context.state.bill, let next = bill.nextEvent, next.date > Date.now {
          Image(systemName: "clock").foregroundStyle(.green)
          Text(next.title).font(.caption)
          Spacer(minLength: 4)
          Text(timerInterval: Date(timeIntervalSince1970: bill.asOfUnix)...next.date, countsDown: true)
            .font(.system(.headline, design: .rounded)).monospacedDigit()
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 100, alignment: .trailing)
        } else {
          Text(context.state.phase == "active" ? "查看实时账单" : "查看结算账单").font(.caption)
          Spacer(minLength: 4)
          Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
        }
      }
      if context.state.bill != nil {
        HStack(spacing: 4) {
          Text(context.state.endedAtUnix == nil ? "已入场" : "总时长")
          StoreVisitTimer(context: context, size: 11).frame(maxWidth: 75, alignment: .leading)
          Spacer()
          if context.isStale, let bill = context.state.bill {
            Text(Date(timeIntervalSince1970: bill.asOfUnix), style: .time)
          }
        }
        .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

private struct StoreVisitTimer: View {
  let context: ActivityViewContext<StoreVisitAttributes>
  var size: CGFloat

  var body: some View {
    let start = Date(timeIntervalSince1970: context.state.startedAtUnix)
    Group {
      if let end = context.state.endedAtUnix {
        let seconds = max(0, Int(end - context.state.startedAtUnix))
        Text(String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60))
      } else {
        Text(min(Date.now, start), style: .timer)
      }
    }
    .font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
    .lineLimit(1).minimumScaleFactor(0.7)
  }
}
