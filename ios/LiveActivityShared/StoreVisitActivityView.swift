import Foundation
import SwiftUI
import WidgetKit

// MARK: - Derived display state

/// Business phase of a visit, resolved once from the pushed `phase` /
/// `endedAtUnix` pair so every surface renders the same state machine.
enum StoreVisitPhase {
  /// Inside the store and metered; the bill keeps changing.
  case billing
  /// Visit closed but unpaid: the bill is final, checkout still pending.
  case awaitingCheckout
  /// Payment confirmed; the activity lingers briefly before dismissal.
  case settled
}

/// Sub-state of `.billing` along the shop's billing-plan timeline: charges
/// accrue, the rule's price cap is reached, or the visit sits in a
/// non-billable ("非营业") segment where the amount freezes.
enum StoreVisitBillingState {
  case metering
  case capped
  case paused
}

// MARK: - Display model

/// Everything the UI renders, derived from the activity context. Views consume
/// this model instead of re-interpreting `ContentState` fields, which keeps the
/// lock screen, Dynamic Island, and compact presentations consistent. A session
/// may stack several billing plans on one timeline, so no plan or rate text is
/// rendered — only unambiguous aggregates: time in store, amount, the next
/// money-affecting instant, and cap headroom, all minute-precise.
struct StoreVisitDisplayModel {
  let phase: StoreVisitPhase
  let billingState: StoreVisitBillingState
  let isStale: Bool
  let shopName: String
  let bill: StoreVisitAttributes.Bill?
  let startedAt: Date
  let endedAt: Date?
  /// Next charge or rule switch; only shown while billing on fresh data.
  let nextEvent: (date: Date, title: String)?

  init(context: ActivityViewContext<StoreVisitAttributes>) {
    let state = context.state
    let resolvedPhase: StoreVisitPhase
    if state.phase == "active" {
      resolvedPhase = state.endedAtUnix == nil ? .billing : .awaitingCheckout
    } else {
      resolvedPhase = .settled
    }
    phase = resolvedPhase
    // Only explicit server state determines billing status; event labels are
    // presentation text and must not be used to infer pricing rules.
    if resolvedPhase == .billing, state.bill?.billable == false {
      billingState = .paused
    } else if resolvedPhase == .billing, state.bill?.remainingToCapCents == 0 {
      billingState = .capped
    } else {
      billingState = .metering
    }
    isStale = context.isStale
    shopName = context.attributes.shopName
    bill = state.bill
    startedAt = Date(timeIntervalSince1970: state.startedAtUnix)
    endedAt = state.endedAtUnix.map(Date.init(timeIntervalSince1970:))
    nextEvent = Self.resolveNextEvent(
      bill: state.bill, phase: resolvedPhase, isStale: context.isStale
    )
  }

  /// The next event to count down to, taken from the backend's pre-merged
  /// alarm timeline. Hidden while stale or once the instant has passed.
  private static func resolveNextEvent(
    bill: StoreVisitAttributes.Bill?, phase: StoreVisitPhase, isStale: Bool
  ) -> (date: Date, title: String)? {
    guard phase == .billing, !isStale, let event = bill?.nextEvent, event.atUnix.isFinite else {
      return nil
    }
    let date = Date(timeIntervalSince1970: event.atUnix)
    guard date > .now else { return nil }
    return (date, event.title)
  }

  // MARK: Colour

  /// The state colour connects status, current progress, next event and keyline.
  /// Per state: green = metering, blue =
  /// paused (non-billable segment), orange = awaiting checkout, gray = settled.
  var accent: Color {
    switch phase {
    case .billing:
      return billingState == .paused ? TimelineIslandLayout.blue : TimelineIslandLayout.green
    case .awaitingCheckout:
      return Color.orange
    case .settled:
      return Color.gray
    }
  }

  // MARK: Copy

  /// Hero amount, or nil before the first bill arrives. Decimals are dropped
  /// when the value is whole, which keeps the largest element on the surface
  /// from carrying noise.
  var heroAmountText: String? {
    guard let bill else { return nil }
    let fractionLength = bill.amountCents % 100 == 0 ? 0 : 2
    return (Decimal(bill.amountCents) / 100)
      .formatted(.number.precision(.fractionLength(fractionLength)))
  }

