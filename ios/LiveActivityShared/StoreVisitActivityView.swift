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

// MARK: - Layout metrics

/// Legacy lock-screen metrics; expanded island metrics are defined separately.
private enum IslandLayout {
  /// The design's inset from the island's edges, shared by all four sides — and
  /// by the ring's top padding, so the ring is inset the same amount on its top
  /// and leading sides.
  static let margin: CGFloat = 24

  /// One ring diameter per phase; the ring grows and shrinks with the island.
  static let ringBilling: CGFloat = 68
  static let ringAwaiting: CGFloat = 62
  static let ringSettled: CGFloat = 56
  static let ringLineWidth: CGFloat = 6.5

  /// Breathing room between the upper band and the footer row, on top of the
  /// spacing the system inserts between regions. HIG likes the two groups read
  /// separately — "what is happening now" above, "this visit" below — and the
  /// expanded island is hard-capped at 160pt, so this stays modest.
  static let bandGap: CGFloat = 8

  // Type. Fixed points rather than semantic styles: the island is a fixed
  // canvas and the sheet is drawn in points.
  static let amount: CGFloat = 40
  static let amountCompact: CGFloat = 36
  static let amountSettled: CGFloat = 34
  static let amountCaption: CGFloat = 20
  static let amountCaptionCompact: CGFloat = 18
  static let amountCaptionSettled: CGFloat = 17
  static let amountGap: CGFloat = 9

  static let eventName: CGFloat = 18
  static let eventNameSettled: CGFloat = 17
  static let eventTime: CGFloat = 24
  static let eventTimeCompact: CGFloat = 22
  static let eventSpacing: CGFloat = 10

  /// Sized for the timer form ("24:37") the ring actually holds, not the word
  /// form it was originally drawn with.
  static let ringLabel: CGFloat = 17
  static let ringLabelCompact: CGFloat = 15

  static let cap: CGFloat = 17
  static let capBarWidth: CGFloat = 19
  static let capBarHeight: CGFloat = 7
  static let capGap: CGFloat = 5

  static let shopName: CGFloat = 17
  static let elapsed: CGFloat = 17
  static let entry: CGFloat = 15
  static let glyphGap: CGFloat = 5

  static let compactRing: CGFloat = 22
  /// The compact ring is smaller, so the sheet strokes it thinner (22pt ring,
  /// 3pt stroke) -- the expanded width would read as a solid disc.
  static let compactRingLineWidth: CGFloat = 3
  static let compactAmount: CGFloat = 15
  static let minimalAmount: CGFloat = 15

  /// Fixed amber for anything about the remaining allowance. Deliberately not
  /// the state colour, so the cap cluster reads as its own kind of fact instead
  /// of competing with the state ring.
  static let allowance = Color(red: 1.0, green: 0.69, blue: 0.13) // #FFB020
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

  /// The state colour. It covers the "now" cluster — ring, the minutes nested
  /// inside it, the instant the ring is counting down to, and the keyline — so
  /// those four read as one statement. Per state: green = metering, blue =
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

  /// Only billing states count down to something, so only they tint the event
  /// instant. Awaiting / settled have no target and stay neutral.
  var eventTimeColor: Color {
    phase == .billing ? accent : .primary
  }

  // MARK: Sized geometry

  var ringDiameter: CGFloat {
    switch phase {
    case .billing: return IslandLayout.ringBilling
    case .awaitingCheckout: return IslandLayout.ringAwaiting
    case .settled: return IslandLayout.ringSettled
    }
  }

  /// The upper band's columns all bottom out on one line, so the whole band is
  /// exactly as tall as the ring.
  var upperBandHeight: CGFloat { ringDiameter }

  var amountSize: CGFloat {
    switch phase {
    case .billing: return IslandLayout.amount
    case .awaitingCheckout: return IslandLayout.amountCompact
    case .settled: return IslandLayout.amountSettled
    }
  }

  var amountCaptionSize: CGFloat {
    switch phase {
    case .billing: return IslandLayout.amountCaption
    case .awaitingCheckout: return IslandLayout.amountCaptionCompact
    case .settled: return IslandLayout.amountCaptionSettled
    }
  }

