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
  /// The design's inset from the island's edges, shared by all four sides — and
  /// by the ring's top padding, so the ring is inset the same amount on its top
  /// and leading sides.
  static let margin: CGFloat = 24

  /// SwiftUI insets every expanded region horizontally before our own padding
  /// applies. Measured off a device screenshot: with 24pt of our own padding the
  /// ring landed about 44pt from the edge, so the system supplies about 20pt.
  /// Our padding is the remainder — calibrate `margin` and the content follows.
  static let systemRegionInset: CGFloat = 20
  static var contentPadding: CGFloat { max(0, margin - systemRegionInset) }

  /// The regions already start about this far below the island's top edge,
  /// measured on device -- which happens to be exactly the inset the sheet asks
  /// for, so the ring and the amount need **no** top padding of their own. The
  /// earlier -13pt here pushed them into the top edge instead.
  static let regionTopInset: CGFloat = 24
  static var besideCameraTop: CGFloat { margin - regionTopInset }

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

  /// How far the trailing column is lifted so the amount **caption's** baseline
  /// lands on the same row as the event title's. The caption (20pt) then reads
  /// as the title's right-hand peer, while the amount (40pt), sharing that
  /// baseline via firstTextBaseline, rises past the camera band above it — the
  /// move Apple's own timer activity makes with its digits. Negative because
  /// the column starts at the region's top and must climb; calibrate on device.
  static let captionRowLift: CGFloat = -16

  /// Nudges the event column toward the ring. The system pads the gap between
  /// the centre and leading regions; the sheet wants the event flush against
  /// the ring's right edge instead. Negative, and calibrate on device.
  static let eventHugRing: CGFloat = -8

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
        // Upper band, left: the state ring. Its top padding equals its leading
        // padding, and its bottom lands on the same line as the other two
        // columns because the band is exactly one ring tall.
        DynamicIslandExpandedRegion(.leading) {
          StoreVisitRing(model: model)
            .padding(.top, IslandLayout.besideCameraTop)
            .padding(.leading, IslandLayout.contentPadding)
        }
        // Upper band, centre: the event. Only the top edge is constrained — it
        // tucks under the camera so the housing stops reading as a hole. The
        // leading edge sits next to the ring rather than lining up with the
        // camera, which would strand it in the middle of the island.
        DynamicIslandExpandedRegion(.center) {
          // Top-aligned on purpose: a region centres its content vertically by
          // default, which left the event stranded mid-band with the ring
          // dangling below it. Pinning it to the top tucks it under the camera,
          // where it also lines its last line up with the ring's bottom.
          StoreVisitEventBlock(model: model)
            .padding(.leading, IslandLayout.eventHugRing)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // Upper band, right: what it costs. The amount's own top inset matches
        // the island's trailing inset, so the block is inset the same amount on
        // two sides. Bottom-aligned to the band so all three columns agree.
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            StoreVisitAmountLine(model: model)
              .padding(.top, IslandLayout.captionRowLift)
            StoreVisitCapRow(model: model)
              .padding(.top, 6)
          }
          .layoutPriority(1)
          .frame(maxHeight: .infinity, alignment: .top)
          .padding(.top, IslandLayout.besideCameraTop)
          .padding(.trailing, IslandLayout.contentPadding)
        }
        // Lower band: the visit itself, on one line.
        DynamicIslandExpandedRegion(.bottom) {
          StoreVisitVisitRow(model: model)
            .padding(.horizontal, IslandLayout.contentPadding)
            .padding(.bottom, IslandLayout.contentPadding)
            .padding(.top, IslandLayout.bandGap)
        }
      } compactLeading: {
        // The ring is concentric with the capsule's end cap: centring it in the
        // slot gives it an identical inset on its leading, top and bottom sides.
        StoreVisitRing(model: model, diameter: IslandLayout.compactRing, showsLabel: false)
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

/// The ring style the sheet draws: a faint track under an accent sweep that
/// starts at 12 o'clock, both at the sheet's stroke width. Used for the live
/// countdown and the static fraction alike, so the two can never render
/// differently -- the system's built-in circular style strokes thinner than the
/// sheet and made the live ring look like a different component.
private struct SweepRingStyle: ProgressViewStyle {
  let lineWidth: CGFloat
  let tint: Color

  func makeBody(configuration: Configuration) -> some View {
    let fraction = CGFloat(configuration.fractionCompleted ?? 1)
    return ZStack {
      Circle()
        .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: min(max(fraction, 0.02), 1))
        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
      configuration.currentValueLabel
    }
  }
}

/// The state ring, with the minutes left nested in its centre. A live countdown
/// uses `ProgressView(timerInterval:)` so it keeps sweeping without a push; the
/// states without a target draw a static ring at their own fraction.
private struct StoreVisitRing: View {
  let model: StoreVisitDisplayModel
  var diameter: CGFloat?
  var showsLabel: Bool = true

  private var side: CGFloat { diameter ?? model.ringDiameter }

  var body: some View {
    ZStack {
      if let window = model.countdownWindow {
        ProgressView(timerInterval: window, countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          centerLabel
        }
        .progressViewStyle(SweepRingStyle(
          lineWidth: IslandLayout.ringLineWidth, tint: model.accent))
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
    .frame(width: side, height: side)
  }

  @ViewBuilder private var centerLabel: some View {
    if !showsLabel {
      EmptyView()
    } else if let window = model.countdownWindow {
      // Self-refreshing, so it ticks down with no backend push. The relative
      // style is not usable here: it reads "24分钟 0秒", far wider than the ring.
      // `showsHours: false` keeps it to mm:ss; with the hour field a five hour
      // countdown renders "5:47:15", wider than the ring's inner circle.
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
