import Foundation

/// `BillTimeline` (packages/core/src/settlement.ts) exactly as `buildBillTimeline`
/// emits it after JSON.stringify: amounts in yuan, instants as ISO strings.
/// Decoding is lenient so receipts from older servers (fields missing, legacy
/// keys, a numeric `capped` on entries) still load; unknown keys are ignored.
struct PrismBillTimeline: Codable, Hashable, Sendable {
  struct Total: Codable, Hashable, Sendable {
    var name: String
    var amount: Double
  }

  struct Span: Codable, Hashable, Sendable {
    var startedAt: String
    var endedAt: String
  }

  struct Track: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var lane: Int
    var color: Int
    var startedAt: String
    var endedAt: String
    /// When a full cap kept this track from charging: drawn dashed.
    var capped: [Span]?

    init(id: String, name: String, lane: Int, color: Int, startedAt: String, endedAt: String, capped: [Span]?) {
      self.id = id
      self.name = name
      self.lane = lane
      self.color = color
      self.startedAt = startedAt
      self.endedAt = endedAt
      self.capped = capped
    }

    private enum CodingKeys: String, CodingKey { case id, name, lane, color, startedAt, endedAt, capped }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      id = try c.decode(String.self, forKey: .id)
      name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil ?? ""
      lane = Int((try? c.decodeIfPresent(Double.self, forKey: .lane)) ?? nil ?? 0)
      color = Int((try? c.decodeIfPresent(Double.self, forKey: .color)) ?? nil ?? 0)
      startedAt = (try? c.decodeIfPresent(String.self, forKey: .startedAt)) ?? nil ?? ""
      endedAt = (try? c.decodeIfPresent(String.self, forKey: .endedAt)) ?? nil ?? ""
      capped = (try? c.decodeIfPresent([Span].self, forKey: .capped)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      try c.encode(id, forKey: .id)
      try c.encode(name, forKey: .name)
      try c.encode(lane, forKey: .lane)
      try c.encode(color, forKey: .color)
      try c.encode(startedAt, forKey: .startedAt)
      try c.encode(endedAt, forKey: .endedAt)
      try c.encodeIfPresent(capped, forKey: .capped)
    }
  }

  struct Event: Codable, Hashable, Sendable {
    var at: String
    var time: String
    var date: String
    var entries: [Entry]

    private enum CodingKeys: String, CodingKey { case at, time, date, entries }

    init(at: String, time: String, date: String, entries: [Entry]) {
      self.at = at
      self.time = time
      self.date = date
      self.entries = entries
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      at = try c.decode(String.self, forKey: .at)
      time = (try? c.decodeIfPresent(String.self, forKey: .time)) ?? nil ?? ""
      date = (try? c.decodeIfPresent(String.self, forKey: .date)) ?? nil ?? ""
      entries = (try? c.decodeIfPresent([Entry].self, forKey: .entries)) ?? nil ?? []
    }
  }

  /// `BillTimelineEntry`. Keys TypeScript always writes are encoded (null when nil);
  /// the optional ones only when set — `pending` (which may be null) goes with `unitFills`.
  struct Entry: Codable, Hashable, Sendable {
    var trackId: String?
    /// `start`, `end`, `current`, `switch`, `split`, `full`, `over` or `adjustment`.
    var kind: String
    var name: String
    var rule: String?
    var nextRule: String?
    var periodLabel: String?
    /// What the stretch ending here charged (yuan); nil where it was capped or did not charge.
    var amount: Double?
    var startedAt: String?
    var endedAt: String?
    var unitMinutes: Double?
    var unitPrice: Double?
    var units: Double?
    var cap: Double?
    var paidBefore: Double?
    var counted: Double?
    /// Each unit charged in the stretch, as the share of its own price it was charged.
    var unitFills: [Double]?
    /// The unit begun but not charged yet (inside its grace), as the share of it that has passed.
    var pending: Double?
    /// The stretch ending here was capped: nothing to charge, the line is dashed.
    var capped: Bool?
    /// On `full`: the tracks the cap keeps from charging.
    var trackIds: [String]?
    /// On `full`: when the cap's window ends.
    var until: String?

    init(trackId: String? = nil, kind: String, name: String, rule: String? = nil, nextRule: String? = nil,
         periodLabel: String? = nil, amount: Double? = nil, startedAt: String? = nil, endedAt: String? = nil,
         unitMinutes: Double? = nil, unitPrice: Double? = nil, units: Double? = nil, cap: Double? = nil,
         paidBefore: Double? = nil, counted: Double? = nil, unitFills: [Double]? = nil, pending: Double? = nil,
         capped: Bool? = nil, trackIds: [String]? = nil, until: String? = nil) {
      self.trackId = trackId
      self.kind = kind
      self.name = name
      self.rule = rule
      self.nextRule = nextRule
      self.periodLabel = periodLabel
      self.amount = amount
      self.startedAt = startedAt
      self.endedAt = endedAt
      self.unitMinutes = unitMinutes
      self.unitPrice = unitPrice
      self.units = units
      self.cap = cap
      self.paidBefore = paidBefore
      self.counted = counted
      self.unitFills = unitFills
      self.pending = pending
      self.capped = capped
      self.trackIds = trackIds
      self.until = until
    }

    private enum CodingKeys: String, CodingKey {
      case trackId, kind, name, rule, nextRule, periodLabel, amount, startedAt, endedAt, unitMinutes, unitPrice, units, cap,
           paidBefore, counted, unitFills, pending, capped, trackIds, until
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      func string(_ key: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil }
      func number(_ key: CodingKeys) -> Double? { (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil }
      trackId = string(.trackId)
      kind = string(.kind) ?? ""
      name = string(.name) ?? ""
      rule = string(.rule)
      nextRule = string(.nextRule)
      periodLabel = string(.periodLabel)
      amount = number(.amount)
      startedAt = string(.startedAt)
      endedAt = string(.endedAt)
      unitMinutes = number(.unitMinutes)
      unitPrice = number(.unitPrice)
      units = number(.units)
      cap = number(.cap)
      paidBefore = number(.paidBefore)
      counted = number(.counted)
      unitFills = (try? c.decodeIfPresent([Double].self, forKey: .unitFills)) ?? nil
      pending = number(.pending)
      capped = (try? c.decodeIfPresent(Bool.self, forKey: .capped)) ?? nil
      trackIds = (try? c.decodeIfPresent([String].self, forKey: .trackIds)) ?? nil
      until = string(.until)
    }

    func encode(to encoder: Encoder) throws {
      var c = encoder.container(keyedBy: CodingKeys.self)
      func always<T: Encodable>(_ value: T?, _ key: CodingKeys) throws {
        if let value { try c.encode(value, forKey: key) } else { try c.encodeNil(forKey: key) }
      }
      try always(trackId, .trackId)
      try c.encode(kind, forKey: .kind)
      try c.encode(name, forKey: .name)
      try always(rule, .rule)
      try always(nextRule, .nextRule)
      try always(periodLabel, .periodLabel)
      try always(amount, .amount)
      try always(startedAt, .startedAt)
      try always(endedAt, .endedAt)
      try always(unitMinutes, .unitMinutes)
      try always(unitPrice, .unitPrice)
      try always(units, .units)
      try always(cap, .cap)
      try always(paidBefore, .paidBefore)
      try always(counted, .counted)
      try c.encodeIfPresent(unitFills, forKey: .unitFills)
      if unitFills != nil || pending != nil { try always(pending, .pending) }
      try c.encodeIfPresent(capped, forKey: .capped)
      try c.encodeIfPresent(trackIds, forKey: .trackIds)
      try c.encodeIfPresent(until, forKey: .until)
    }
  }

  var pricingReleaseIds: [String]?
  var totals: [Total]
  var tracks: [Track]
  var events: [Event]

  init(pricingReleaseIds: [String]? = nil, totals: [Total], tracks: [Track], events: [Event]) {
    self.pricingReleaseIds = pricingReleaseIds
    self.totals = totals
    self.tracks = tracks
    self.events = events
  }

  private enum CodingKeys: String, CodingKey { case pricingReleaseIds, totals, tracks, events }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    pricingReleaseIds = (try? c.decodeIfPresent([String].self, forKey: .pricingReleaseIds)) ?? nil
    totals = (try? c.decodeIfPresent([Total].self, forKey: .totals)) ?? nil ?? []
    tracks = (try? c.decodeIfPresent([Track].self, forKey: .tracks)) ?? nil ?? []
    events = (try? c.decodeIfPresent([Event].self, forKey: .events)) ?? nil ?? []
  }

  static let empty = PrismBillTimeline(totals: [], tracks: [], events: [])
}

