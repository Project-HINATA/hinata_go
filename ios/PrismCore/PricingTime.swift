import Foundation

/// Port of packages/core/src/pricing-time.ts: rule activity, anchors and
/// boundaries, the time plan's quote, history keys, the day timeline, and the
/// joint settlement of period caps and caps across plans (`settleTimeCaps`,
/// `settleTimeCapWindows`). Instants are epoch milliseconds (`PrismMs`).
enum PrismPricingTime {
  // MARK: Rules

  /// `activeRules(rules).sort((a, b) => b.priority - a.priority)` (stable).
  static func activeRules(_ rules: [PrismPricingRule]) -> [PrismPricingRule] {
    rules.filter { ($0.status ?? "active") == "active" }.prismSorted { a, b in b.priority - a.priority }
  }

  static func findActiveRule(_ date: PrismMs, _ rules: [PrismPricingRule], _ timeZone: String) throws -> PrismPricingRule? {
    for rule in rules where try isRuleActiveAt(date, rule, timeZone) { return rule }
    return nil
  }

  static func buildRuleHistoryKey(_ pricingConfigId: String, _ providerId: String, _ date: PrismMs, _ rule: PrismPricingRule, _ timeZone: String) throws -> String {
    "\(pricingConfigId)@\(providerId)@\(rule.historyRuleId ?? rule.id)@\(try PrismJS.isoString(try getRuleAnchor(date, rule, timeZone)))"
  }

  static func buildTimeCapHistoryKey(_ capConfigId: String, _ capRuleId: String, _ capAnchorAt: PrismMs) throws -> String {
    "\(capConfigId)@\(capRuleId)@\(try PrismJS.isoString(capAnchorAt))"
  }

  private static func noTimeRange() -> PrismDomainError {
    PrismDomainError("Time pricing rule has no time range.", "INVALID_TIME_PRICING_RULE")
  }

  static func getRuleAnchor(_ date: PrismMs, _ rule: PrismPricingRule, _ timeZone: String) throws -> PrismMs {
    if let anchorAt = rule.anchorAt { return anchorAt.prismMs }
    if let range = rule.dateTimeRange, rule.timeRange == nil { return range.start.prismMs }
    guard let timeRange = rule.timeRange else { throw noTimeRange() }
    let localDate = try PrismZones.formatLocalDate(date, timeZone)
    var anchorLocalDate = localDate
    let start = PrismZones.parseClockMinutes(timeRange.start)
    let end = PrismZones.parseClockMinutes(timeRange.end)
    let parts = try PrismZones.parts(date, timeZone)
    let current = Double(parts.hour * 60 + parts.minute)
    if start >= end && current < start { anchorLocalDate = PrismZones.addLocalDays(localDate, -1) }
    return try PrismZones.parseLocalDateTime(anchorLocalDate, timeRange.start, timeZone)
  }

  static func isRuleActiveAt(_ date: PrismMs, _ rule: PrismPricingRule, _ timeZone: String) throws -> Bool {
    if let range = rule.dateTimeRange {
      if date < range.start.prismMs || date >= range.end.prismMs { return false }
      if rule.timeRange == nil { return true }
    }
    guard let timeRange = rule.timeRange else { return false }
    return try isRuleDateMatch(date, rule, timeZone) && isTimeInRange(date, timeRange, timeZone)
  }

  static func findNextPriorityBoundary(_ cursor: PrismMs, _ endedAt: PrismMs, _ activeRule: PrismPricingRule,
                                       _ rules: [PrismPricingRule], _ timeZone: String) throws -> PrismMs {
    var boundary = minDate(try getRuleNaturalEnd(cursor, activeRule, timeZone), endedAt)
    for rule in rules {
      if rule.priority <= activeRule.priority { continue }
      let candidate = try getNextRuleActivationAfter(cursor, rule, timeZone)
      if candidate > cursor && candidate < boundary { boundary = candidate }
    }
    return boundary
  }

  static func getRuleNaturalEnd(_ cursor: PrismMs, _ rule: PrismPricingRule, _ timeZone: String) throws -> PrismMs {
    if let range = rule.dateTimeRange, rule.timeRange == nil { return range.end.prismMs }
    guard let timeRange = rule.timeRange else { throw noTimeRange() }
    let clockEnd = try parseNextClockTime(cursor, timeRange.end, timeZone)
    if let range = rule.dateTimeRange { return minDate(clockEnd, range.end.prismMs) }
    return clockEnd
  }

