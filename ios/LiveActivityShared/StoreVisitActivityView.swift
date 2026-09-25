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

  /// Status accent for the countdown row: green while metered, blue while
  /// paused. Awaiting checkout and settled never render a countdown.
  var tint: Color {
    switch phase {
    case .billing:
      return billingState == .paused ? Color.blue : Color.green
    case .awaitingCheckout, .settled:
      return Color.secondary
    }
  }

  /// Compact/minimal state icon: blue clock while metered, gray pause while
  /// paused, orange credit card while awaiting payment, green checkmark once
  /// settled.
  var stateSymbolName: String {
    switch phase {
    case .billing:
      return billingState == .paused ? "pause.circle.fill" : "clock.fill"
    case .awaitingCheckout:
      return "creditcard.circle.fill"
    case .settled:
      return "checkmark.circle.fill"
    }
  }

  var stateColor: Color {
    switch phase {
    case .billing:
      return billingState == .paused ? Color.gray : Color.blue
    case .awaitingCheckout:
      return Color.orange
    case .settled:
      return Color.green
    }
  }

  /// Amount still chargeable before the effective cap, or nil when unknown or
  /// the visit is no longer billing.
  var remainingToCapCents: Int? {
    phase == .billing ? bill?.remainingToCapCents : nil
  }

  var isCapped: Bool {
    billingState == .capped
  }

  /// Minute-precision localized duration ("1小时23分" style, no seconds).
  static func minutesText(from: Date, to: Date) -> String {
    Duration.seconds(max(0, to.timeIntervalSince(from)))
      .formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2))
  }

  /// Time in store so far, shown as the leading headline while billing.
  var elapsedText: String {
    Self.minutesText(from: startedAt, to: .now)
  }

  /// Frozen total duration, shown as the leading headline after checkout.
  var totalDurationText: String {
    Self.minutesText(from: startedAt, to: endedAt ?? .now)
  }

  /// Check-in clock time for the footer, e.g. "14:02".
  var startedAtText: String {
    startedAt.formatted(date: .omitted, time: .shortened)
  }

  /// Exact decimal rendering of integer cents, shared by every amount shown.
  static func centsText(_ cents: Int) -> String {
    (Decimal(cents) / 100).formatted(.number.precision(.fractionLength(2)))
  }

  /// Hero amount text, or nil before the first bill arrives.
  var amountText: String? {
    bill.map { Self.centsText($0.amountCents) }
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
          StoreVisitHeading(model: model)
        }
        DynamicIslandExpandedRegion(.trailing) {
          StoreVisitMetric(model: model)
        }
        DynamicIslandExpandedRegion(.bottom) {
          StoreVisitDetailRows(model: model)
            .padding(.top, 4)
        }
      } compactLeading: {
        Image(systemName: model.stateSymbolName)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(model.stateColor)
      } compactTrailing: {
        if let amountText = model.amountText {
          HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("¥")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
            Text(amountText)
              .font(.footnote.weight(.semibold))
              .monospacedDigit()
          }
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        }
      } minimal: {
        Image(systemName: model.stateSymbolName)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(model.stateColor)
      }
      .keylineTint(model.tint)
      .widgetURL(context.attributes.shopURL)
    }
    .contentMarginsDisabled()
  }
}

// MARK: - Lock screen

struct StoreVisitActivityView: View {
  let context: ActivityViewContext<StoreVisitAttributes>

  var body: some View {
    StoreVisitCard(model: StoreVisitDisplayModel(context: context))
      .padding(.horizontal, 18)
      .padding(.vertical, 14)
      .widgetURL(context.attributes.shopURL)
  }
}

/// Glanceable facts (status, shop, amount) above the supporting detail rows,
/// separated by a hairline so the hierarchy reads top-down.
private struct StoreVisitCard: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        StoreVisitHeading(model: model)
        Spacer(minLength: 12)
        StoreVisitMetric(model: model)
      }
      Divider()
      StoreVisitDetailRows(model: model)
    }
  }
}

// MARK: - Shared components

/// Leading header column, mirroring the amount column: what the number is,
/// the time in store itself (frozen total duration after checkout), and the
/// check-in clock time in small print.
private struct StoreVisitHeading: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("在场时间")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(model.phase == .billing ? model.elapsedText : model.totalDurationText)
        .font(.headline.weight(.semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text(String(localized: "入店") + " " + model.startedAtText)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}

/// Trailing header column, mirroring the time column: what the number is, the
/// bill amount, and the cap notice in small print (segment-scoped when
/// capped, otherwise the remaining headroom).
private struct StoreVisitMetric: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      if let amountText = model.amountText {
        Text(amountLabel)
          .font(.caption2)
          .foregroundStyle(.secondary)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("¥")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
          Text(amountText)
            .font(.title2.weight(.semibold))
            .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        capNotice
      }
    }
  }

  @ViewBuilder private var capNotice: some View {
    if model.phase == .billing, !model.isStale {
      if model.isCapped {
        Text("本时段已封顶")
          .font(.caption2)
          .foregroundStyle(Color.green)
      } else if let remaining = model.remainingToCapCents, remaining > 0 {
        Text("距封顶还差 \("¥" + StoreVisitDisplayModel.centsText(remaining))")
          .font(.caption2)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }

  private var amountLabel: LocalizedStringKey {
    model.phase == .settled ? "本次消费" : "账单金额"
  }
}

/// Detail hierarchy shared by the lock screen card and the island's bottom
/// region: the forward-looking countdown when one exists, then a footer line
/// carrying the shop name on the left and the state notice on the right.
private struct StoreVisitDetailRows: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if model.nextEvent != nil {
        StoreVisitLiveRow(model: model)
      }
      StoreVisitMetaRow(model: model)
    }
  }
}

/// The forward-looking metric: a countdown to the next event, minute-precise
/// and self-refreshing, with the event's absolute clock time in small print.
private struct StoreVisitLiveRow: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      if let next = model.nextEvent {
        Image(systemName: "clock")
          .font(.caption.weight(.semibold))
          .foregroundStyle(model.tint)
          .padding(.top, 1)
        Text(next.title)
          .font(.caption)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 1) {
          Text(next.date, style: .relative)
            .font(.callout.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(model.tint)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: 110, alignment: .trailing)
          Text(next.date.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: 110, alignment: .trailing)
        }
      }
    }
  }
}

/// Footer line: the shop name in the leading slot (full width, so long names
/// are safe) and the state notice on the right — data freshness when stale,
/// the phase when it needs action, otherwise the tap hint. Cap notices live
/// under the amount in the header.
private struct StoreVisitMetaRow: View {
  let model: StoreVisitDisplayModel

  var body: some View {
    HStack(spacing: 4) {
      Text(model.shopName)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
      Spacer(minLength: 8)
      notice
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
  }

  @ViewBuilder private var notice: some View {
    if model.isStale, let asOfUnix = model.bill?.asOfUnix {
      Text("数据更新于")
      Text(Date(timeIntervalSince1970: asOfUnix), style: .time)
    } else if model.phase == .awaitingCheckout {
      Text("待结账")
        .foregroundStyle(Color.orange)
    } else if model.billingState == .paused {
      Text("暂不计费")
        .foregroundStyle(Color.blue)
    } else {
      Text("轻点查看账单")
    }
  }
}