/// The raw input of a bill timeline as the server returns it for previews and
/// receipts: JSON.stringify of `{ at, sessions, adjustments, globalCapWindows }`
/// (cents, ISO instants).
struct PrismBillInputs: Decodable, Sendable {
  struct Session: Codable, Sendable {
    var sessionId: String
    var label: String?
    @PrismISODate var startedAt: Date
    @PrismOptionalISODate var endedAt: Date?
    var chargeItems: [PrismChargeItem]
  }

  @PrismISODate var at: Date
  var sessions: [Session]
  var adjustments: [PrismSettlementAdjustment]
  var globalCapWindows: [PrismTimeCapPricingWindow]

  init(at: Date, sessions: [Session], adjustments: [PrismSettlementAdjustment], globalCapWindows: [PrismTimeCapPricingWindow]) {
    self.at = at
    self.sessions = sessions
    self.adjustments = adjustments
    self.globalCapWindows = globalCapWindows
  }

  private enum CodingKeys: String, CodingKey { case at, sessions, adjustments, globalCapWindows }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    _at = try c.decode(PrismISODate.self, forKey: .at)
    sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
    adjustments = try c.decodeIfPresent([PrismSettlementAdjustment].self, forKey: .adjustments) ?? []
    globalCapWindows = try c.decodeIfPresent([PrismTimeCapPricingWindow].self, forKey: .globalCapWindows) ?? []
  }
}