  var eventNameSize: CGFloat {
    phase == .settled ? IslandLayout.eventNameSettled : IslandLayout.eventName
  }

  var eventTimeSize: CGFloat {
    phase == .billing ? IslandLayout.eventTime : IslandLayout.eventTimeCompact
  }

  var ringLabelSize: CGFloat {
    phase == .billing ? IslandLayout.ringLabel : IslandLayout.ringLabelCompact
  }

  // MARK: Copy

  /// "计价 / 应付 / 结算" — the one-word caption that says what the hero number
  /// is, sitting on the amount's baseline to its left.
  var amountCaption: String {
    switch phase {
    case .billing: return String(localized: "计价")
    case .awaitingCheckout: return String(localized: "应付")
    case .settled: return String(localized: "结算")
    }
  }

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

  /// Exact decimal rendering of integer cents, shared by every amount shown.
  static func centsText(_ cents: Int) -> String {
    (Decimal(cents) / 100).formatted(.number.precision(.fractionLength(2)))
  }

  /// Ring centre while a countdown is running: the minutes left until the next
  /// money-affecting instant. States without a countdown fall back to a two
  /// character word instead.
  var ringStateWord: String? {
    guard nextEvent == nil else { return nil }
    switch phase {
    case .billing:
      switch billingState {
      case .capped: return String(localized: "封顶")
      case .paused: return String(localized: "暂停")
      // Metering with nothing to count: either a plan with no next boundary,
      // or an update that has not landed yet. Saying "计费中" is the truth in
      // both cases; a countdown stuck at zero would not be.
      case .metering: return String(localized: "计费中")
      }
    case .awaitingCheckout: return String(localized: "待付")
    case .settled: return String(localized: "已付")
    }
  }

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

  /// How full a static ring is drawn. Only used when there is no live
  /// countdown; per state: metering is full, paused is a little under half,
  /// capped and the terminal states are full.
  var staticRingFraction: Double {
    switch phase {
    case .billing: return billingState == .paused ? 0.45 : 1.0
    case .awaitingCheckout, .settled: return 1.0
    }
  }

  /// Cap headroom line: the amber cluster. Nil when the visit is not billing,
  /// in which case the trailing column carries a plain status line instead.
  var capRow: (text: String, fraction: Double)? {
    guard phase == .billing, !isStale else { return nil }
    if billingState == .capped { return (String(localized: "已达上限"), 0) }
    if billingState == .paused { return (String(localized: "非营业时段"), 0.45) }
    guard let remaining = bill?.remainingToCapCents, remaining > 0 else { return nil }
    // 100.00 of headroom is the fullest bar the sheet draws; below that the
    // width tracks the value so the bar reads as a proportion.
    let fraction = min(1.0, Double(remaining) / 10_000)
    return (Self.centsText(remaining), fraction)
  }

