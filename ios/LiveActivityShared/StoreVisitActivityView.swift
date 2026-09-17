import SwiftUI
import WidgetKit

// iOS-native minimal presentation. The previous version pinned a black background
// (`.activityBackgroundTint(.black)`), which looked wrong in light mode and fought the
// system lock-screen material; the system now supplies the background, so the activity
// tracks light and dark automatically.
struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  private var isActive: Bool { context.state.phase == "active" }
  private var statusText: LocalizedStringKey { isActive ? "在店计费中" : "本次计费已结束" }

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          StatusDot(isActive: isActive)
          Text(context.attributes.shopName)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        Text(statusText)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("轻点查看账单")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      StoreVisitTimer(context: context, size: 30)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .widgetURL(context.attributes.shopURL)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(context.attributes.shopName))
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
          HStack(spacing: 6) {
            StatusDot(isActive: context.state.phase == "active")
            Text(context.attributes.shopName)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          StoreVisitTimer(context: context, size: 22)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 6) {
            Text(context.state.phase == "active" ? "在店计费中" : "本次计费已结束")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("轻点查看账单")
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
        }
      } compactLeading: {
        StatusDot(isActive: context.state.phase == "active")
      } compactTrailing: {
        StoreVisitTimer(context: context, size: 15)
      } minimal: {
        StatusDot(isActive: context.state.phase == "active")
      }
      .keylineTint(context.state.phase == "active" ? .green : .secondary)
      .widgetURL(context.attributes.shopURL)
    }
  }
}

private struct StatusDot: View {
  let isActive: Bool

  var body: some View {
    Circle()
      .fill(isActive ? Color.green : Color.secondary)
      .frame(width: 8, height: 8)
      .accessibilityHidden(true)
  }
}

private struct StoreVisitTimer: View {
  let context: ActivityViewContext<StoreVisitAttributes>
  var size: CGFloat

  var body: some View {
    let start = Date(timeIntervalSince1970: context.state.startedAtUnix)
    let end = context.state.endedAtUnix.map { Date(timeIntervalSince1970: $0) }
    Group {
      if let end {
        Text(timerInterval: start...end, countsDown: false)
      } else {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
      }
    }
    .font(.system(size: size, weight: .semibold, design: .rounded))
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.6)
  }
}
