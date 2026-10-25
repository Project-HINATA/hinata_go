import Foundation

/// One piece of a plan's day as the scan page draws it (`Segment` in
/// prism-web/src/ui/merchant/PricingRing.tsx, i.e. `PriorityTimePricingTimelineSegment`).
struct PrismDaySegment: Codable, Hashable, Sendable {
  struct Pricing: Codable, Hashable, Sendable {
    /// Yuan, snapped to whole cents (roundMoney).
    var unitPrice: Double
    var unitMinutes: Double
    var roundGraceMinutes: Double
    /// The period cap in yuan; 0 means uncapped.
    var priceCap: Double?
  }

  var ruleId: String
  var label: String
  /// The rule's priority; nil for a closed piece (TypeScript's -Infinity, which JSON writes as null).
  var priority: Double?
  var startMinute: Int
  var endMinute: Int
  var startLabel: String
  var endLabel: String
  var isClosed: Bool?
  var startedAt: String?
  var endedAt: String?
  /// The rule's window this piece belongs to; it can start before or end after the day.
  var windowStartedAt: String?
  var windowEndedAt: String?
  var pricing: Pricing?
  /// A cap plan's cap across plans for this window, yuan.
  var priceCap: Double?

  private enum CodingKeys: String, CodingKey {
    case ruleId, label, priority, startMinute, endMinute, startLabel, endLabel, isClosed, startedAt, endedAt,
         windowStartedAt, windowEndedAt, pricing, priceCap
  }

  init(ruleId: String, label: String, priority: Double?, startMinute: Int, endMinute: Int, startLabel: String, endLabel: String,
       isClosed: Bool?, startedAt: String?, endedAt: String?, windowStartedAt: String?, windowEndedAt: String?,
       pricing: Pricing?, priceCap: Double?) {
    self.ruleId = ruleId
    self.label = label
    self.priority = priority
    self.startMinute = startMinute
    self.endMinute = endMinute
    self.startLabel = startLabel
    self.endLabel = endLabel
    self.isClosed = isClosed
    self.startedAt = startedAt
    self.endedAt = endedAt
    self.windowStartedAt = windowStartedAt
    self.windowEndedAt = windowEndedAt
    self.pricing = pricing
    self.priceCap = priceCap
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    ruleId = try c.decode(String.self, forKey: .ruleId)
    label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    priority = (try? c.decodeIfPresent(Double.self, forKey: .priority)) ?? nil
    startMinute = Int(try c.decode(Double.self, forKey: .startMinute))
    endMinute = Int(try c.decode(Double.self, forKey: .endMinute))
    startLabel = try c.decodeIfPresent(String.self, forKey: .startLabel) ?? ""
    endLabel = try c.decodeIfPresent(String.self, forKey: .endLabel) ?? ""
    isClosed = try c.decodeIfPresent(Bool.self, forKey: .isClosed)
    startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt)
    endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt)
    windowStartedAt = try c.decodeIfPresent(String.self, forKey: .windowStartedAt)
    windowEndedAt = try c.decodeIfPresent(String.self, forKey: .windowEndedAt)
    pricing = try c.decodeIfPresent(Pricing.self, forKey: .pricing)
    priceCap = try c.decodeIfPresent(Double.self, forKey: .priceCap)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(ruleId, forKey: .ruleId)
    try c.encode(label, forKey: .label)
    if let priority { try c.encode(priority, forKey: .priority) } else { try c.encodeNil(forKey: .priority) }
    try c.encode(startMinute, forKey: .startMinute)
    try c.encode(endMinute, forKey: .endMinute)
    try c.encode(startLabel, forKey: .startLabel)
    try c.encode(endLabel, forKey: .endLabel)
    try c.encodeIfPresent(isClosed, forKey: .isClosed)
    try c.encodeIfPresent(startedAt, forKey: .startedAt)
    try c.encodeIfPresent(endedAt, forKey: .endedAt)
    try c.encodeIfPresent(windowStartedAt, forKey: .windowStartedAt)
    try c.encodeIfPresent(windowEndedAt, forKey: .windowEndedAt)
    try c.encodeIfPresent(pricing, forKey: .pricing)
    try c.encodeIfPresent(priceCap, forKey: .priceCap)
  }
}

/// What the scan page computes for one plan's day: ResourcePricing's
/// `pricingInZone(config, config.provider.timeZone ?? "UTC", zone, day)`, then
/// usePlansDaySegments' `pricingPreview(pricingInZone(that, zone, "UTC", day), day, zone, true)`.
enum PrismDaySegments {
  /// The day's pieces of `config` on `localDate` (YYYY-MM-DD in `displayTimeZone`).
  /// Empty for a fixed charge, and where the web shows an error instead of a ring.
  static func segments(config: PrismPricingConfig, localDate: String, displayTimeZone: String) -> [PrismDaySegment] {
    (try? segmentsOrThrow(config: config, localDate: localDate, displayTimeZone: displayTimeZone)) ?? []
  }