/// `buildBillTimeline(inputs)` (application/src/bill-timeline.ts). `timeZone` is the
/// fallback display zone used when no charge carries one (TS `input.timeZone`).
/// Returns an empty timeline if the inputs cannot be laid out (TS would throw).
func prismBuildBillTimeline(_ inputs: PrismBillInputs, timeZone: String? = nil) -> PrismBillTimeline {
  (try? prismBuildBillTimelineOrThrow(inputs, timeZone: timeZone)) ?? .empty
}

func prismBuildBillTimelineOrThrow(_ inputs: PrismBillInputs, timeZone: String? = nil) throws -> PrismBillTimeline {
  try prismBuildBillTimeline(at: inputs.at, timeZone: timeZone, planNames: nil, sessions: inputs.sessions,
                             adjustments: inputs.adjustments, globalCapWindows: inputs.globalCapWindows)
}

/// The engine-typed overload the checkout preview uses.
func prismBuildBillTimeline(at: Date, timeZone: String?, planNames: [String: String]?, sessions: [PrismBillInputs.Session],
                            adjustments: [PrismSettlementAdjustment], globalCapWindows: [PrismTimeCapPricingWindow]) throws -> PrismBillTimeline {
  try PrismBillTimelineBuilder(at: at.prismMs, planNames: planNames, sessions: sessions, fallbackTimeZone: timeZone,
                               adjustments: adjustments, windows: globalCapWindows).build()
}

private struct PrismBillTimelineBuilder {
  enum Role: String { case start, `switch`, split, full, over, end, current }

  struct Track {
    var id: String
    var name: String
    var lane = 0
    var color: Int
    var startedAt: String
    var endedAt: String
    var capped: [(from: PrismMs, to: PrismMs)] = []
    var from: PrismMs
    var to: PrismMs
    var live: Bool
    var items: [Int]
  }

