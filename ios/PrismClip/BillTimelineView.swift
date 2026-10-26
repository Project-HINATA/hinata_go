import SwiftUI

private typealias Timeline = PrismBillTimeline

/// A card's fill. Pages are grouped, so their cards are grouped cards; a sheet keeps the system
/// background (glass, or white at full height), where only a translucent fill reads as a card.
private struct PrismCardFillKey: EnvironmentKey {
  static let defaultValue = Color(.secondarySystemGroupedBackground)
}
extension EnvironmentValues {
  var prismCardFill: Color {
    get { self[PrismCardFillKey.self] }
    set { self[PrismCardFillKey.self] = newValue }
  }
}

private func instant(_ value: String) -> TimeInterval { prismParsedDate(value)?.timeIntervalSince1970 ?? 0 }

private func cappedAt(_ track: Timeline.Track, _ at: TimeInterval) -> Bool {
  (track.capped ?? []).contains { at >= instant($0.startedAt) && at < instant($0.endedAt) }
}

/// The total. Where a cap kept any plan from charging, a key to the rails: a solid line charges,
/// a dotted one is capped. Otherwise what the total is made of as one bar, each plan's share in
/// its colour.
struct ClipBillTotal: View {
  let total: Double
  let timeline: PrismBillTimeline?

  var body: some View {
    let anyCapped = timeline?.tracks.contains { !($0.capped ?? []).isEmpty } == true
    let parts = (timeline?.totals ?? []).filter { $0.amount > 0 }
    VStack(alignment: .leading, spacing: 4) {
      Text("合计").font(.subheadline).foregroundStyle(.secondary)
      Text(total.formatted(.number.precision(.fractionLength(2)))).font(.largeTitle.bold()).monospacedDigit()
      if anyCapped {
        HStack(spacing: 20) {
          legend("计费") { Capsule().fill(Color.secondary).frame(width: 3, height: 12) }
          legend("封顶中") { ClipRailLine(dotted: true).stroke(Color.secondary, style: ClipRailLine.style(dotted: true)).frame(width: 3, height: 12) }
        }
        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        .accessibilityElement(children: .combine).accessibilityLabel(Text("图例"))
      } else if parts.count > 1 {
        // One part is the whole: the bar only says something when there are two.
        VStack(alignment: .leading, spacing: 8) {
          GeometryReader { geometry in
            let sum = parts.reduce(0) { $0 + $1.amount }
            let usable = max(0, geometry.size.width - 2 * CGFloat(parts.count - 1))
            HStack(spacing: 2) {
              ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                Capsule().fill(color(part.name)).frame(width: usable * part.amount / max(sum, 0.01))
              }
            }
          }
          .frame(height: 8)
          .accessibilityHidden(true)
          ClipFlowRow(spacing: 16) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
              HStack(spacing: 6) {
                Circle().fill(color(part.name)).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(part.name).foregroundStyle(.secondary)
                Text(prismMoney(part.amount)).fontWeight(.medium)
              }.monospacedDigit()
            }
          }
          .font(.caption)
        }
        .padding(.top, 8)
      }
    }
  }

  private func legend<Mark: View>(_ title: LocalizedStringKey, @ViewBuilder mark: () -> Mark) -> some View {
    HStack(spacing: 8) { mark().accessibilityHidden(true); Text(title) }
  }

  private func color(_ name: String) -> Color {
    timeline?.tracks.first { $0.name == name }.map { prismPlanColor($0.color) } ?? Color.secondary
  }
}

/// The bill as one rail per plan, newest first. Every point on a rail ends the stretch below it: a
/// stretch that charged is a card at its end with what it charged; a stretch a full cap kept from
/// charging is dotted. The date is written once a day, on its first event.
struct ClipBillTimeline: View {
  let timeline: PrismBillTimeline

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(timeline.events.enumerated()), id: \.offset) { index, event in
        ClipBillEvent(
          event: event, tracks: timeline.tracks,
          newer: index > 0 ? timeline.events[index - 1].at : nil,
          older: index + 1 < timeline.events.count ? timeline.events[index + 1].at : nil
        )
      }
    }
  }
}

private let headings: [(String, LocalizedStringKey)] = [
  ("current", "现在"), ("end", "结束计费"), ("start", "开始计费"), ("switch", "切换计费规则"), ("over", "封顶结束"),
]