  static func getNextRuleActivationAfter(_ cursor: PrismMs, _ rule: PrismPricingRule, _ timeZone: String) throws -> PrismMs {
    if let range = rule.dateTimeRange, rule.timeRange == nil { return range.start.prismMs }
    guard let timeRange = rule.timeRange else { throw noTimeRange() }
    if let range = rule.dateTimeRange, range.start.prismMs > cursor, try isRuleActiveAt(range.start.prismMs, rule, timeZone) {
      return range.start.prismMs
    }
    let baseLocalDate = try PrismZones.formatLocalDate(cursor, timeZone)
    for dayOffset in 0...370 {
      let localDate = PrismZones.addLocalDays(baseLocalDate, Double(dayOffset))
      let candidate = try PrismZones.parseLocalDateTime(localDate, timeRange.start, timeZone)
      if candidate <= cursor { continue }
      if try isRuleActiveAt(candidate, rule, timeZone) { return candidate }
    }
    return .nan // new Date(Infinity): an invalid Date that never compares true
  }

  static func findNextAnyRuleActivationAfter(_ cursor: PrismMs, _ fallbackBoundary: PrismMs, _ rules: [PrismPricingRule], _ timeZone: String) throws -> PrismMs {
    var boundary = fallbackBoundary
    for rule in rules {
      let candidate = try getNextRuleActivationAfter(cursor, rule, timeZone)
      if candidate > cursor && candidate < boundary { boundary = candidate }
    }
    return boundary
  }

  static func isTimeInRange(_ date: PrismMs, _ range: PrismTimeRange, _ timeZone: String) throws -> Bool {
    let parts = try PrismZones.parts(date, timeZone)
    let current = Double(parts.hour * 60 + parts.minute)
    let start = PrismZones.parseClockMinutes(range.start)
    let end = PrismZones.parseClockMinutes(range.end)
    if start < end { return current >= start && current < end }
    return current >= start || current < end
  }

  static func isRuleDateMatch(_ date: PrismMs, _ rule: PrismPricingRule, _ timeZone: String) throws -> Bool {
    let parts = try PrismZones.parts(try getRuleDateMatchAnchor(date, rule, timeZone), timeZone)
    if let dates = rule.specificDates, !dates.contains(PrismZones.formatLocalDate(parts)) { return false }
    if let weekdays = rule.weekdays, !weekdays.contains(Double(parts.weekday)) { return false }
    return true
  }

  static func getRuleDateMatchAnchor(_ date: PrismMs, _ rule: PrismPricingRule, _ timeZone: String) throws -> PrismMs {
    guard let timeRange = rule.timeRange else { return date }
    let parts = try PrismZones.parts(date, timeZone)
    let current = Double(parts.hour * 60 + parts.minute)
    let start = PrismZones.parseClockMinutes(timeRange.start)
    let end = PrismZones.parseClockMinutes(timeRange.end)
    if start >= end && current < start {
      return try PrismZones.parseLocalDateTime(PrismZones.addLocalDays(PrismZones.formatLocalDate(parts), -1), timeRange.start, timeZone)
    }
    return date
  }

  static func parseNextClockTime(_ base: PrismMs, _ time: String, _ timeZone: String) throws -> PrismMs {
    let localDate = try PrismZones.formatLocalDate(base, timeZone)
    var date = try PrismZones.parseLocalDateTime(localDate, time, timeZone)
    if date <= base { date = try PrismZones.parseLocalDateTime(PrismZones.addLocalDays(localDate, 1), time, timeZone) }
    return date
  }

  static func minDate(_ a: PrismMs, _ b: PrismMs) -> PrismMs { a < b ? a : b }

  // MARK: Unit pricing

  /// A period cap of 0 leaves the period uncapped ("不限").
  static func periodCapOf(_ priceCap: Double) throws -> Int? {
    priceCap > 0 ? try PrismMoney.centsOf(priceCap) : nil
  }

  static func calculateUnits(_ durationMinutes: Double, _ config: PrismUnitPricing, _ invalidateFirstGrace: Bool) -> Double {
    var units = (max(0, durationMinutes) / config.unitMinutes).rounded(.down)
    let leftover = durationMinutes.truncatingRemainder(dividingBy: config.unitMinutes)
    // A partial unit rounds up once the leftover reaches the grace; exact multiples never do.
    if leftover > 0 && leftover >= config.roundGraceMinutes { units += 1 }
    if invalidateFirstGrace && units == 0 { units = 1 }
    return units
  }

