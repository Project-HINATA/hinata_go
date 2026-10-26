import SwiftUI

/// One hue per plan, shared by the bill timeline and the pricing card so a plan looks the same in
/// both, and the same as on the web page.
func prismPlanColor(_ index: Int) -> Color {
  let colors: [(Double, Double, Double)] = [
    (0x4e, 0x7e, 0xaf), (0xa4, 0x75, 0x53), (0x88, 0x74, 0xb4), (0x4b, 0x90, 0x8d), (0xba, 0x71, 0x87), (0x7f, 0x8e, 0x49),
  ]
  let (r, g, b) = colors[((index % colors.count) + colors.count) % colors.count]
  return Color(red: r / 255, green: g / 255, blue: b / 255)
}

/// The web page's accent: what a cap has counted, and a cap filling.
let prismAccent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
  ? UIColor(red: 0x40 / 255, green: 0x9c / 255, blue: 1, alpha: 1)
  : UIColor(red: 0, green: 0x66 / 255, blue: 0xd6 / 255, alpha: 1) })

/// Money as the pricing card writes it: always two decimals.
func prismMoney(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }

/// A period as listed: the pieces of one window, joined across midnight.
struct PrismPeriodRow {
  var pieces: [PrismDaySegment]
  var startLabel: String
  var endLabel: String
}

/// One row per period. A window running through midnight shows on the strip as its morning and
/// evening pieces; listed, it is one period such as 22:00–10:00.
func prismPeriodRows(_ segments: [PrismDaySegment]) -> [PrismPeriodRow] {
  let rows = segments.map { PrismPeriodRow(pieces: [$0], startLabel: $0.startLabel, endLabel: $0.endLabel) }
  func instant(_ value: String?) -> Date? { value.flatMap(prismParsedDate) }
  func startsBefore(_ s: PrismDaySegment) -> Bool {
    guard let window = instant(s.windowStartedAt), let start = instant(s.startedAt) else { return false }
    return window < start
  }
  func endsAfter(_ s: PrismDaySegment) -> Bool {
    guard let window = instant(s.windowEndedAt), let end = instant(s.endedAt) else { return false }
    return window > end
  }
  if segments.count > 1, let head = segments.first, let tail = segments.last, head.isClosed != true,
     head.ruleId == tail.ruleId, startsBefore(head), endsAfter(tail) {
    return Array(rows.dropFirst().dropLast()) + [PrismPeriodRow(pieces: [tail, head], startLabel: tail.startLabel, endLabel: head.endLabel)]
  }
  return rows
}

/// What scanning this resource charges today, read before confirming: one card of lanes on a
/// shared 0–24 axis. Each plan is a strip of its periods, dearer periods drawn stronger; each cap
/// across plans a strip of its windows filled as far as the current one is used up. A lane states
/// its current period in one line; tapping a piece states that one instead.
struct ClipResourcePricing: View {
  let rules: PrismResourceBilling.Rules
  /// What confirming starts, ends and keeps.
  var changes: PrismResourceBilling.Preview? = nil
  @State private var segments: [[PrismDaySegment]] = []

  private var zone: TimeZone { TimeZone(identifier: rules.timeZone) ?? .current }
  private var today: (date: String, minute: Int) {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date())
    return (String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0), (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
  }
  private var shared: [PrismResourceBilling.Rules.SharedCap] { rules.caps?.shared ?? [] }