  /// Status line for the trailing column when there is no cap headroom to show.
  var trailingStatusText: String {
    switch phase {
    case .billing: return ""
    case .awaitingCheckout: return String(localized: "已结束计费")
    case .settled: return String(localized: "已完成计费")
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

  /// Where the visit began, as a wall-clock time.
  var entryText: String {
    startedAt.formatted(date: .omitted, time: .shortened)
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
          StoreVisitIslandStatus(model: model)
            .padding(.horizontal, TimelineIslandLayout.statusInset)
            .frame(minWidth: TimelineIslandLayout.headerWidth, maxWidth: .infinity, alignment: .center)
        }
        DynamicIslandExpandedRegion(.trailing) {
          StoreVisitIslandAmount(model: model)
            .frame(minWidth: TimelineIslandLayout.headerWidth, maxWidth: .infinity, alignment: .center)
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
            .font(.system(size: IslandLayout.compactAmount, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(model.accent)
            .lineLimit(1)
        }
      } minimal: {
        // HIG asks the minimal presentation to show updating information rather
        // than a static glyph, so the amount goes in.
        Text(model.compactAmountText ?? "--")
          .font(.system(size: IslandLayout.minimalAmount, weight: .semibold))
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
  static let horizontalInset: CGFloat = 12
  static let headerWidth: CGFloat = 92
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
    HStack(spacing: 6) {
      Circle().fill(model.accent).frame(width: 6, height: 6)
      Text(model.statusText)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(model.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }
    .fixedSize(horizontal: false, vertical: true)
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

struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  var body: some View {
    let model = StoreVisitDisplayModel(context: context)
    VStack(spacing: IslandLayout.bandGap) {
      HStack(alignment: .bottom, spacing: 16) {
        StoreVisitRing(model: model)
          .frame(height: model.upperBandHeight, alignment: .top)
        StoreVisitEventBlock(model: model)
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: IslandLayout.eventSpacing) {
          StoreVisitAmountLine(model: model)
          StoreVisitCapRow(model: model)
        }
      }
      StoreVisitVisitRow(model: model)
    }
    // Not a Dynamic Island region, so there is no system inset to subtract.
    .padding(IslandLayout.margin)
    .widgetURL(context.attributes.shopURL)
  }
}

// MARK: - Upper band

/// The state ring, with the minutes left nested in its centre. A live countdown
/// uses `ProgressView(timerInterval:)` so it keeps sweeping without a push; the
/// states without a target draw a static ring at their own fraction.
private struct StoreVisitRing: View {
  let model: StoreVisitDisplayModel
  var diameter: CGFloat?
  var showsLabel: Bool = true

  private var side: CGFloat { diameter ?? model.ringDiameter }

  /// The compact slot draws the ring small, so it takes the sheet's thinner
  /// stroke; every other call site is the expanded ring.
  private var strokeWidth: CGFloat {
    diameter == nil ? IslandLayout.ringLineWidth : IslandLayout.compactRingLineWidth
  }

  var body: some View {
    ZStack {
      if let window = model.countdownWindow {
        ProgressView(timerInterval: window, countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          centerLabel
        }
        .progressViewStyle(.circular)
        .tint(model.accent)
      } else {
        Circle()
          .stroke(Color.white.opacity(0.14), lineWidth: strokeWidth)
        Circle()
          .trim(from: 0, to: model.staticRingFraction)
          .stroke(model.accent, style: StrokeStyle(
            lineWidth: strokeWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
        centerLabel
      }
    }
    .frame(width: side, height: side)
  }

  @ViewBuilder private var centerLabel: some View {
    if !showsLabel {
      EmptyView()
    } else if let window = model.countdownWindow {
      // Real time, and the only self-updating form that fits the ring: the
      // timer counts down with no backend push. `showsHours: false` keeps it to
      // mm:ss -- a five hour countdown would otherwise read "5:47:15", wider
      // than the ring's inner circle, so it shows total minutes instead.
      //
      // The sheet asked for one rounded unit ("4分"), which no self-updating
      // primitive can render; that version was a snapshot of the last push and
      // was dropped in favour of this.
      Text(timerInterval: window, countsDown: true, showsHours: false)
        .font(.system(size: model.ringLabelSize, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(model.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    } else if let word = model.ringStateWord {
      Text(word)
        .font(.system(size: model.ringLabelSize, weight: .semibold))
        .foregroundStyle(model.accent)
        .lineLimit(1)
    }
  }
}

/// The event column: what happens next, and when. The name is supporting type
/// above the instant, which carries the state colour while a countdown is live
/// so it reads as the target the ring is sweeping toward.
private struct StoreVisitEventBlock: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(alignment: .leading, spacing: IslandLayout.eventSpacing) {
      Text(eventName)
        .font(.system(size: model.eventNameSize, weight: .regular))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      if let next = model.nextEvent {
        Text(next.date, style: .time)
          .font(.system(size: model.eventTimeSize, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(model.eventTimeColor)
          .lineLimit(1)
      } else if let scheduled = model.lastScheduledEvent {
        // Last known instant, held steady and left neutral until the update
        // lands: it is no longer a target, so it must not wear the state colour.
        Text(scheduled.date, style: .time)
          .font(.system(size: model.eventTimeSize, weight: .semibold))
          .monospacedDigit()
          .foregroundStyle(.primary)
          .lineLimit(1)
      } else if !model.trailingStatusText.isEmpty {
        Text(model.trailingStatusText)
          .font(.system(size: model.eventTimeSize, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
    }
    .lineLimit(1)
  }

  private var eventName: String {
    if let next = model.nextEvent { return next.title }
    // The countdown expired but the push has not arrived: keep naming the event
    // the backend last scheduled rather than promoting it to a state. Only an
    // explicit `.paused` may say billing stopped.
    if let scheduled = model.lastScheduledEvent { return scheduled.title }
    switch model.phase {
    case .billing:
      switch model.billingState {
      case .capped: return String(localized: "本时段已封顶")
      case .paused: return String(localized: "暂停计费")
      case .metering: return String(localized: "计费中")
      }
    case .awaitingCheckout: return String(localized: "待支付")
    case .settled: return String(localized: "已结算")
    }
  }
}

/// The hero: a one-word caption and the amount on a shared baseline, so the
/// caption sits to the left of the number rather than above or below it.
private struct StoreVisitAmountLine: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: IslandLayout.amountGap) {
      Text(model.amountCaption)
        .font(.system(size: model.amountCaptionSize, weight: .regular))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
      Text(model.heroAmountText ?? "--")
        .font(.system(size: model.amountSize, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .lineLimit(1)
        // Shrinks rather than truncating: a four-figure bill at 40pt would
        // otherwise push past the island's 371pt width.
        .minimumScaleFactor(0.6)
    }
    .layoutPriority(1)
  }
}

/// The allowance cluster: a proportion bar plus the exact headroom, both in the
/// fixed amber so they read as their own kind of fact. A bar beats an icon here
/// because it carries the quantity, not just the concept.
private struct StoreVisitCapRow: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    if let cap = model.capRow {
      HStack(alignment: .center, spacing: IslandLayout.capGap) {
        allowanceBar(fraction: cap.fraction)
        Text(cap.text)
          .font(.system(size: IslandLayout.cap, weight: .regular))
          .monospacedDigit()
          .foregroundStyle(IslandLayout.allowance)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
    } else if !model.trailingStatusText.isEmpty {
      Text(model.trailingStatusText)
        .font(.system(size: IslandLayout.cap, weight: .regular))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }

  private func allowanceBar(fraction: Double) -> some View {
    Capsule(style: .continuous)
      .fill(Color.white.opacity(0.18))
      .frame(width: IslandLayout.capBarWidth, height: IslandLayout.capBarHeight)
      .overlay(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(IslandLayout.allowance)
          .frame(
            width: fraction <= 0
              ? 0 : max(IslandLayout.capBarHeight, IslandLayout.capBarWidth * fraction),
            height: IslandLayout.capBarHeight
          )
      }
  }
}

// MARK: - Lower band

/// One line for the visit: where, when it started, how long it has run. The
/// three are peers, so they share a baseline and are separated by size alone —
/// the shop name and the elapsed time at full weight, the entry time a step
/// down. Both times carry a glyph because a bare `11:55` next to a duration
/// gives no clue which is which.
private struct StoreVisitVisitRow: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(model.shopName)
        .font(.system(size: IslandLayout.shopName, weight: .regular))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 8)
      if model.isStale, let asOfUnix = model.bill?.asOfUnix {
        Text("数据更新于")
          .font(.system(size: IslandLayout.entry, weight: .regular))
          .foregroundStyle(.secondary)
        Text(Date(timeIntervalSince1970: asOfUnix), style: .time)
          .font(.system(size: IslandLayout.entry, weight: .regular))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      } else {
        glyphLine(systemName: "figure.walk.arrival", text: model.entryText,
                  size: IslandLayout.entry)
        glyphLine(systemName: "timer", text: model.elapsedText,
                  size: IslandLayout.elapsed)
      }
    }
  }

  private func glyphLine(systemName: String, text: String, size: CGFloat) -> some View {
    HStack(spacing: IslandLayout.glyphGap) {
      Image(systemName: systemName)
        .font(.system(size: size, weight: .regular))
      Text(text)
        .font(.system(size: size, weight: .regular))
        .monospacedDigit()
    }
    .foregroundStyle(.secondary)
    .lineLimit(1)
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