/// A rail's piece: a solid line, or a dotted one while a cap keeps the plan from charging.
private struct ClipRailLine: Shape {
  var dotted = false
  static func style(dotted: Bool) -> StrokeStyle {
    dotted ? StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0, 6]) : StrokeStyle(lineWidth: 3)
  }
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.midX, y: rect.minY + (dotted ? 1.5 : 0)))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    }
  }
}

private struct ClipBillEvent: View {
  let event: Timeline.Event
  let tracks: [Timeline.Track]
  let newer: String?
  let older: String?
  private var lanes: Int { max(1, (tracks.map(\.lane).max() ?? 0) + 1) }

  var body: some View {
    let kinds = Set(event.entries.map(\.kind))
    let heading = headings.first { kinds.contains($0.0) }?.1
    let day = { (at: String) in prismLocalDay(at) }
    let showDate = older.map { day($0) != day(event.at) } ?? true
    let startsOnly = event.entries.allSatisfy { $0.kind == "start" }
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        (Text(prismDisplayClock(event.at)) + (heading.map { Text(" · ") + Text($0) } ?? Text(verbatim: "")))
          .font(.subheadline.bold())
        Spacer(minLength: 8)
        if showDate { Text(prismDisplayDay(event.at)).font(.caption).foregroundStyle(.secondary) }
      }
      if startsOnly {
        ClipFlowRow(spacing: 16) {
          ForEach(Array(event.entries.enumerated()), id: \.offset) { _, entry in
            HStack(spacing: 6) {
              ClipPlanDot(color: color(entry.trackId))
              Text(entry.name)
              if let rule = entry.rule { Text(rule).foregroundStyle(.tertiary) }
            }
          }
        }
        .font(.subheadline)
      } else {
        ForEach(Array(event.entries.enumerated()), id: \.offset) { _, entry in
          ClipBillEntry(entry: entry, color: entry.trackId.map { color($0) })
        }
      }
    }
    .padding(.leading, CGFloat(lanes * 14 + 18)).padding(.bottom, older == nil ? 8 : 30)
    .background(alignment: .topLeading) { rails }
  }

  private func color(_ trackId: String?) -> Color {
    prismPlanColor(tracks.first { $0.id == trackId }?.color ?? 0)
  }

  private var rails: some View {
    let at = instant(event.at)
    let marked = Set(event.entries.flatMap { $0.kind == "full" && $0.trackId == nil ? $0.trackIds ?? [] : [] })
    return GeometryReader { proxy in
      ForEach(tracks) { track in
        let point = event.entries.contains { $0.trackId == track.id } || marked.contains(track.id)
        let above = newer != nil && instant(track.endedAt) > at && instant(track.startedAt) <= at
        let below = older != nil && instant(track.startedAt) < at && instant(track.endedAt) >= at
        let x = CGFloat(track.lane * 14 + 5)
        let hue = prismPlanColor(track.color)
        if above {
          let dotted = cappedAt(track, (at + instant(newer!)) / 2)
          ClipRailLine(dotted: dotted).stroke(hue.opacity(dotted ? 1 : 0.7), style: ClipRailLine.style(dotted: dotted))
            .frame(width: 3, height: 11).position(x: x, y: 5.5)
        }
        if below {
          let dotted = cappedAt(track, (at + instant(older!)) / 2)
          ClipRailLine(dotted: dotted).stroke(hue.opacity(dotted ? 1 : 0.7), style: ClipRailLine.style(dotted: dotted))
            .frame(width: 3, height: max(0, proxy.size.height - 11)).position(x: x, y: 11 + max(0, proxy.size.height - 11) / 2)
        }
        if marked.contains(track.id) {
          RoundedRectangle(cornerRadius: 3).fill(prismAccent)
            .overlay { RoundedRectangle(cornerRadius: 3).strokeBorder(Color(.systemGroupedBackground), lineWidth: 2).padding(-2) }
            .frame(width: 11, height: 13).position(x: x, y: 10.5)
        } else if point {
          Circle().fill(hue).frame(width: 9, height: 9).position(x: x, y: 11)
        }
      }
    }
    .accessibilityHidden(true)
  }
}

private struct ClipPlanDot: View {
  let color: Color
  var body: some View { Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true) }
}

/// One line of an event: a cap filling, a stretch that charged, a capped stretch's rule change,
/// or an adjustment.
private struct ClipBillEntry: View {
  let entry: Timeline.Entry
  let color: Color?
  @Environment(\.prismCardFill) private var cardFill