  /// Compact amount: decimals only when the amount has them.
  var compactAmountText: String? { heroAmountText }

  /// The event the backend last scheduled, whether or not its instant has
  /// passed. `nextEvent` deliberately goes nil the moment a countdown would
  /// reach zero, but the name and time it carried are still the most recent
  /// thing the backend said — keeping them beats an empty row, and beats
  /// inventing a state, while the next push is in flight.
  var lastScheduledEvent: (date: Date, title: String)? {
    guard let event = bill?.nextEvent, event.atUnix.isFinite else { return nil }
    return (Date(timeIntervalSince1970: event.atUnix), event.title)
  }

  /// A real previous→next event interval; snapshot timestamps are not events.
  var countdownWindow: ClosedRange<Date>? {
    guard phase == .billing, !isStale else { return nil }
    return bill?.eventInterval(startedAt: startedAt, now: .now)
  }

  var previousEventDate: Date? {
    bill?.previousEventDate(startedAt: startedAt, now: .now)
  }

  var statusText: String {
    if isStale && phase == .billing { return String(localized: "待更新") }
    switch phase {
    case .billing:
      switch billingState {
      case .metering: return String(localized: "计费中")
      case .capped: return String(localized: "本时段已封顶")
      case .paused: return String(localized: "暂停计费")
      }
    case .awaitingCheckout: return String(localized: "待结账")
    case .settled: return String(localized: "已结清")
    }
  }

  /// Minute-precision localized duration ("1小时23分" style, no seconds).
  static func minutesText(from: Date, to: Date) -> String {
    Duration.seconds(max(0, to.timeIntervalSince(from)))
      .formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
  }

  /// Time in store so far; frozen once the visit ends.
  var elapsedText: String {
    Self.minutesText(from: startedAt, to: phase == .billing ? .now : (endedAt ?? .now))
  }
}

// MARK: - Widget configuration

struct StoreVisitActivityLiveConfiguration: Widget {
  static let kind = "StoreVisitActivity"

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: StoreVisitAttributes.self) { context in
      StoreVisitActivityView(context: context)
    } dynamicIsland: { context in
      let model = StoreVisitDisplayModel(context: context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          StoreVisitCameraSideHeader {
            StoreVisitIslandStatus(model: model)
              .padding(.horizontal, TimelineIslandLayout.statusInset)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          StoreVisitCameraSideHeader {
            StoreVisitIslandAmount(model: model)
          }
        }
        // WidgetKit puts center content below the TrueDepth camera. No extra
        // top padding or offsets from the old ring layout are applied.
        DynamicIslandExpandedRegion(.center) {
          StoreVisitElapsedLabel(model: model)
            .frame(width: 220)
            .multilineTextAlignment(.center)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.gray)
            .monospacedDigit()
            .lineLimit(1)
        }
        DynamicIslandExpandedRegion(.bottom) {
          StoreVisitTimelineContent(model: model)
            .padding(.horizontal, TimelineIslandLayout.horizontalInset)
        }
      } compactLeading: {
        // The ring is concentric with the capsule's end cap: centring it in the
        // slot gives it an identical inset on its leading, top and bottom sides.
        StoreVisitCompactProgress(model: model)
      } compactTrailing: {
        if let amount = model.compactAmountText {
          Text(amount)
            .font(.system(size: TimelineIslandLayout.compactAmount, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(model.accent)
            .lineLimit(1)
        }
      } minimal: {
        // HIG asks the minimal presentation to show updating information rather
        // than a static glyph, so the amount goes in.
        Text(model.compactAmountText ?? "--")
          .font(.system(size: TimelineIslandLayout.compactAmount, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(model.accent)
          .lineLimit(1)
      }
      .keylineTint(model.accent)
      .widgetURL(context.attributes.shopURL)
    }
    .contentMarginsDisabled()
  }
}

// MARK: - Timeline island (V19)

private enum TimelineIslandLayout {
  // Center the header in WidgetKit's camera-side regions. Keep the system's
  // vertical margins, and inset the entire lower section equally on both sides.
  static let compactAmount: CGFloat = 15
  static let horizontalInset: CGFloat = 12
  // Six cap-status characters at 14 pt, plus dot, gap and two 4 pt insets.
  // Equal camera-side widths keep the full label and amount balanced.
  static let headerWidth: CGFloat = 104
  static let statusInset: CGFloat = 4
  static let footerGap: CGFloat = 4
  static let railWidth: CGFloat = 7
  static let nodeDiameter: CGFloat = 12
  static let blue = Color(red: 0.39, green: 0.71, blue: 1)
  static let history = Color(red: 0.29, green: 0.58, blue: 1)
  static let green = Color(red: 0.19, green: 0.82, blue: 0.35)
  static let track = Color(red: 0.20, green: 0.20, blue: 0.22)
}

private struct StoreVisitIslandStatus: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    ViewThatFits(in: .horizontal) {
      status(size: 14)
      status(size: 12)
      status(size: 12, usesIdealWidth: false)
    }
  }

  private func status(size: CGFloat, usesIdealWidth: Bool = true) -> some View {
    HStack(spacing: 6) {
      Circle().fill(model.accent).frame(width: 6, height: 6)
      Text(model.statusText)
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(model.accent)
        .lineLimit(1)
    }
    // Center the dot and the actual fitted glyphs as one group. Scaling only
    // the Text can leave a wider layout box with its visible text off-center.
    .fixedSize(horizontal: usesIdealWidth, vertical: true)
  }
}