  var body: some View {
    let now = today
    VStack(alignment: .leading, spacing: 20) {
      ForEach(Array(rules.plans.enumerated()), id: \.offset) { index, plan in
        ClipPlanLane(
          name: plan.config.name,
          fixedAmount: plan.config.kind == "charge.fixed" ? plan.config.provider.amount ?? 0 : nil,
          tag: tag(plan.config.id),
          color: prismPlanColor(index),
          segments: index < segments.count ? segments[index] : [],
          nowMinute: now.minute,
          caps: rules.caps?.plans.filter { $0.pricingConfigId == plan.config.id } ?? []
        )
      }
      if !shared.isEmpty {
        VStack(alignment: .leading, spacing: 16) {
          Text("跨方案封顶").font(.caption).foregroundStyle(.secondary).padding(.bottom, -8)
          ForEach(Array(shared.enumerated()), id: \.offset) { index, cap in
            let at = rules.plans.count + index
            ClipCapLane(cap: cap, segments: at < segments.count ? segments[at] : [], nowMinute: now.minute)
          }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Divider() }
      }
      ClipDayAxis().padding(.top, -8)
      let stopped = changes?.stopped ?? []
      let unsettled = rules.caps?.unsettled ?? 0
      if !stopped.isEmpty || unsettled > 0 {
        VStack(spacing: 8) {
          if !stopped.isEmpty {
            HStack(alignment: .firstTextBaseline) {
              Text("结束方案").foregroundStyle(.secondary)
              Spacer(minLength: 12)
              Text(stopped.map(\.planName).joined(separator: "、")).lineLimit(1)
            }
          }
          if unsettled > 0 {
            HStack(alignment: .firstTextBaseline) {
              Text("已计").foregroundStyle(.secondary)
              Spacer(minLength: 12)
              Text(prismMoney(unsettled)).fontWeight(.semibold).monospacedDigit()
            }
          }
        }
        .font(.subheadline)
        .padding(.top, 12)
        .overlay(alignment: .top) { Divider() }
      }
    }
    .padding(16)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text("计费规则"))
    // Each plan's day is worked out here, from the plan's own rules, as the web page does.
    .task(id: now.date + rules.timeZone + rules.plans.map(\.config.id).joined() + shared.map(\.pricingConfigId).joined()) {
      let date = now.date, zone = rules.timeZone
      let configs = rules.plans.map(\.config) + shared.map(\.config)
      segments = await Task.detached(priority: .userInitiated) {
        configs.map { PrismDaySegments.segments(config: $0, localDate: date, displayTimeZone: zone) }
      }.value
    }
  }

  private func tag(_ planId: String) -> LocalizedStringKey? {
    if changes?.started.contains(where: { $0.planId == planId }) == true { return "新增" }
    if changes?.kept.contains(where: { $0.planId == planId }) == true { return "保留" }
    return nil
  }
}

/// The period a lane states: the one tapped, else the one in force now.
private struct PickedRow {
  var picked: (start: Int, ruleId: String)?
  func row(in rows: [PrismPeriodRow], nowMinute: Int) -> (row: PrismPeriodRow?, tapped: Bool) {
    if let picked, let tapped = rows.first(where: { $0.pieces[0].startMinute == picked.start && $0.pieces[0].ruleId == picked.ruleId }) {
      return (tapped, true)
    }
    return (rows.first { prismIsNow($0, nowMinute) }, false)
  }
}

private func prismIsNow(_ row: PrismPeriodRow?, _ nowMinute: Int) -> Bool {
  row?.pieces.contains { nowMinute >= $0.startMinute && nowMinute < $0.endMinute } == true
}

private func prismCapText(paidBefore: Double, priceCap: Double) -> String {
  paidBefore >= priceCap
    ? String(localized: "已达封顶") + " " + prismMoney(priceCap)
    : String(localized: "已计") + " " + prismMoney(paidBefore) + " / " + String(localized: "封顶") + " " + prismMoney(priceCap)
}

private func prismPriceText(_ s: PrismDaySegment) -> String {
  if s.isClosed == true { return String(localized: "不计费") }
  if let pricing = s.pricing {
    return prismMoney(pricing.unitPrice) + " / " + pricing.unitMinutes.formatted() + " " + String(localized: "分钟")
  }
  if let cap = s.priceCap { return String(localized: "封顶") + " " + prismMoney(cap) }
  return s.label
}

/// One plan: name and price, its day with dearer periods drawn stronger, and the stated period in a line.
private struct ClipPlanLane: View {
  let name: String
  /// A fixed charge has no day to draw: it is billed once for the visit.
  var fixedAmount: Double? = nil
  let tag: LocalizedStringKey?
  let color: Color
  let segments: [PrismDaySegment]
  let nowMinute: Int
  let caps: [PrismResourceBilling.Rules.CapProgress]
  @State private var picked = PickedRow()