  static func calculateRawUnitPrice(_ durationMinutes: Double, _ config: PrismUnitPricing, _ invalidateFirstGrace: Bool, ignoreCap: Bool = false) throws -> Int {
    let units = calculateUnits(durationMinutes, config, invalidateFirstGrace)
    let unitPrice = try PrismMoney.centsOf(config.unitPrice)
    let raw = try PrismMoney.mulDivRound(unitPrice, units, 1, .trunc)
    let cap = try periodCapOf(config.priceCap)
    return ignoreCap || cap == nil ? raw : min(raw, cap!)
  }

  static func calculateUnitPriceWithHistory(_ durationMinutes: Double, _ config: PrismUnitPricing, _ paidBefore: Int, _ invalidateFirstGrace: Bool) throws -> Int {
    if durationMinutes <= 0 && !invalidateFirstGrace { return 0 }
    let raw = try calculateRawUnitPrice(durationMinutes, config, invalidateFirstGrace, ignoreCap: true)
    guard raw > 0, let cap = try periodCapOf(config.priceCap) else { return raw }
    let effectiveTotal = min(try PrismMoney.add(paidBefore, raw), cap)
    return max(0, try PrismMoney.sub(effectiveTotal, paidBefore))
  }

  // MARK: Quotes

  static func quote(_ provider: PrismPricingProvider, session: PrismSession, now: PrismMs) throws -> [PrismChargeItem] {
    switch provider {
    case .priority(let config):
      return try quotePriority(config, session: session, now: now)
    case .fixed(let id, let label, let amount):
      return [PrismChargeItem(id: "\(session.id):\(id)", source: id, label: label ?? "", amount: try PrismMoney.centsOf(amount ?? .nan))]
    }
  }

  /// `createPriorityTimePricingProvider(config).quote(context)`.
  static func quotePriority(_ config: PrismPriorityTimeProviderConfig, session: PrismSession, now: PrismMs) throws -> [PrismChargeItem] {
    let rules = activeRules(config.rules)
    let timeZone = config.timeZone ?? "UTC"
    let endedAt = session.endedAt?.prismMs ?? now
    var charges: [PrismChargeItem] = []
    var paidHistory = config.paidHistory
    var cursor = session.startedAt.prismMs
    let hasDeviceActivity = session.hasDeviceActivity
    var effectiveEndedAt = endedAt
    if effectiveEndedAt <= cursor && hasDeviceActivity { effectiveEndedAt = cursor + 60_000 }
    var invalidateFirstGrace = hasDeviceActivity
    let pricingConfigId = config.pricingConfigId ?? config.id
    var guardCount = 0

    while cursor < effectiveEndedAt {
      guardCount += 1
      if guardCount > 1_000_000 { throw PrismDomainError("Time pricing quote cannot advance.", "TIME_PRICING_QUOTE_STALLED") }
      guard let rule = try findActiveRule(cursor, rules, timeZone) else {
        cursor = try findNextAnyRuleActivationAfter(cursor, effectiveEndedAt, rules, timeZone)
        continue
      }
      guard let pricing = rule.pricing else { throw PrismDomainError.typeError("Cannot read properties of undefined (reading 'priceCap')") }
      let nextBoundary = try findNextPriorityBoundary(cursor, effectiveEndedAt, rule, rules, timeZone)
      let durationMinutes = ((nextBoundary - cursor) / 60_000).rounded(.down)
      let historyKey = try buildRuleHistoryKey(pricingConfigId, config.id, cursor, rule, timeZone)
      let paidBefore = paidHistory[historyKey] ?? 0
      let amount = try calculateUnitPriceWithHistory(durationMinutes, pricing, paidBefore, invalidateFirstGrace)
      let units = calculateUnits(durationMinutes, pricing, invalidateFirstGrace)
      paidHistory[historyKey] = try PrismMoney.add(paidBefore, amount)
      if amount > 0 { invalidateFirstGrace = false }
      let period = PrismPeriod(startedAtMs: cursor, endedAtMs: nextBoundary)
      let cap = try periodCapOf(pricing.priceCap)
      charges.append(PrismChargeItem(
        id: "\(session.id):\(config.id):\(rule.id):\(try PrismJS.isoString(cursor))",
        sessionId: session.id,
        source: config.id,
        label: rule.label,
        amount: amount,
        period: period,
        pricingHistory: PrismPricingHistoryContribution(
          pricingConfigId: pricingConfigId, providerId: config.id, ruleId: rule.historyRuleId ?? rule.id,
          ruleAnchorAt: Date(prismMs: try getRuleAnchor(cursor, rule, timeZone)), amount: amount),
        pricingExplanation: PrismPricingSegmentExplanation(
          timeZone: timeZone, planName: config.name, pricing: pricing, paidBefore: PrismMoney.yuanOf(paidBefore), units: units,
          pricingConfigId: pricingConfigId, providerId: config.id, ruleId: rule.id, ruleLabel: rule.label, period: period,
          ruleTimeRange: rule.timeRange, intervalCap: pricing.priceCap,
          intervalCapReached: try cap != nil && PrismMoney.add(paidBefore, amount) >= cap!)))
      cursor = nextBoundary
    }
    return charges
  }