private struct StoreVisitCameraSideHeader<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    GeometryReader { geometry in
      content.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
    }
    .frame(minWidth: TimelineIslandLayout.headerWidth, maxWidth: .infinity)
    .frame(height: 20)
  }
}

private struct StoreVisitIslandAmount: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    Text(model.heroAmountText.map { "¥" + $0 } ?? "—")
      .font(.system(size: 32, weight: .semibold))
      .monospacedDigit()
      .foregroundStyle(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.5)
      .frame(width: TimelineIslandLayout.headerWidth, alignment: .center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(height: 20, alignment: .top)
  }
}

private struct StoreVisitElapsedLabel: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    if model.phase != .billing {
      Text("已停留 \(model.elapsedText)")
    } else if #available(iOS 18.0, *) {
      Text("已停留 \(TimeDataSource<Date>.currentDate, format: .offset(to: model.startedAt, allowedFields: [.hour, .minute], maxFieldCount: 2, sign: .never))")
    } else {
      // iOS 17 has no live, minute-only format. Use the system timer rather
      // than presenting a frozen minute count as if it were current.
      HStack(spacing: 3) {
        Text("已停留")
        Text(model.startedAt, style: .timer)
      }
    }
  }
}

private struct StoreVisitNextEventCountdown: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    if let next = model.nextEvent {
      if #available(iOS 18.0, *) {
        Text("距下次事件还有 \(TimeDataSource<Date>.currentDate, format: .timer(countingDownIn: model.startedAt..<next.date, showsHours: false, maxFieldCount: 1, maxPrecision: .seconds(1)))")
      } else {
        HStack(spacing: 3) {
          Text("距下次事件")
          Text(timerInterval: min(model.startedAt, next.date)...next.date, countsDown: true, showsHours: false)
        }
      }
    } else if model.isStale || model.lastScheduledEvent != nil {
      Text("等待更新")
    } else {
      Text("下一事件待定")
    }
  }
}

private struct StoreVisitCompactProgress: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    Group {
      if let window = model.countdownWindow {
        // Date-relative progress must use a system style. A custom style's
        // fractionCompleted is nil and would silently draw a constant ring.
        ProgressView(timerInterval: window, countsDown: false) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
        .progressViewStyle(.circular)
        .tint(model.accent)
      } else {
        Image(systemName: model.isStale ? "clock.badge.exclamationmark" :
          model.billingState == .paused ? "pause.circle" : "clock")
          .foregroundStyle(model.accent)
      }
    }
    .frame(width: 22, height: 22)
    .accessibilityLabel(Text(model.statusText))
  }
}

