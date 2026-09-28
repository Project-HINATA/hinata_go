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

/// Geometry and type scale for the expanded island.
///
/// Mirrors `dynamic-island-preview.svg` (rev 15), which follows Apple's
/// specification table for the expanded presentation: **371 × 84–160pt** with a
/// **44pt** corner radius (408pt wide on Pro Max / Plus / Air). The billing
/// states use the whole 160pt so the island keeps the standard 2.3:1 proportion
/// rather than being squeezed flat.
///
/// Every value is a point measurement taken from that sheet. If a device
/// screenshot drifts, calibrate here instead of scattering literals through the
/// views.
private enum IslandLayout {
  /// A component size, not a positioning offset. WidgetKit owns all spacing
  /// around the TrueDepth camera and the island edges.
  static let ringDiameter: CGFloat = 56
  static var ringLineWidth: CGFloat { ringDiameter / 10 }

  static let allowance = Color(red: 1.0, green: 0.69, blue: 0.13)
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
    // Dormant until the backend starts sending these two. `ActivityBill` on the
    // server is `{ amountCents, planLabel, nextEvent, asOfUnix }` — it carries
    // neither `billable` nor `remainingToCapCents`, so both decode as nil and
    // every billing session currently resolves to `.metering`. The capped and
    // paused states are drawn, tested against the sheet, and waiting on the
    // payload rather than on this side. `nextEvent.label` is not a substitute:
    // a rule switch happens for reasons other than a cap.
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
      return billingState == .paused ? Color.blue : Color.green
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

  /// Compact presentations use a symbol instead of forcing the expanded ring
  /// into the much smaller compact slot.
  var compactSymbolName: String {
    switch phase {
    case .billing:
      switch billingState {
      case .metering: return "clock.fill"
      case .capped: return "checkmark.circle.fill"
      case .paused: return "pause.circle.fill"
      }
    case .awaitingCheckout:
      return "creditcard.fill"
    case .settled:
      return "checkmark.seal.fill"
    }
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

  /// The window the ring sweeps: from the bill's push time to the next event,
  /// so it depletes toward the next charge without needing a new push.
  var countdownWindow: ClosedRange<Date>? {
    guard let next = nextEvent else { return nil }
    let end = next.date
    let fallback = end.timeIntervalSince1970 - 60
    let start = bill.map { min($0.asOfUnix, fallback) } ?? fallback
    return Date(timeIntervalSince1970: start)...end
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

  /// Secondary allowance/status text. Deliberately text-only: a proportional
  /// progress bar would imply a real cap percentage that the payload does not
  /// currently provide.
  var capRowText: String? {
    guard phase == .billing, !isStale else { return nil }
    if billingState == .capped { return String(localized: "已达上限") }
    if billingState == .paused { return String(localized: "非营业时段") }
    guard let remaining = bill?.remainingToCapCents, remaining > 0 else { return nil }
    return Self.centsText(remaining)
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
        // Keep expanded content in a compact cluster immediately below the
        // camera. WidgetKit owns camera clearance and edge insets; the view
        // deliberately contains no screenshot-derived positioning offsets.
        DynamicIslandExpandedRegion(.center) {
          StoreVisitHeroRow(model: model)
        }
        DynamicIslandExpandedRegion(.bottom) {
          StoreVisitVisitRow(model: model)
        }
      } compactLeading: {
        StoreVisitCompactStatus(model: model)
      } compactTrailing: {
        StoreVisitCompactAmount(model: model)
      } minimal: {
        StoreVisitMinimal(model: model)
      }
      .keylineTint(model.accent)
      .widgetURL(context.attributes.shopURL)
    }
  }
}

// MARK: - Lock screen

struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  var body: some View {
    let model = StoreVisitDisplayModel(context: context)
    VStack {
      StoreVisitHeroRow(model: model)
      StoreVisitVisitRow(model: model)
    }
    .padding()
    .widgetURL(context.attributes.shopURL)
  }
}

// MARK: - Compact / minimal

private struct StoreVisitCompactStatus: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    Image(systemName: model.compactSymbolName)
      .font(.callout.weight(.semibold))
      .foregroundStyle(model.accent)
      // The compact region is already a camera-safe slot. Fill that slot and
      // align inward instead of adding padding or offsetting by measured points.
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
  }
}

private struct StoreVisitCompactAmount: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    if let amount = model.compactAmountText {
      ViewThatFits(in: .horizontal) {
        amountText(amount, font: .callout)
        amountText(amount, font: .caption)
      }
      // Trailing content starts at the camera-facing edge of its system slot.
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }

  private func amountText(_ amount: String, font: Font.TextStyle) -> some View {
    Text(amount)
      .font(.system(font, design: .rounded, weight: .semibold))
      .monospacedDigit()
      .foregroundStyle(model.accent)
      .lineLimit(1)
  }
}

private struct StoreVisitMinimal: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    ViewThatFits(in: .horizontal) {
      if let amount = model.compactAmountText {
        Text(amount)
          .font(.caption.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(model.accent)
          .lineLimit(1)
      }
      Image(systemName: model.compactSymbolName)
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.accent)
    }
  }
}

// MARK: - Expanded shared views