  /// `collectPriorityTimePricingHistoryLookupKeys`: the history keys a quote over [startedAt, endedAt) reads, in order.
  static func collectPriorityHistoryKeys(_ config: PrismPriorityTimeProviderConfig, startedAt: PrismMs, endedAt: PrismMs) throws -> [String] {
    let rules = activeRules(config.rules)
    let timeZone = config.timeZone ?? "UTC"
    var keys = PrismOrderedMap<String, Bool>()
    var cursor = startedAt
    while cursor < endedAt {
      guard let rule = try findActiveRule(cursor, rules, timeZone) else {
        cursor = try findNextAnyRuleActivationAfter(cursor, endedAt, rules, timeZone)
        continue
      }
      let nextBoundary = try findNextPriorityBoundary(cursor, endedAt, rule, rules, timeZone)
      keys[try buildRuleHistoryKey(config.pricingConfigId ?? config.id, config.id, cursor, rule, timeZone)] = true
      cursor = nextBoundary
    }
    return keys.keys
  }

  // MARK: Day timeline

  enum TimelineValue { case pricing, priceCap }

  /// `buildTimeRuleTimeline` (buildPriorityTimePricingTimeline / buildTimeCapPricingTimeline).
  static func buildTimeRuleTimeline(localDate: String, displayTimeZone: String?, rules allRules: [PrismPricingRule],
                                    timeZone configTimeZone: String?, value: TimelineValue) throws -> [PrismDaySegment] {
    let rules = activeRules(allRules)
    let timeZone = configTimeZone ?? "UTC"
    let displayTimeZone = displayTimeZone ?? timeZone
    let dayStart = try PrismZones.parseLocalDateTime(localDate, "00:00", displayTimeZone)
    let dayEnd = try PrismZones.parseLocalDateTime(PrismZones.addLocalDays(localDate, 1), "00:00", displayTimeZone)
    var segments: [PrismDaySegment] = []
    var cursor = dayStart
    while cursor < dayEnd {
      let rule = try findActiveRule(cursor, rules, timeZone)
      let nextBoundary = try rule.map { try findNextPriorityBoundary(cursor, dayEnd, $0, rules, timeZone) }
        ?? findNextAnyRuleActivationAfter(cursor, dayEnd, rules, timeZone)
      if nextBoundary <= cursor { throw PrismDomainError("Time pricing timeline cannot advance.", "TIME_PRICING_TIMELINE_STALLED") }
      let startMinute = try localMinuteOfDay(cursor, localDate, displayTimeZone)
      let endMinute = try localMinuteOfDay(nextBoundary, localDate, displayTimeZone)
      if let rule {
        var segment = PrismDaySegment(
          ruleId: rule.id, label: rule.label, priority: rule.priority.isFinite ? rule.priority : nil,
          startMinute: startMinute, endMinute: endMinute,
          startLabel: minuteLabel(startMinute), endLabel: minuteLabel(endMinute), isClosed: nil,
          startedAt: try PrismJS.isoString(cursor), endedAt: try PrismJS.isoString(nextBoundary),
          windowStartedAt: try PrismJS.isoString(try getRuleAnchor(cursor, rule, timeZone)),
          windowEndedAt: try PrismJS.isoString(try getRuleNaturalEnd(cursor, rule, timeZone)),
          pricing: nil, priceCap: nil)
        switch value {
        case .pricing:
          segment.pricing = rule.pricing.map {
            PrismDaySegment.Pricing(unitPrice: $0.unitPrice, unitMinutes: $0.unitMinutes, roundGraceMinutes: $0.roundGraceMinutes,
                                    priceCap: $0.priceCap.isNaN ? nil : $0.priceCap)
          }
        case .priceCap:
          segment.priceCap = rule.priceCap
        }
        segments.append(segment)
      } else {
        segments.append(PrismDaySegment(
          ruleId: "__closed__", label: "非营业", priority: nil, startMinute: startMinute, endMinute: endMinute,
          startLabel: minuteLabel(startMinute), endLabel: minuteLabel(endMinute), isClosed: true,
          startedAt: try PrismJS.isoString(cursor), endedAt: try PrismJS.isoString(nextBoundary),
          windowStartedAt: nil, windowEndedAt: nil, pricing: nil, priceCap: nil))
      }
      cursor = nextBoundary
    }
    var merged: [PrismDaySegment] = []
    for segment in segments {
      // A rule that starts a new window where the last one ended (a cap resetting at 06:00) stays two pieces.
      if var previous = merged.last, previous.ruleId == segment.ruleId, previous.endMinute == segment.startMinute,
         previous.windowStartedAt == segment.windowStartedAt {
        previous.endMinute = segment.endMinute
        previous.endLabel = segment.endLabel
        previous.endedAt = segment.endedAt
        merged[merged.count - 1] = previous
        continue
      }
      merged.append(segment)
    }
    return merged
  }