private struct StoreVisitTimelineContent: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(spacing: TimelineIslandLayout.footerGap) {
      if model.phase == .billing {
        timeline
      } else {
        Text(model.phase == .settled ? "支付完成，感谢到访" : "本次费用已确定")
          .font(.system(size: 15, weight: .semibold))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
      }
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(model.shopName)
          .foregroundStyle(.gray)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
        if model.phase == .billing {
          StoreVisitNextEventCountdown(model: model)
            .multilineTextAlignment(.trailing)
            .frame(width: 174, alignment: .trailing)
            .foregroundStyle(model.isStale ? .gray : model.accent)
            .fontWeight(.semibold)
            .lineLimit(1)
            .layoutPriority(1)
        }
      }
      .font(.system(size: 13, weight: .medium))
      .monospacedDigit()
      .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var timeline: some View {
    VStack(spacing: 0) {
      columns {
        Text("入场")
        Text("上一事件")
        Text(model.lastScheduledEvent?.title ?? String(localized: "下一事件"))
          .foregroundStyle(model.isStale ? .gray : model.accent)
      }
      .font(.system(size: 14, weight: .medium))
      .foregroundStyle(TimelineIslandLayout.blue)
      .frame(height: 18, alignment: .bottom)

      StoreVisitTimelineRail(model: model)
        // V19: equal space between the labels and the times. The line and
        // every node share this row's center; neither text row is offset.
        .frame(height: 25)
        .accessibilityHidden(true)

      columns {
        Text(model.startedAt, style: .time)
        if let previous = model.previousEventDate {
          Text(previous, style: .time)
        } else {
          Text("待更新")
        }
        if let next = model.lastScheduledEvent {
          Text(next.date, style: .time)
            .foregroundStyle(model.isStale ? .gray : model.accent)
        } else {
          Text("待定").foregroundStyle(.gray)
        }
      }
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(TimelineIslandLayout.blue)
      .monospacedDigit()
      .frame(height: 20, alignment: .top)
    }
  }

  /// Three equal columns keep the previous event exactly at the island center,
  /// independent of the lengths of either endpoint label.
  private func columns<A: View, B: View, C: View>(
    @ViewBuilder content: () -> TupleView<(A, B, C)>
  ) -> some View {
    let views = content().value
    return HStack(spacing: 0) {
      views.0.frame(maxWidth: .infinity, alignment: .leading)
      views.1.frame(maxWidth: .infinity, alignment: .center)
      views.2.frame(maxWidth: .infinity, alignment: .trailing)
    }
    .lineLimit(1)
    .minimumScaleFactor(0.85)
  }
}