private struct StoreVisitHeroRow: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        StoreVisitRing(model: model)
        StoreVisitEventBlock(model: model)
          .layoutPriority(1)
        StoreVisitAmountStack(model: model)
      }

      // Narrow devices or unusually long localized content fall back to a
      // symbol instead of squeezing or clipping the ring.
      HStack {
        Image(systemName: model.compactSymbolName)
          .font(.headline)
          .foregroundStyle(model.accent)
        StoreVisitEventBlock(model: model)
          .layoutPriority(1)
        StoreVisitAmountStack(model: model)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

private struct SweepRingStyle: ProgressViewStyle {
  let tint: Color

  func makeBody(configuration: Configuration) -> some View {
    let fraction = CGFloat(configuration.fractionCompleted ?? 1)
    return ZStack {
      Circle()
        .stroke(Color.white.opacity(0.14), lineWidth: IslandLayout.ringLineWidth)
      Circle()
        .trim(from: 0, to: min(max(fraction, 0.02), 1))
        .stroke(tint, style: StrokeStyle(
          lineWidth: IslandLayout.ringLineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .frame(width: IslandLayout.ringDiameter, height: IslandLayout.ringDiameter)
    .overlay { configuration.currentValueLabel }
  }
}

private struct StoreVisitRing: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    ZStack {
      if let window = model.countdownWindow {
        ProgressView(timerInterval: window, countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          centerLabel
        }
        .progressViewStyle(SweepRingStyle(tint: model.accent))
      } else {
        Circle()
          .stroke(Color.white.opacity(0.14), lineWidth: IslandLayout.ringLineWidth)
        Circle()
          .trim(from: 0, to: model.staticRingFraction)
          .stroke(model.accent, style: StrokeStyle(
            lineWidth: IslandLayout.ringLineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
        centerLabel
      }
    }
    .frame(width: IslandLayout.ringDiameter, height: IslandLayout.ringDiameter)
  }

  @ViewBuilder private var centerLabel: some View {
    if let window = model.countdownWindow {
      ViewThatFits(in: .horizontal) {
        timerText(window, font: .caption)
        timerText(window, font: .caption2)
        Image(systemName: model.compactSymbolName)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(model.accent)
      }
    } else if let word = model.ringStateWord {
      Text(word)
        .font(.caption.weight(.semibold))
        .foregroundStyle(model.accent)
        .lineLimit(1)
    }
  }

  private func timerText(_ window: ClosedRange<Date>, font: Font.TextStyle) -> some View {
    Text(timerInterval: window, countsDown: true, showsHours: false)
      .font(.system(font, design: .rounded, weight: .semibold))
      .monospacedDigit()
      .foregroundStyle(model.accent)
      .lineLimit(1)
  }
}

private struct StoreVisitEventBlock: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(alignment: .leading) {
      Text(eventName)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)

      if let next = model.nextEvent {
        Text(next.date, style: .time)
          .font(.headline)
          .monospacedDigit()
          .foregroundStyle(model.eventTimeColor)
          .lineLimit(1)
      } else if let scheduled = model.lastScheduledEvent {
        Text(scheduled.date, style: .time)
          .font(.headline)
          .monospacedDigit()
          .foregroundStyle(.primary)
          .lineLimit(1)
      } else if !model.trailingStatusText.isEmpty {
        Text(model.trailingStatusText)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
  }

  private var eventName: String {
    if let next = model.nextEvent { return next.title }
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

private struct StoreVisitAmountStack: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(alignment: .trailing) {
      StoreVisitAmountLine(model: model)
      StoreVisitCapRow(model: model)
    }
  }
}

private struct StoreVisitAmountLine: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Text(model.amountCaption)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(model.heroAmountText ?? "--")
        .font(.title2.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .contentTransition(.numericText())
    }
  }
}

private struct StoreVisitCapRow: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    if let text = model.capRowText {
      Label {
        Text(text)
          .monospacedDigit()
      } icon: {
        Image(systemName: "gauge")
      }
      .font(.caption)
      .foregroundStyle(IslandLayout.allowance)
      .lineLimit(1)
    } else if !model.trailingStatusText.isEmpty {
      Text(model.trailingStatusText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}

// MARK: - Lower band

private struct StoreVisitVisitRow: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    ViewThatFits(in: .horizontal) {
      fullRow
      compactRow
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }

  private var fullRow: some View {
    HStack {
      Text(model.shopName)
        .lineLimit(1)

      if model.isStale, let asOfUnix = model.bill?.asOfUnix {
        Label {
          Text(Date(timeIntervalSince1970: asOfUnix), style: .time)
            .monospacedDigit()
        } icon: {
          Image(systemName: "clock.arrow.circlepath")
        }
      } else {
        visitMetric(systemName: "figure.walk.arrival", text: model.entryText)
        visitMetric(systemName: "timer", text: model.elapsedText)
      }
    }
  }

  private var compactRow: some View {
    HStack {
      Text(model.shopName)
        .lineLimit(1)

      if model.isStale, let asOfUnix = model.bill?.asOfUnix {
        Text(Date(timeIntervalSince1970: asOfUnix), style: .time)
          .monospacedDigit()
      } else {
        visitMetric(systemName: "timer", text: model.elapsedText)
      }
    }
  }

  private func visitMetric(systemName: String, text: String) -> some View {
    Label {
      Text(text).monospacedDigit()
    } icon: {
      Image(systemName: systemName)
    }
  }
}