  var body: some View {
    if entry.kind == "start" {
      EmptyView()
    } else if entry.kind == "full", entry.trackId == nil {
      HStack(alignment: .firstTextBaseline) {
        Text(entry.name + String(localized: "已满")).fontWeight(.medium).foregroundStyle(prismAccent)
        Spacer(minLength: 12)
        if let until = entry.until {
          Text(String(localized: "封顶到") + " " + clock(until)).font(.caption).foregroundStyle(.secondary)
        }
      }
      .font(.footnote)
      .padding(.bottom, 8)
    } else if entry.trackId != nil, entry.capped == true || entry.amount == nil {
      // A stretch that charged nothing: only a change of rule, an end or now is worth a line.
      if ["switch", "split", "current", "end"].contains(entry.kind) {
        HStack(spacing: 8) {
          if let color { ClipPlanDot(color: color) }
          Text(entry.name).foregroundStyle(.primary.opacity(0.75))
          if let rule { Text(rule).foregroundStyle(.tertiary) }
        }
        .font(.footnote)
        .padding(.bottom, 6)
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          HStack(spacing: 8) {
            if let color { ClipPlanDot(color: color) }
            Text(entry.name).fontWeight(.medium)
            if entry.trackId != nil, let rule = entry.rule { Text(rule).font(.caption).foregroundStyle(.tertiary) }
          }
          Spacer(minLength: 8)
          if let amount = entry.amount {
            Text(amount.formatted(.number.precision(.fractionLength(2)))).fontWeight(.bold).monospacedDigit()
              .foregroundStyle(amount < 0 ? Color.green : Color.primary)
          }
        }
        .font(.subheadline)
        if entry.trackId != nil, let unitMinutes = entry.unitMinutes, let unitPrice = entry.unitPrice {
          HStack(spacing: 10) {
            if let fills = entry.unitFills, let color {
              ClipUnitBlocks(fills: fills, pending: entry.pending ?? nil, color: color)
            } else if let units = entry.units {
              Text(verbatim: "× " + units.formatted())
            }
            Text(prismMoney(unitPrice) + " / " + (unitMinutes == 60 ? String(localized: "小时") : unitMinutes.formatted() + " " + String(localized: "分钟")))
          }
          .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(cardFill, in: RoundedRectangle(cornerRadius: 14))
      .padding(.bottom, 6)
    }
  }

  private var rule: String? {
    guard let rule = entry.rule else { return nil }
    if let next = entry.nextRule { return rule + " → " + next }
    return entry.kind == "split" ? String(localized: "新的一天") : rule
  }

  /// A cap's end as a clock time; one ending at midnight ends at 24:00.
  private func clock(_ at: String) -> String {
    let time = prismDisplayClock(at)
    return time == "00:00" ? "24:00" : time
  }
}

/// A block per unit the stretch charged, filled as far as it was charged against its own price
/// (the unit that filled a cap only in part); a unit begun but still inside its grace is outlined.
private struct ClipUnitBlocks: View {
  let fills: [Double]
  let pending: Double?
  let color: Color

  var body: some View {
    if fills.count + (pending == nil ? 0 : 1) > 24 {
      Text(verbatim: "× \(fills.count)")
    } else {
      ClipFlowRow(spacing: 2, lineSpacing: 2) {
        ForEach(Array(fills.enumerated()), id: \.offset) { _, fill in
          block(fill: fill, outlined: false)
        }
        if let pending { block(fill: pending, outlined: true) }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: "× \(fills.count)"))
    }
  }

  private func block(fill: Double, outlined: Bool) -> some View {
    RoundedRectangle(cornerRadius: 2)
      .fill(outlined ? Color.clear : color.opacity(0.28))
      .overlay(alignment: .leading) {
        GeometryReader { geometry in
          Rectangle().fill(color.opacity(outlined ? 0.45 : 1)).frame(width: geometry.size.width * min(1, max(0, fill)))
        }
      }
      .overlay { if outlined { RoundedRectangle(cornerRadius: 2).strokeBorder(color, lineWidth: 1) } }
      .clipShape(RoundedRectangle(cornerRadius: 2))
      .frame(width: 8, height: 10)
  }
}

/// Children laid out in rows, wrapping when a row is full.
struct ClipFlowRow: Layout {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
    let width = rows.map { $0.width }.max() ?? 0
    let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
    return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(width: bounds.width, subviews: subviews) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + lineSpacing
    }
  }

  private func arrange(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
    var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(.unspecified)
      if let last = rows.last, last.width + spacing + size.width <= width {
        rows[rows.count - 1] = (last.indices + [index], last.width + spacing + size.width, max(last.height, size.height))
      } else {
        rows.append(([index], size.width, size.height))
      }
    }
    return rows
  }
}