  static func localMinuteOfDay(_ date: PrismMs, _ localDate: String, _ timeZone: String) throws -> Int {
    let parts = try PrismZones.parts(date, timeZone)
    let dateString = PrismZones.formatLocalDate(parts)
    if dateString < localDate { return 0 }
    if dateString > localDate { return 1440 }
    return parts.hour * 60 + parts.minute
  }

  static func minuteLabel(_ minute: Int) -> String {
    if minute >= 1440 { return "24:00" }
    return "\(PrismJS.pad(minute / 60, 2)):\(PrismJS.pad(minute % 60, 2))"
  }

  // MARK: Caps

  /// One unit of a charge as the caps see it (`TimeCapUnit`). `item` indexes the
  /// charge list the settlement was given.
  struct CapUnit: Sendable {
    var item: Int
    var index: Int
    var at: PrismMs
    var nominal: Int
    var price: Int
    var charged: Int
    var heldBy: String?
  }

  struct CapSettlement: Sendable {
    var windows: [PrismTimeCapPricingWindow]
    var adjustments: [PrismSettlementAdjustment]
    var units: [CapUnit]
  }

  private struct CapWindowSpec {
    var key: String
    var capName: String?
    var capConfigId: String
    var capRuleId: String
    var ruleLabel: String
    var windowStartedAt: PrismMs
    var windowEndedAt: PrismMs
    var priceCap: Int
    var paidBefore: Int
    var includedPricingConfigIds: [String]
  }

  private struct KeyedUnit {
    var item: Int
    var index: Int
    var at: PrismMs
    var nominal: Int
    var price: Int
    var keys: [String]
  }

  static func capPlanOf(_ item: PrismChargeItem) -> String? { item.pricingHistory?.pricingConfigId }

  /// `settleTimeCaps`: every period cap and every cap across plans over the same charges, together.
  static func settleTimeCaps(configs: [PrismTimeCapProviderConfig], chargeItems: [PrismChargeItem], paidHistory: [String: Int]?) throws -> CapSettlement {
    var specs = PrismOrderedMap<String, CapWindowSpec>()
    var segments: [[[(key: String, from: PrismMs, to: PrismMs)]]] = chargeItems.map { _ in configs.map { _ in [] } }
    for (configIndex, config) in configs.enumerated() {
      let rules = activeRules(config.rules)
      let timeZone = config.timeZone ?? "UTC"
      let capConfigId = config.pricingConfigId ?? config.id
      let included = Set(config.includedPricingConfigIds)
      let history = paidHistory ?? config.paidHistory ?? [:]
      for (itemIndex, item) in chargeItems.enumerated() {
        guard let plan = capPlanOf(item), !plan.isEmpty, included.contains(plan), let period = item.period else { continue }
        var cursor = period.startedAtMs
        let endedAt = period.endedAtMs
        while cursor < endedAt {
          guard let rule = try findActiveRule(cursor, rules, timeZone) else {
            cursor = try findNextAnyRuleActivationAfter(cursor, endedAt, rules, timeZone)
            continue
          }
          let nextBoundary = try findNextPriorityBoundary(cursor, endedAt, rule, rules, timeZone)
          let capAnchorAt = try getRuleAnchor(cursor, rule, timeZone)
          let capRuleId = rule.historyRuleId ?? rule.id
          let key = try buildTimeCapHistoryKey(capConfigId, capRuleId, capAnchorAt)
          if !specs.has(key) {
            specs[key] = CapWindowSpec(
              key: key, capName: config.name, capConfigId: capConfigId, capRuleId: capRuleId, ruleLabel: rule.label,
              windowStartedAt: capAnchorAt, windowEndedAt: try getRuleNaturalEnd(capAnchorAt, rule, timeZone),
              priceCap: try PrismMoney.centsOf(rule.priceCap ?? .nan), paidBefore: history[key] ?? 0,
              includedPricingConfigIds: config.includedPricingConfigIds)
          }
          segments[itemIndex][configIndex].append((key, cursor, nextBoundary))
          cursor = nextBoundary
        }
      }
    }
    var units: [KeyedUnit] = []
    for (itemIndex, item) in chargeItems.enumerated() {
      let perConfig = segments[itemIndex]
      let cuts = perConfig.flatMap { $0 }.flatMap { [$0.from, $0.to] }
      for (index, piece) in try capUnitsOf(item, cuts).enumerated() {
        let keys = perConfig.flatMap { list in list.filter { piece.at >= $0.from && piece.at < $0.to }.map(\.key) }
        units.append(KeyedUnit(item: itemIndex, index: index, at: piece.at, nominal: piece.nominal, price: piece.price, keys: keys))
      }
    }
    return try settleUnits(specs.values, units, chargeItems)
  }