  var body: some View {
    let rows = prismPeriodRows(segments)
    let (row, tapped) = picked.row(in: rows, nowMinute: nowMinute)
    let first = row?.pieces.first
    let cap = first.flatMap { first in prismIsNow(row, nowMinute) ? caps.first { $0.ruleId == first.ruleId } : nil }
    let rate = { (s: PrismDaySegment) -> Double in
      s.isClosed == true || s.pricing == nil ? 0 : abs(s.pricing!.unitPrice / max(1, s.pricing!.unitMinutes))
    }
    let top = segments.map(rate).max() ?? 0
    VStack(alignment: .leading, spacing: 8) {
      ClipLaneHeader(value: fixedAmount.map(prismMoney) ?? first.map(prismPriceText) ?? "") {
        Circle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
        Text(name).fontWeight(.semibold).lineLimit(1)
        if let tag {
          Text(tag).font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
      }
      if fixedAmount != nil {
        Text("单次收取").font(.caption).foregroundStyle(.secondary)
      } else {
      ClipDayStrip(segments: segments, rows: rows, nowMinute: nowMinute, height: 10, accent: color,
                   picked: tapped ? row : nil, pick: { pick($0, rows: rows, tapped: tapped ? row : nil) }) { s in
        s.isClosed == true ? AnyShapeStyle(Color.primary.opacity(0.1))
          : AnyShapeStyle(color.opacity(top > 0 ? 0.55 + 0.45 * pow(rate(s) / top, 2) : 1))
      }
      if let row, let first {
        let capLine: String = {
          if let cap { return " · " + prismCapText(paidBefore: cap.paidBefore, priceCap: cap.priceCap) }
          if first.isClosed != true, let limit = first.pricing?.priceCap, limit > 0, limit < 9007199254740991 {
            return " · " + String(localized: "封顶") + " " + prismMoney(limit)
          }
          return ""
        }()
        Text((first.isClosed == true ? String(localized: "不计费") : first.label) + " " + row.startLabel + "–" + row.endLabel + capLine)
          .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      }
    }
  }

  private func pick(_ next: PrismPeriodRow, rows: [PrismPeriodRow], tapped: PrismPeriodRow?) {
    // Tapping the picked or the current period goes back to now.
    let same = tapped.map { $0.pieces[0].startMinute == next.pieces[0].startMinute && $0.pieces[0].ruleId == next.pieces[0].ruleId } ?? false
    picked.picked = same || prismIsNow(next, nowMinute) ? nil : (next.pieces[0].startMinute, next.pieces[0].ruleId)
  }
}

/// One cap across plans: its windows over the day, the current one filled as far as it is used up.
private struct ClipCapLane: View {
  let cap: PrismResourceBilling.Rules.SharedCap
  let segments: [PrismDaySegment]
  let nowMinute: Int
  @State private var picked = PickedRow()

  var body: some View {
    let rows = prismPeriodRows(segments)
    let (row, tapped) = picked.row(in: rows, nowMinute: nowMinute)
    let first = row?.pieces.first
    let start = prismParsedDate(cap.startsAt)
    let inWindow = { (s: PrismDaySegment) -> Bool in s.windowStartedAt.flatMap(prismParsedDate) == start && start != nil }
    let counting = segments.filter(inWindow)
    // The window's spending fills its pieces from the left, across a split if it has one.
    let fills: [Double] = {
      var left = (cap.priceCap > 0 ? min(1, cap.paidBefore / cap.priceCap) : 1)
        * Double(counting.reduce(0) { $0 + $1.endMinute - $1.startMinute })
      return segments.map { s in
        guard inWindow(s) else { return 0 }
        let length = Double(s.endMinute - s.startMinute)
        let part = min(length, left)
        left -= part
        return length > 0 ? part / length : 0
      }
    }()
    let counted = row?.pieces.contains(where: inWindow) == true
    VStack(alignment: .leading, spacing: 8) {
      ClipLaneHeader(value: first.map { first in
        counted ? prismCapText(paidBefore: cap.paidBefore, priceCap: cap.priceCap)
          : first.isClosed == true ? String(localized: "不封顶") : String(localized: "封顶") + " " + prismMoney(first.priceCap ?? 0)
      } ?? "", quiet: true) {
        Text(cap.name).fontWeight(.semibold).lineLimit(1)
      }
      ClipDayStrip(segments: segments, rows: rows, nowMinute: nowMinute, height: 6, accent: prismAccent,
                   picked: tapped ? row : nil, fill: { s in segments.firstIndex(of: s).map { fills[$0] } ?? 0 },
                   pick: { next in
                     let same = tapped && row.map { $0.pieces[0].startMinute == next.pieces[0].startMinute && $0.pieces[0].ruleId == next.pieces[0].ruleId } == true
                     picked.picked = same || prismIsNow(next, nowMinute) ? nil : (next.pieces[0].startMinute, next.pieces[0].ruleId)
                   }) { s in
        AnyShapeStyle(s.isClosed == true ? Color.clear : Color.primary.opacity(0.12))
      }
      if let row, let first {
        Text((first.isClosed == true ? String(localized: "不封顶") : first.label) + " " + row.startLabel + "–" + row.endLabel)
          .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
    }
  }
}

private struct ClipLaneHeader<Title: View>: View {
  let value: String
  var quiet = false
  @ViewBuilder let title: Title
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      HStack(spacing: 8) { title }.layoutPriority(1)
      Spacer(minLength: 0)
      Text(value).font(quiet ? .caption : .subheadline.weight(.semibold)).monospacedDigit().lineLimit(1).fixedSize()
    }
    .font(.subheadline)
  }
}

/// The day from 0 to 24 as pieces, one per period window: a period through midnight is two pieces
/// of the same colour. Tapping a piece picks its period. A knob rimmed in the lane's colour marks now.
private struct ClipDayStrip: View {
  let segments: [PrismDaySegment]
  let rows: [PrismPeriodRow]
  let nowMinute: Int
  let height: CGFloat
  let accent: Color
  let picked: PrismPeriodRow?
  var fill: ((PrismDaySegment) -> Double)? = nil
  let pick: (PrismPeriodRow) -> Void
  let tone: (PrismDaySegment) -> AnyShapeStyle
  private static let gap: CGFloat = 2