  static func segmentsOrThrow(config: PrismPricingConfig, localDate: String, displayTimeZone: String) throws -> [PrismDaySegment] {
    let zone = displayTimeZone.isEmpty ? TimeZone.current.identifier : displayTimeZone
    let shopClock = try pricingInZone(config, from: config.provider.timeZone ?? "UTC", to: zone, referenceDate: localDate)
    let utc = try pricingInZone(shopClock, from: zone, to: "UTC", referenceDate: localDate)
    return try pricingPreview(utc, localDate: localDate, displayTimeZone: zone, roundMoney: true) ?? []
  }

  /// `pricingInZone` (prism-web/src/ui/merchant/pricing-clock.ts).
  static func pricingInZone(_ value: PrismPricingConfig, from: String, to: String, referenceDate: String) throws -> PrismPricingConfig {
    if value.kind == "charge.fixed" { return value }
    var provider = value.provider
    provider.timeZone = to
    provider.rules = try value.provider.rules?.map { try convertPricingRuleClock($0, from: from, to: to, referenceDate: referenceDate) }
    return value.with(provider: provider)
  }

  /// `pricingPreview(value, localDate, displayTimeZone, roundMoney)` → the timeline's segments; nil for a fixed charge.
  static func pricingPreview(_ value: PrismPricingConfig, localDate: String, displayTimeZone: String, roundMoney: Bool) throws -> [PrismDaySegment]? {
    if value.kind == "charge.fixed" { return nil }
    var provider = value.provider
    provider.rules = provider.rules ?? []
    if roundMoney { provider = try PrismPricingConfigs.quantizePricingProvider(provider) }
    return try PrismPricingTime.buildTimeRuleTimeline(
      localDate: localDate, displayTimeZone: displayTimeZone, rules: provider.rules ?? [], timeZone: provider.timeZone,
      value: value.kind == "time.cap" ? .priceCap : .pricing)
  }

  /// `convertPricingRuleClock` (packages/core/src/pricing-clock.ts): a rule's clock moved between zones.
  static func convertPricingRuleClock(_ rule: PrismPricingRule, from: String, to: String, referenceDate: String) throws -> PrismPricingRule {
    guard let timeRange = rule.timeRange, from != to else { return rule }
    func parts(_ at: PrismMs) throws -> (date: String, clock: String) {
      let display = try PrismZones.displayParts(at, to)
      return (display.date, display.time)
    }
    func addDays(_ date: String, _ days: Double) throws -> String {
      String(try PrismJS.isoString(PrismJS.parseDate("\(date)T00:00:00Z") + days * PrismJS.msPerDay).prefix(10))
    }
    let anchorDate = rule.specificDates?.first ?? referenceDate
    let overnight = timeRange.start >= timeRange.end
    let start = try parts(try PrismZones.parseLocalDateTime(anchorDate, timeRange.start, from))
    let endDate = overnight ? try addDays(anchorDate, 1) : anchorDate
    let end = timeRange.start == timeRange.end ? start : try parts(try PrismZones.parseLocalDateTime(endDate, timeRange.end, from))
    for date in rule.specificDates ?? [] {
      let datedStart = try parts(try PrismZones.parseLocalDateTime(date, timeRange.start, from))
      let datedEnd = timeRange.start == timeRange.end
        ? datedStart
        : try parts(try PrismZones.parseLocalDateTime(overnight ? try addDays(date, 1) : date, timeRange.end, from))
      if datedStart.clock != start.clock || datedEnd.clock != end.clock {
        throw PrismDomainError("Dates with different UTC offsets require separate pricing rules.", "PRICING_DATES_REQUIRE_SEPARATE_UTC_RULES")
      }
    }
    let shift = (PrismJS.parseDate("\(start.date)T00:00:00Z") - PrismJS.parseDate("\(anchorDate)T00:00:00Z")) / PrismJS.msPerDay
    let dayShift = (shift + 0.5).rounded(.down) // Math.round
    var result = rule
    result.timeRange = PrismTimeRange(start: start.clock, end: end.clock)
    if let weekdays = rule.weekdays {
      result.weekdays = weekdays.map { ($0 + dayShift + 7).truncatingRemainder(dividingBy: 7) }
    }
    if let dates = rule.specificDates {
      result.specificDates = try dates.map { try parts(try PrismZones.parseLocalDateTime($0, timeRange.start, from)).date }
    }
    return result
  }
}