  /// `settleTimeCapWindows`: the same settlement replayed over windows already settled.
  static func settleTimeCapWindows(_ windows: [PrismTimeCapPricingWindow], _ chargeItems: [PrismChargeItem]) throws -> CapSettlement {
    let specs = windows.map { window -> CapWindowSpec in
      var included = PrismOrderedMap<String, Bool>()
      for contribution in window.contributions { included[contribution.pricingConfigId] = true }
      return CapWindowSpec(key: window.key, capName: window.capName, capConfigId: window.capConfigId, capRuleId: window.capRuleId,
                           ruleLabel: window.ruleLabel, windowStartedAt: window.windowStartedAt.prismMs,
                           windowEndedAt: window.windowEndedAt.prismMs, priceCap: window.priceCap, paidBefore: window.paidBefore,
                           includedPricingConfigIds: included.keys)
    }
    func holds(_ window: PrismTimeCapPricingWindow, _ item: PrismChargeItem) -> Bool {
      window.contributions.contains { $0.sessionId == item.sessionId && $0.pricingConfigId == capPlanOf(item) }
    }
    var units: [KeyedUnit] = []
    for (itemIndex, item) in chargeItems.enumerated() {
      let own = windows.filter { holds($0, item) }
      let cuts = own.flatMap { [$0.windowStartedAt.prismMs, $0.windowEndedAt.prismMs] }
      for (index, piece) in try capUnitsOf(item, cuts).enumerated() {
        let keys = own.filter { piece.at >= $0.windowStartedAt.prismMs && piece.at < $0.windowEndedAt.prismMs }.map(\.key)
        units.append(KeyedUnit(item: itemIndex, index: index, at: piece.at, nominal: piece.nominal, price: piece.price, keys: keys))
      }
    }
    return try settleUnits(specs, units, chargeItems)
  }

  /// `capUnitsOf`: a charge as units (or, without units, as pieces cut at the given edges).
  static func capUnitsOf(_ item: PrismChargeItem, _ cuts: [PrismMs]) throws -> [(at: PrismMs, nominal: Int, price: Int)] {
    guard let period = item.period else { return [] }
    let from = period.startedAtMs, to = period.endedAtMs
    if to <= from { return [] }
    if let starts = chargeUnitStarts(item), !starts.isEmpty {
      let nominal = try PrismMoney.centsOf(item.pricingExplanation!.pricing!.unitPrice)
      if try !(nominal > 0) || PrismMoney.mulDivRound(nominal, Double(starts.count), 1, .trunc) < item.amount {
        let prices = try PrismMoney.allocate(item.amount, starts.map { _ in 1 })
        return starts.enumerated().map { ($0.element, prices[$0.offset], prices[$0.offset]) }
      }
      var left = item.amount
      return try starts.map { at in
        let price = max(0, min(nominal, left))
        left = try PrismMoney.sub(left, price)
        return (at, nominal, price)
      }
    }
    var inner: [PrismMs] = []
    var seen = Set<PrismMs>()
    for at in cuts where at > from && at < to && !seen.contains(at) {
      seen.insert(at)
      inner.append(at)
    }
    var edges: [PrismMs] = [from]
    edges.append(contentsOf: inner.sorted())
    edges.append(to)
    var weights: [Double] = []
    for index in 0..<(edges.count - 1) { weights.append(edges[index + 1] - edges[index]) }
    let prices = try PrismMoney.allocate(item.amount, weights)
    var pieces: [(at: PrismMs, nominal: Int, price: Int)] = []
    for index in 0..<(edges.count - 1) { pieces.append((edges[index], prices[index], prices[index])) }
    return pieces
  }