  init(segments: [PrismDaySegment], rows: [PrismPeriodRow], nowMinute: Int, height: CGFloat, accent: Color,
       picked: PrismPeriodRow?, fill: ((PrismDaySegment) -> Double)? = nil, pick: @escaping (PrismPeriodRow) -> Void,
       tone: @escaping (PrismDaySegment) -> AnyShapeStyle) {
    self.segments = segments; self.rows = rows; self.nowMinute = nowMinute; self.height = height; self.accent = accent
    self.picked = picked; self.fill = fill; self.pick = pick; self.tone = tone
  }

  var body: some View {
    GeometryReader { geometry in
      let usable = max(0, geometry.size.width - Self.gap * CGFloat(max(0, segments.count - 1)))
      ZStack(alignment: .leading) {
        HStack(spacing: Self.gap) {
          ForEach(Array(segments.enumerated()), id: \.offset) { _, s in
            let row = rows.first { $0.pieces.contains(s) }
            let isPicked = picked.map { picked in row.map { $0.pieces[0] == picked.pieces[0] } ?? false } ?? false
            Button { if let row { pick(row) } } label: {
              ZStack(alignment: .leading) {
                Capsule().fill(tone(s))
                if let fill, fill(s) > 0 {
                  GeometryReader { piece in
                    Rectangle().fill(prismAccent).frame(width: piece.size.width * fill(s))
                  }
                }
              }
              .clipShape(Capsule())
              .overlay { if isPicked { Capsule().inset(by: -3).strokeBorder(Color.primary.opacity(0.6), lineWidth: 2) } }
              .frame(width: usable * CGFloat(s.endMinute - s.startMinute) / 1440, height: height)
              .contentShape(Rectangle().inset(by: -10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text((row?.startLabel ?? s.startLabel) + "–" + (row?.endLabel ?? s.endLabel) + " " + s.label))
          }
        }
        Circle()
          .fill(Color(.secondarySystemGroupedBackground))
          .overlay { Circle().strokeBorder(accent, lineWidth: 2) }
          .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
          .frame(width: 12, height: 12)
          .offset(x: geometry.size.width * CGFloat(nowMinute) / 1440 - 6)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .frame(height: geometry.size.height)
    }
    .frame(height: max(height, 12))
  }
}

private struct ClipDayAxis: View {
  var body: some View {
    GeometryReader { geometry in
      ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
        Text(verbatim: "\(hour)")
          .font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary)
          .fixedSize()
          .alignmentGuide(.leading) { d in hour == 0 ? 0 : hour == 24 ? d.width : d.width / 2 }
          .offset(x: geometry.size.width * CGFloat(hour) / 24)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(height: 14)
    .accessibilityHidden(true)
  }
}