  struct Fill {
    var at: PrismMs
    var until: PrismMs
    var label: String
    var trackIds: [String]
  }

  struct Row {
    var trackId: String?
    var kind: String
    var name: String
    var rule: String?
    var nextRule: String?
    var periodLabel: String?
    var amount: Int?
    var startedAt: String?
    var endedAt: String?
    var unitMinutes: Double?
    var unitPrice: Double?
    var units: Double?
    var unitFills: [Double]?
    var pending: Double?
    var capped: Bool?
    var trackIds: [String]?
    var until: String?
  }

  struct StretchKey: Hashable { var trackId: String; var point: PrismMs }

  let at: PrismMs
  let planNames: [String: String]?
  let sessions: [PrismBillInputs.Session]
  let fallbackTimeZone: String?
  let adjustments: [PrismSettlementAdjustment]
  let windows: [PrismTimeCapPricingWindow]

  func build() throws -> PrismBillTimeline {
    // Every charge, numbered: the number stands in for the object identity TypeScript keys maps by.
    var items: [PrismChargeItem] = []
    var owned: [PrismChargeItem] = []
    var sessionItems: [[Int]] = []
    for session in sessions {
      var indices: [Int] = []
      for item in session.chargeItems {
        indices.append(items.count)
        items.append(item)
        var copy = item
        if (item.sessionId ?? "").isEmpty { copy.sessionId = session.sessionId }
        owned.append(copy)
      }
      sessionItems.append(indices)
    }
    let timeZone = items.first(where: { !($0.pricingExplanation?.timeZone ?? "").isEmpty })?.pricingExplanation?.timeZone
      ?? fallbackTimeZone ?? "UTC"
    func local(_ ms: PrismMs) throws -> (date: String, time: String) { try PrismZones.displayParts(ms, timeZone) }
    func iso(_ ms: PrismMs) throws -> String { try PrismJS.isoString(ms) }

    // Replay the caps as settlement applied them, unit by unit.
    let settled = try PrismPricingTime.settleTimeCapWindows(windows, owned)
    var unitsOf = PrismOrderedMap<Int, [PrismPricingTime.CapUnit]>()
    for unit in settled.units { unitsOf[unit.item] = (unitsOf[unit.item] ?? []) + [unit] }

    var tracks: [Track] = []
    for (sessionIndex, session) in sessions.enumerated() {
      var groups = PrismOrderedMap<String, [Int]>()
      for index in sessionItems[sessionIndex] {
        let item = items[index]
        let id = item.pricingExplanation?.pricingConfigId ?? item.source
        groups[id] = (groups[id] ?? []) + [index]
      }
      // Zero-charge sessions still have a visible start/stop pair.
      if groups.count == 0 { groups[session.sessionId] = [] }
      for (configId, groupItems) in groups.entries {
        let to = (session.endedAt ?? Date(prismMs: at)).prismMs
        let first = groupItems.first.map { items[$0] }
        let labelName: String? = session.label == "entry" ? "入场计费" : session.label
        let name = first?.pricingExplanation?.planName ?? planNames?[configId] ?? labelName ?? first?.label ?? "计费"
        let from = session.startedAt.prismMs
        tracks.append(Track(
          id: "\(session.sessionId):\(configId)", name: name, color: tracks.count, startedAt: try iso(from), endedAt: try iso(to),
          from: from, to: to, live: session.endedAt == nil,
          items: groupItems.prismSorted { (items[$0].period?.startedAtMs ?? 0) - (items[$1].period?.startedAtMs ?? 0) }))
      }
    }
    func trackOf(_ item: Int) -> Int { tracks.firstIndex { $0.items.contains(item) }! }
    // A charge with no period (a fixed charge, a charge saved before periods were) is not
    // laid along the track: it is a line of its own where the track ends.
    func timeless(_ track: Track) -> [Int] { track.items.filter { items[$0].period == nil } }

    // Caps filling: a cap across plans at the first unit it stopped, over every track it holds;
    // a period cap at the first unit it stopped, over its own track until its rule's window ends.
    var fills: [Fill] = []
    for window in windows {
      guard let first = settled.units.filter({ $0.heldBy == window.key }).prismSorted({ $0.at - $1.at }).first else { continue }
      let capName = window.capName ?? planNames?[window.capConfigId] ?? "全局封顶"
      fills.append(Fill(
        at: first.at, until: window.windowEndedAt.prismMs, label: "\(capName)（\(window.ruleLabel)）",
        trackIds: tracks.filter { track in window.contributions.contains { "\($0.sessionId):\($0.pricingConfigId)" == track.id } }.map(\.id)))
    }
    for track in tracks {
      for index in track.items {
        if let first = (unitsOf[index] ?? []).first(where: { $0.heldBy == "period" }) {
          fills.append(Fill(at: first.at, until: ruleWindowEnd(items[index]), label: "时段封顶（\(track.name) \(items[index].label)）", trackIds: [track.id]))
        }
      }
    }
    for t in tracks.indices {
      let track = tracks[t]
      let spans = fills.filter { $0.trackIds.contains(track.id) }
        .map { (max($0.at, track.from), min($0.until, track.to)) }
        .filter { $0.1 > $0.0 }
      var merged: [(from: PrismMs, to: PrismMs)] = []
      for (from, to) in spans.prismSorted({ $0.0 - $1.0 }) {
        if let last = merged.last, from <= last.to { merged[merged.count - 1].to = max(last.to, to) } else { merged.append((from, to)) }
      }
      tracks[t].capped = merged
    }
    func isCapped(_ track: Track, _ at: PrismMs) -> Bool { track.capped.contains { at >= $0.from && at < $0.to } }

    // Every point where a track changes.
    var roles: [[PrismMs: Set<Role>]] = tracks.map { _ in [:] }
    func mark(_ t: Int, _ at: PrismMs, _ role: Role) { roles[t][at, default: []].insert(role) }
    for (t, track) in tracks.enumerated() {
      mark(t, track.from, .start)
      for (position, index) in track.items.enumerated() {
        guard let period = items[index].period else { continue }
        if position > 0 { mark(t, period.startedAtMs, items[track.items[position - 1]].label == items[index].label ? .split : .switch) }
        // A rule that ends with no rule after it (closed hours) ends the charging there, not at the next point.
        let next = position + 1 < track.items.count ? (items[track.items[position + 1]].period?.startedAtMs ?? track.to) : track.to
        let end = period.endedAtMs
        if next - end >= 60_000 && end > track.from { mark(t, end, .end) }
      }
      for fill in fills where fill.trackIds.contains(track.id) && fill.at >= track.from && fill.at < track.to { mark(t, fill.at, .full) }
      for span in track.capped where span.to < track.to { mark(t, span.to, .over) }
      mark(t, track.to, track.live ? .current : .end)
    }
    func pointsOf(_ t: Int) -> [PrismMs] { roles[t].keys.sorted() }

    // A unit counts in the stretch it began in; the unit that filled a cap, in the stretch the fill ends.
    var stretch: [StretchKey: [PrismPricingTime.CapUnit]] = [:]
    for (index, units) in unitsOf.entries {
      let t = trackOf(index)
      let points = pointsOf(t)
      for unit in units where unit.charged != 0 {
        let at = unit.at - (isCapped(tracks[t], unit.at) ? 1 : 0)
        let end = points.first { $0 > at } ?? tracks[t].to
        stretch[StretchKey(trackId: tracks[t].id, point: end), default: []].append(unit)
      }
    }
    func ruleAt(_ track: Track, _ at: PrismMs) -> Int? {
      track.items.first { index in
        guard let period = items[index].period else { return false }
        return period.startedAtMs <= at && period.endedAtMs > at
      } ?? track.items.filter { index in
        guard let period = items[index].period else { return false }
        return period.startedAtMs <= at
      }.last
    }

    var events = PrismOrderedMap<String, [Row]>()
    func add(_ at: PrismMs, _ entry: Row) throws {
      var row = entry
      if let startedAt = row.startedAt, let endedAt = row.endedAt, !startedAt.isEmpty, !endedAt.isEmpty {
        let start = try local(PrismJS.parseDate(startedAt)), end = try local(PrismJS.parseDate(endedAt))
        row.periodLabel = start.date == end.date
          ? "\(start.time) – \(end.time)"
          : "\(start.date.dropFirst(5)) \(start.time) – \(end.date.dropFirst(5)) \(end.time)"
      }
      let key = try iso(at)
      events[key] = (events[key] ?? []) + [row]
    }
    for fill in fills where !(fill.at >= at) {
      try add(fill.at, Row(kind: "full", name: fill.label, trackIds: fill.trackIds, until: try iso(fill.until)))
    }
    // Each plan at what it was charged, every unit counted once.
    var totals = PrismOrderedMap<String, Int>()
    for (index, units) in unitsOf.entries {
      let name = tracks[trackOf(index)].name
      var sum = totals[name] ?? 0
      for unit in units { sum = try PrismMoney.add(sum, unit.charged) }
      totals[name] = sum
    }
    for track in tracks {
      for index in timeless(track) { totals[track.name] = try PrismMoney.add(totals[track.name] ?? 0, items[index].amount) }
    }
    let order: [Role] = [.current, .end, .switch, .split, .full, .over]
    for (t, track) in tracks.enumerated() {
      let points = pointsOf(t)
      for (position, point) in points.enumerated() {
        let here = roles[t][point]!
        if position == 0 {
          try add(point, Row(trackId: track.id, kind: "start", name: track.name, rule: (ruleAt(track, point) ?? track.items.first).map { items[$0].label }))
          continue
        }
        let lines = point == track.to ? timeless(track) : []
        func listLines() throws {
          for index in lines {
            try add(point, Row(trackId: track.id, kind: track.live ? "current" : "end", name: track.name, rule: items[index].label, amount: items[index].amount))
          }
        }
        let from = points[position - 1]
        let kind = order.first { here.contains($0) }?.rawValue ?? ""
        let ruleIndex = ruleAt(track, from)
        let rule = ruleIndex.map { items[$0] }
        let next = here.contains(.switch) ? ruleAt(track, point).map { items[$0].label } : nil
        let units = (stretch[StretchKey(trackId: track.id, point: point)] ?? []).prismSorted { $0.at - $1.at }
        let priced = rule?.period.map { $0.startedAtMs < point && $0.endedAtMs > from } ?? false
        let cappedHere = isCapped(track, (from + point) / 2)
        if units.isEmpty && (cappedHere || !priced) {
          // A capped stretch, or one with no rule charging, states only where its rule changes, ends or is now;
          // where the track ends with charges of no period, those say it.
          if !lines.isEmpty && rule == nil { try listLines(); continue }
          try add(point, Row(trackId: track.id, kind: kind, name: track.name, rule: rule?.label, nextRule: next, capped: cappedHere))
          try listLines()
          continue
        }
        var amount = 0
        for unit in units { amount = try PrismMoney.add(amount, unit.charged) }
        let pricing = rule?.pricingExplanation?.pricing
        // The unit begun at the end of a running stretch but still inside its grace.
        var pending: Double? = nil
        if kind == "current", let pricing, let period = rule?.period, let ruleIndex {
          let step = pricing.unitMinutes * 60_000
          let charged = Double((unitsOf[ruleIndex] ?? []).count)
          let begun = period.startedAtMs + charged * step
          if begun < point && point - begun < step { pending = (point - begun) / step }
        }
        try add(point, Row(
          trackId: track.id, kind: kind, name: track.name, rule: rule?.label, nextRule: next, amount: amount,
          startedAt: try iso(from), endedAt: try iso(min(point, rule?.period?.endedAtMs ?? point)),
          unitMinutes: pricing?.unitMinutes, unitPrice: pricing?.unitPrice, units: Double(units.count),
          unitFills: units.map { $0.nominal > 0 ? min(1, Double($0.charged) / Double($0.nominal)) : 1 },
          pending: pending))
        try listLines()
      }
    }
    // Adjustments other than caps across plans (offers, price overrides) stay lines of their own.
    for adjustment in adjustments where adjustment.amount != 0 && adjustment.pricingCapHistory == nil {
      try add(at, Row(kind: "adjustment", name: adjustment.label, amount: adjustment.amount))
      totals[adjustment.label] = try PrismMoney.add(totals[adjustment.label] ?? 0, adjustment.amount)
    }
    var lanes: [String] = []
    let laneOrder = tracks.indices.map { $0 }.prismSorted { a, b in
      let byStart = PrismJS.localeCompare(tracks[a].startedAt, tracks[b].startedAt)
      return Double(byStart != 0 ? byStart : PrismJS.localeCompare(tracks[a].id, tracks[b].id))
    }
    for t in laneOrder {
      var lane = lanes.firstIndex { $0 <= tracks[t].startedAt } ?? -1
      if lane < 0 { lane = lanes.count }
      tracks[t].lane = lane
      if lane == lanes.count { lanes.append(tracks[t].endedAt) } else { lanes[lane] = tracks[t].endedAt }
    }

    let sortedEvents = events.entries.prismSorted { a, b in Double(PrismJS.localeCompare(b.key, a.key)) }
    return PrismBillTimeline(
      totals: totals.entries.filter { $0.value != 0 }.map { PrismBillTimeline.Total(name: $0.key, amount: PrismMoney.yuanOf($0.value)) },
      tracks: try tracks.map { track in
        PrismBillTimeline.Track(id: track.id, name: track.name, lane: track.lane, color: track.color, startedAt: track.startedAt,
                                endedAt: track.endedAt, capped: try track.capped.map { PrismBillTimeline.Span(startedAt: try iso($0.from), endedAt: try iso($0.to)) })
      },
      events: try sortedEvents.map { key, rows in
        let parts = try local(PrismJS.parseDate(key))
        return PrismBillTimeline.Event(at: key, time: parts.time, date: parts.date, entries: rows.map { row in
          PrismBillTimeline.Entry(
            trackId: row.trackId, kind: row.kind, name: row.name, rule: row.rule, nextRule: row.nextRule, periodLabel: row.periodLabel,
            amount: row.amount.map(PrismMoney.yuanOf), startedAt: row.startedAt, endedAt: row.endedAt, unitMinutes: row.unitMinutes,
            unitPrice: row.unitPrice, units: row.units, cap: nil, paidBefore: nil, counted: nil, unitFills: row.unitFills,
            pending: row.pending, capped: row.capped, trackIds: row.trackIds, until: row.until)
        })
      })
  }

  /// When a rule's window ends: its anchor plus the length of its clock range.
  func ruleWindowEnd(_ item: PrismChargeItem) -> PrismMs {
    guard let range = item.pricingExplanation?.ruleTimeRange, let anchor = item.pricingHistory?.ruleAnchorAt else {
      return item.period?.endedAtMs ?? 0
    }
    func slice(_ text: String, _ start: Int, _ end: Int) -> String {
      let units = Array(text.utf16)
      let lower = min(start, units.count), upper = min(end, units.count)
      return String(decoding: units[lower..<max(lower, upper)], as: UTF16.self)
    }
    func minutes(_ clock: String) -> Double { PrismJS.number(slice(clock, 0, 2)) * 60 + PrismJS.number(slice(clock, 3, 5)) }
    var length = (minutes(range.end) - minutes(range.start) + 1440).truncatingRemainder(dividingBy: 1440)
    if length == 0 || length.isNaN { length = 1440 }
    return anchor.prismMs + length * 60_000
  }
}