  /// `chargeUnitStarts`: when each charged unit of a time charge starts; nil for a charge not made of units.
  static func chargeUnitStarts(_ item: PrismChargeItem) -> [PrismMs]? {
    guard let explanation = item.pricingExplanation, let pricing = explanation.pricing, let units = explanation.units,
          let period = item.period else { return nil }
    let start = period.startedAtMs, end = period.endedAtMs
    let step = pricing.unitMinutes * 60_000
    var starts: [PrismMs] = []
    var unit = 0.0
    while unit < units {
      let at = start + unit * step
      // A charge cut short (a live projection) has only the units begun before its end.
      if unit > 0 && at >= end { break }
      starts.append(at)
      unit += 1
    }
    return starts
  }

  private static func periodCapOfItem(_ item: PrismChargeItem) throws -> (key: String, allowance: Int)? {
    guard let explanation = item.pricingExplanation, explanation.pricing != nil, let history = item.pricingHistory,
          explanation.intervalCap > 0 else { return nil }
    let key = [item.sessionId ?? "", history.pricingConfigId, history.providerId, history.ruleId,
               try PrismJS.isoString(history.ruleAnchorAt.prismMs)].joined(separator: "\u{0}")
    let allowance = max(0, try PrismMoney.sub(try PrismMoney.centsOf(explanation.intervalCap), try PrismMoney.centsOf(explanation.paidBefore ?? 0)))
    return (key, allowance)
  }

  private final class WindowState {
    var allowance: Int
    var current = 0, applied = 0, held = 0
    var contributions = PrismOrderedMap<String, PrismTimeCapPricingWindow.Contribution>()
    init(allowance: Int) { self.allowance = allowance }
  }

