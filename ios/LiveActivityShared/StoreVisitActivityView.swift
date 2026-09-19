import SwiftUI
import WidgetKit

// MARK: - Store Visit Activity View (Lock Screen & Banner)

struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  private var isActive: Bool { context.state.phase == "active" }
  private var startTimeString: String {
    let startDate = Date(timeIntervalSince1970: context.state.startedAtUnix)
    return startDate.formatted(date: .omitted, time: .shortened)
  }

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      // Left Icon Container
      ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(isActive ? Color.green.opacity(0.16) : Color.blue.opacity(0.16))
          .frame(width: 44, height: 44)

        Image(systemName: isActive ? "storefront.fill" : "checkmark.circle.fill")
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(isActive ? Color.green : Color.blue)
      }

      // Shop Information & Status Details
      VStack(alignment: .leading, spacing: 3) {
        Text(context.attributes.shopName)
          .font(.system(.headline, design: .rounded, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.85)

        HStack(spacing: 6) {
          Circle()
            .fill(isActive ? Color.green : Color.secondary)
            .frame(width: 6, height: 6)

          Text(isActive ? "在店计费中 · \(startTimeString) 入店" : "本次计费已结束")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        HStack(spacing: 3) {
          Text(isActive ? "轻点查看实时账单" : "轻点查看消费明细")
            .font(.caption2)
            .foregroundStyle(.tertiary)
          Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      // Duration / Timer Display
      VStack(alignment: .trailing, spacing: 3) {
        Text(isActive ? "已入场时长" : "总计游玩时长")
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)

        StoreVisitTimer(context: context, size: 24)
          .foregroundStyle(isActive ? Color.green : Color.primary)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .widgetURL(context.attributes.shopURL)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("\(context.attributes.shopName), \(isActive ? "在店计费中" : "计费已结束")"))
  }
}

// MARK: - Dynamic Island Configuration

struct StoreVisitActivityLiveConfiguration: Widget {
  static let kind = "StoreVisitActivity"

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: StoreVisitAttributes.self) { context in
      StoreVisitActivityView(context: context)
    } dynamicIsland: { context in
      let isActive = context.state.phase == "active"
      let startTimeString = Date(timeIntervalSince1970: context.state.startedAtUnix).formatted(date: .omitted, time: .shortened)

      return DynamicIsland {
        // Expanded: Leading Header
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 8) {
            ZStack {
              Circle()
                .fill((isActive ? Color.green : Color.blue).opacity(0.18))
                .frame(width: 28, height: 28)

              Image(systemName: isActive ? "storefront.fill" : "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? Color.green : Color.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
              Text(context.attributes.shopName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
              Text(isActive ? "入店 \(startTimeString)" : "已结算")
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
          }
          .padding(.leading, 8)
          .padding(.top, 4)
        }

        // Expanded: Trailing Header
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(isActive ? "已入场" : "总时长")
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)

            StoreVisitTimer(context: context, size: 18, alignment: .trailing)
              .foregroundStyle(isActive ? Color.green : Color.primary)
          }
          .padding(.trailing, 8)
          .padding(.top, 4)
        }

        // Expanded: Bottom Action Button
        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 6) {
            Image(systemName: isActive ? "creditcard.fill" : "receipt.fill")
              .font(.caption.weight(.medium))
              .foregroundStyle(isActive ? Color.green : Color.blue)

            Text(isActive ? "查看实时账单" : "查看结算账单")
              .font(.caption.weight(.semibold))

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
              .font(.caption2.weight(.bold))
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(
            Capsule()
              .fill(Color.white.opacity(0.12))
          )
          .padding(.horizontal, 10)
          .padding(.top, 4)
          .padding(.bottom, 6)
        }
      } compactLeading: {
        // Compact Leading: Clear storefront/checkmark symbol
        Image(systemName: isActive ? "storefront.fill" : "checkmark.circle.fill")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isActive ? Color.green : Color.blue)
          .frame(alignment: .leading)
      } compactTrailing: {
        // Compact Trailing: Clean monospaced timer constrained to avoid full status bar stretch
        StoreVisitTimer(context: context, size: 13, alignment: .trailing)
          .foregroundStyle(isActive ? Color.green : Color.secondary)
          .frame(maxWidth: 56, alignment: .trailing)
      } minimal: {
        // Minimal: Clear brand/status symbol for the detached bubble
        Image(systemName: isActive ? "storefront.fill" : "checkmark.circle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isActive ? Color.green : Color.blue)
      }
      .widgetURL(context.attributes.shopURL)
    }
  }
}

// MARK: - Shared Timer Component

private struct StoreVisitTimer: View {
  let context: ActivityViewContext<StoreVisitAttributes>
  var size: CGFloat
  var alignment: Alignment = .trailing

  var body: some View {
    let safeStart = Date(timeIntervalSince1970: context.state.startedAtUnix)
    let end = context.state.endedAtUnix.map { Date(timeIntervalSince1970: max($0, context.state.startedAtUnix)) }

    Group {
      if let end {
        Text(timerInterval: safeStart...end, countsDown: false)
      } else {
        // Clamp to now in case device clock has micro-drift behind server clock
        Text(min(Date.now, safeStart), style: .timer)
      }
    }
    .font(.system(size: size, weight: .semibold, design: .rounded))
    .monospacedDigit()
    .multilineTextAlignment(alignment == .trailing ? .trailing : (alignment == .leading ? .leading : .center))
    .lineLimit(1)
    .minimumScaleFactor(0.7)
  }
}