/// A negative-space cut, scaled with the rail, replaces the old thin slashes.
private struct StoreVisitHistoryRail: Shape {
  func path(in rect: CGRect) -> Path {
    let cut = rect.midX
    let slant: CGFloat = 4
    let gap: CGFloat = 6
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: cut - gap / 2 + slant / 2, y: rect.minY))
    path.addLine(to: CGPoint(x: cut - gap / 2 - slant / 2, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    path.move(to: CGPoint(x: cut + gap / 2 + slant / 2, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: cut + gap / 2 - slant / 2, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

private struct StoreVisitTimelineRail: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    GeometryReader { geometry in
      let radius = TimelineIslandLayout.nodeDiameter / 2
      let half = max(0, geometry.size.width / 2 - radius)
      ZStack {
        HStack(spacing: 0) {
          StoreVisitHistoryRail()
            .fill(TimelineIslandLayout.history)
            .frame(width: half, height: TimelineIslandLayout.railWidth)
          ZStack {
            Capsule().fill(TimelineIslandLayout.track)
            if let window = model.countdownWindow {
              // Native date progress keeps moving in a suspended activity.
              ProgressView(timerInterval: window, countsDown: false) {
                EmptyView()
              } currentValueLabel: {
                EmptyView()
              }
              .progressViewStyle(.linear)
              .tint(model.accent)
              .scaleEffect(x: 1, y: TimelineIslandLayout.railWidth / 4)
            }
          }
          .frame(width: half, height: TimelineIslandLayout.railWidth)
        }
        HStack {
          node(filled: true, color: TimelineIslandLayout.history)
          Spacer(minLength: 0)
          node(filled: false, color: model.isStale ? .gray : model.accent)
        }
        node(filled: model.previousEventDate != nil, color: TimelineIslandLayout.history)
        if let window = model.countdownWindow {
          StoreVisitTimelineCursor(window: window)
            .frame(width: half, height: 12)
            .offset(x: half / 2)
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
    }
  }

  private func node(filled: Bool, color: Color) -> some View {
    Circle()
      .fill(filled ? color : .black)
      .overlay {
        Circle().strokeBorder(color, lineWidth: 2)
      }
      .frame(width: TimelineIslandLayout.nodeDiameter, height: TimelineIslandLayout.nodeDiameter)
  }
}

// MARK: - Lock screen

private enum TimelineLockScreenLayout {
  static let margin: CGFloat = 14
  static let sectionGap: CGFloat = 8
  static let amountSize: CGFloat = 32
}

struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  var body: some View {
    let model = StoreVisitDisplayModel(context: context)
    VStack(spacing: TimelineLockScreenLayout.sectionGap) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          StoreVisitIslandStatus(model: model)
          StoreVisitElapsedLabel(model: model)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.gray)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 0)
        Text(model.heroAmountText.map { "¥" + $0 } ?? "—")
          .font(.system(size: TimelineLockScreenLayout.amountSize, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .frame(width: 140, alignment: .trailing)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
      }
      StoreVisitTimelineContent(model: model)
    }
    .padding(TimelineLockScreenLayout.margin)
    .activityBackgroundTint(.black)
    .activitySystemActionForegroundColor(.white)
    .widgetURL(context.attributes.shopURL)
  }
}

#if DEBUG
private enum StoreVisitTimelinePreview {
  static let attributes = StoreVisitAttributes(
    sessionId: "timeline-preview", shopCode: "preview", shopName: "晴日游戏厅",
    origin: nil)
  static let now = Date.now.timeIntervalSince1970

  static func state(billable: Bool = true, capped: Bool = false,
    includesPrevious: Bool = true) -> StoreVisitAttributes.ContentState {
    .init(phase: "active", startedAtUnix: now - 65 * 60, endedAtUnix: nil,
      bill: .init(amountCents: capped ? 10000 : 6000, planLabel: "", asOfUnix: now,
        remainingToCapCents: capped ? 0 : nil, billable: billable,
        nextEvent: .init(atUnix: now + (billable && !capped ? 12 : 48) * 60,
          label: !billable ? "恢复计费" : capped ? "规则切换" : "下次计费"),
        previousEvent: includesPrevious ? .init(atUnix: now - 18 * 60) : nil))
  }
}

#Preview("时间轴 · 锁屏", as: .content, using: StoreVisitTimelinePreview.attributes) {
  StoreVisitActivityLiveConfiguration()
} contentStates: {
  StoreVisitTimelinePreview.state()
  StoreVisitTimelinePreview.state(capped: true)
  StoreVisitTimelinePreview.state(billable: false)
  StoreVisitTimelinePreview.state(includesPrevious: false)
}

#Preview("时间轴 · 展开", as: .dynamicIsland(.expanded), using: StoreVisitTimelinePreview.attributes) {
  StoreVisitActivityLiveConfiguration()
} contentStates: {
  StoreVisitTimelinePreview.state()
  StoreVisitTimelinePreview.state(capped: true)
  StoreVisitTimelinePreview.state(billable: false)
  StoreVisitTimelinePreview.state(includesPrevious: false)
}

#Preview("时间轴 · 紧凑", as: .dynamicIsland(.compact), using: StoreVisitTimelinePreview.attributes) {
  StoreVisitActivityLiveConfiguration()
} contentStates: {
  StoreVisitTimelinePreview.state()
}
#endif

/// Both masks share the rail's system clock. Their overlap isolates the live
/// leading edge without a local Timer or a frozen fractionCompleted snapshot.
private struct StoreVisitTimelineCursor: View {
  let window: ClosedRange<Date>
  var body: some View {
    GeometryReader { geo in
      Rectangle().fill(.white)
        .mask { mask(width: geo.size.width, reverse: false).offset(x: 6) }
        .mask { mask(width: geo.size.width, reverse: true).offset(x: -6) }
        .clipShape(Capsule())
    }
  }
  private func mask(width: CGFloat, reverse: Bool) -> some View {
    ProgressView(timerInterval: window, countsDown: reverse) {
      EmptyView()
    } currentValueLabel: {
      EmptyView()
    }
    .progressViewStyle(.linear)
    .tint(.white)
    .frame(width: width / 3)
    .scaleEffect(x: reverse ? -3 : 3, y: 3)
    .frame(width: width)
    .frame(height: 12)
    .background { Rectangle().fill(.black).frame(width: width + 48, height: 40) }
    .compositingGroup()
    .contrast(100)
    .luminanceToAlpha()
  }
}