  private static func settleUnits(_ specs: [CapWindowSpec], _ units: [KeyedUnit], _ items: [PrismChargeItem]) throws -> CapSettlement {
    var order: [String: Int] = [:]
    for (index, spec) in specs.enumerated() { order[spec.key] = index }
    var state: [String: WindowState] = [:]
    for spec in specs {
      // A window already over its cap takes nothing more, but still nets out a discount.
      state[spec.key] = WindowState(allowance: max(0, try PrismMoney.sub(spec.priceCap, spec.paidBefore)))
    }
    for unit in units where unit.price < 0 {
      for key in unit.keys { state[key]!.allowance = try PrismMoney.sub(state[key]!.allowance, unit.price) }
    }
    func periodStart(_ unit: KeyedUnit) -> Double { items[unit.item].period?.startedAtMs ?? 0 }
    // Each period cap, from the earliest charge in its window.
    var periods: [String: Int] = [:]
    for unit in units.prismSorted({ periodStart($0) - periodStart($1) }) {
      if let period = try periodCapOfItem(items[unit.item]), periods[period.key] == nil { periods[period.key] = period.allowance }
    }
    func nonZero(_ value: Double) -> Double? { value != 0 && !value.isNaN ? value : nil }
    let ordered = units.prismSorted { a, b in
      let ia = items[a.item], ib = items[b.item]
      return nonZero(a.at - b.at)
        ?? nonZero(Double(PrismJS.localeCompare(ia.sessionId ?? "", ib.sessionId ?? "")))
        ?? nonZero(Double(PrismJS.localeCompare(capPlanOf(ia) ?? "", capPlanOf(ib) ?? "")))
        ?? nonZero(periodStart(a) - periodStart(b))
        ?? Double(a.index - b.index)
    }
    var settled: [(charged: Int, heldBy: String?)] = []
    var settledIndex: [Int: Int] = [:] // position in `units` -> position in `settled`
    let positions = Dictionary(uniqueKeysWithValues: units.enumerated().map { ("\($0.element.item):\($0.element.index)", $0.offset) })
    for unit in ordered {
      let item = items[unit.item]
      let keys = unit.keys.prismSorted { Double(order[$0]! - order[$1]!) }
      let period = unit.nominal > 0 ? try periodCapOfItem(item) : nil
      let periodLeft = period.map { periods[$0.key]! }
      let limit = periodLeft == nil ? unit.nominal : min(unit.nominal, periodLeft!)
      var amount = unit.nominal > 0 ? limit : unit.price
      var binding: String? = nil
      if unit.nominal > 0 {
        for key in keys {
          let allowance = state[key]!.allowance
          if allowance < amount {
            amount = max(0, allowance)
            binding = key
          }
        }
      }
      let heldBy = unit.nominal > 0 && amount < unit.nominal ? (binding ?? "period") : nil
      settledIndex[positions["\(unit.item):\(unit.index)"]!] = settled.count
      settled.append((amount, heldBy))
      if let period { periods[period.key] = try PrismMoney.sub(periodLeft!, amount) }
      if let binding { state[binding]!.held = try PrismMoney.add(state[binding]!.held, try PrismMoney.sub(limit, amount)) }
      for key in keys {
        let window = state[key]!
        window.current = try PrismMoney.add(window.current, unit.price)
        window.applied = try PrismMoney.add(window.applied, amount)
        if unit.nominal > 0 { window.allowance = try PrismMoney.sub(window.allowance, amount) }
        guard let sessionId = item.sessionId, !sessionId.isEmpty else { continue }
        let plan = capPlanOf(item) ?? ""
        let contributionKey = "\(sessionId)\u{0}\(plan)"
        var contribution = window.contributions[contributionKey]
          ?? PrismTimeCapPricingWindow.Contribution(sessionId: sessionId, pricingConfigId: plan, amount: 0)
        contribution.amount = try PrismMoney.add(contribution.amount, amount)
        window.contributions[contributionKey] = contribution
      }
    }
    // What the caps across plans take off the quotes, split over the windows that bound units.
    var price = 0, charged = 0
    for (position, unit) in units.enumerated() {
      price = try PrismMoney.add(price, unit.price)
      charged = try PrismMoney.add(charged, settled[settledIndex[position]!].charged)
    }
    let takenOff = try PrismMoney.sub(price, charged)
    let weights = specs.map { Double(state[$0.key]!.held) }
    let shares = takenOff > 0 && weights.contains(where: { $0 > 0 })
      ? try PrismMoney.allocate(takenOff, weights)
      : specs.map { _ in 0 }
    var windows: [PrismTimeCapPricingWindow] = []
    for (index, spec) in specs.enumerated() {
      let window = state[spec.key]!
      windows.append(PrismTimeCapPricingWindow(
        key: spec.key, capName: spec.capName, capConfigId: spec.capConfigId, capRuleId: spec.capRuleId, ruleLabel: spec.ruleLabel,
        windowStartedAt: Date(prismMs: spec.windowStartedAt), windowEndedAt: Date(prismMs: spec.windowEndedAt),
        priceCap: spec.priceCap, paidBefore: spec.paidBefore, currentAmount: window.current, amountApplied: window.applied,
        heldBack: shares[index],
        contributions: window.contributions.values.prismSorted { a, b in
          let bySession = PrismJS.localeCompare(a.sessionId, b.sessionId)
          return Double(bySession != 0 ? bySession : PrismJS.localeCompare(a.pricingConfigId, b.pricingConfigId))
        }))
    }
    var adjustments: [PrismSettlementAdjustment] = []
    for (index, window) in windows.enumerated() {
      let amount = try PrismMoney.sub(0, window.heldBack ?? 0)
      if amount == 0 && !(window.amountApplied > 0) { continue }
      adjustments.append(PrismSettlementAdjustment(
        id: "time-cap:\(window.capConfigId):\(window.capRuleId):\(try PrismJS.isoString(window.windowStartedAt.prismMs))",
        source: "time.cap:\(window.capConfigId):\(window.capRuleId)",
        label: window.ruleLabel,
        amount: amount,
        pricingCapHistory: PrismPricingCapHistoryContribution(
          capConfigId: window.capConfigId, capRuleId: window.capRuleId, capAnchorAt: window.windowStartedAt,
          includedPricingConfigIds: specs[index].includedPricingConfigIds, amount: max(0, window.amountApplied))))
    }
    let resultUnits = ordered.enumerated().map { position, unit in
      CapUnit(item: unit.item, index: unit.index, at: unit.at, nominal: unit.nominal, price: unit.price,
              charged: settled[position].charged, heldBy: settled[position].heldBy)
    }
    return CapSettlement(windows: windows, adjustments: adjustments, units: resultUnits)
  }
}
