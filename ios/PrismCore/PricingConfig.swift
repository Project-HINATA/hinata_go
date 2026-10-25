import Foundation

// Pricing configuration types (packages/core/src/pricing-config.ts and the rule
// types of pricing-time.ts).
//
// Wire formats: the snapshot's `currentPricingConfigs` / `pricingReleases[].configs`
// (engine `PricingConfig` after JSON.stringify) and the scan page's
// `toPricingConfigManagementView` output have the same JSON shape — money in
// YUAN in both (`unitPrice`, `priceCap`, fixed `amount`; only paid histories are
// cents), instants as ISO strings (`anchorAt`, `dateTimeRange.start/end`,
// `createdAt`, `updatedAt`). The management view additionally always carries
// `status` and (for time plans) `relations`; the engine form may omit `status`
// and carries `versionId`/`version`. `PrismPricingConfig` decodes both.

struct PrismUnitPricing: Codable, Hashable, Sendable {
  var unitMinutes: Double
  var unitPrice: Double
  var roundGraceMinutes: Double
  /// Yuan; 0 (or absent, decoded as NaN) leaves the period uncapped.
  var priceCap: Double

  init(unitMinutes: Double, unitPrice: Double, roundGraceMinutes: Double, priceCap: Double) {
    self.unitMinutes = unitMinutes
    self.unitPrice = unitPrice
    self.roundGraceMinutes = roundGraceMinutes
    self.priceCap = priceCap
  }

  private enum CodingKeys: String, CodingKey { case unitMinutes, unitPrice, roundGraceMinutes, priceCap }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func number(_ key: CodingKeys) -> Double { ((try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil) ?? .nan }
    unitMinutes = number(.unitMinutes)
    unitPrice = number(.unitPrice)
    roundGraceMinutes = number(.roundGraceMinutes)
    priceCap = number(.priceCap)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    for (key, value) in [(CodingKeys.unitMinutes, unitMinutes), (.unitPrice, unitPrice), (.roundGraceMinutes, roundGraceMinutes), (.priceCap, priceCap)] where !value.isNaN {
      try c.encode(value, forKey: key)
    }
  }
}

struct PrismTimeRange: Codable, Hashable, Sendable {
  var start: String
  var end: String
}

struct PrismDateTimeRange: Codable, Hashable, Sendable {
  @PrismISODate var start: Date
  @PrismISODate var end: Date
}

/// A time rule of a `time.priority` plan (`pricing`) or a `time.cap` plan (`priceCap`).
struct PrismPricingRule: Codable, Hashable, Sendable {
  var id: String
  var label: String
  var priority: Double
  var status: String?
  var weekdays: [Double]?
  var specificDates: [String]?
  /// Absolute UTC anchor retained by the historical data migration.
  @PrismOptionalISODate var anchorAt: Date?
  var historyRuleId: String?
  var timeRange: PrismTimeRange?
  var dateTimeRange: PrismDateTimeRange?
  var pricing: PrismUnitPricing?
  /// `time.cap` rules: the cap across plans, yuan.
  var priceCap: Double?

  init(id: String, label: String, priority: Double, status: String? = nil, weekdays: [Double]? = nil,
       specificDates: [String]? = nil, anchorAt: Date? = nil, historyRuleId: String? = nil,
       timeRange: PrismTimeRange? = nil, dateTimeRange: PrismDateTimeRange? = nil,
       pricing: PrismUnitPricing? = nil, priceCap: Double? = nil) {
    self.id = id
    self.label = label
    self.priority = priority
    self.status = status
    self.weekdays = weekdays
    self.specificDates = specificDates
    self.anchorAt = anchorAt
    self.historyRuleId = historyRuleId
    self.timeRange = timeRange
    self.dateTimeRange = dateTimeRange
    self.pricing = pricing
    self.priceCap = priceCap
  }

  private enum CodingKeys: String, CodingKey {
    case id, label, priority, status, weekdays, specificDates, anchorAt, historyRuleId, timeRange, dateTimeRange, pricing, priceCap
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    priority = try c.decodeIfPresent(Double.self, forKey: .priority) ?? .nan
    status = try c.decodeIfPresent(String.self, forKey: .status)
    weekdays = try c.decodeIfPresent([Double].self, forKey: .weekdays)
    specificDates = try c.decodeIfPresent([String].self, forKey: .specificDates)
    _anchorAt = try c.decode(PrismOptionalISODate.self, forKey: .anchorAt)
    historyRuleId = try c.decodeIfPresent(String.self, forKey: .historyRuleId)
    timeRange = try c.decodeIfPresent(PrismTimeRange.self, forKey: .timeRange)
    dateTimeRange = try c.decodeIfPresent(PrismDateTimeRange.self, forKey: .dateTimeRange)
    pricing = try c.decodeIfPresent(PrismUnitPricing.self, forKey: .pricing)
    priceCap = try c.decodeIfPresent(Double.self, forKey: .priceCap)
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(label, forKey: .label)
    if !priority.isNaN { try c.encode(priority, forKey: .priority) }
    try c.encodeIfPresent(status, forKey: .status)
    try c.encodeIfPresent(weekdays, forKey: .weekdays)
    try c.encodeIfPresent(specificDates, forKey: .specificDates)
    try c.encode(_anchorAt, forKey: .anchorAt)
    try c.encodeIfPresent(historyRuleId, forKey: .historyRuleId)
    try c.encodeIfPresent(timeRange, forKey: .timeRange)
    try c.encodeIfPresent(dateTimeRange, forKey: .dateTimeRange)
    try c.encodeIfPresent(pricing, forKey: .pricing)
    try c.encodeIfPresent(priceCap, forKey: .priceCap)
  }
}

/// The union of the three provider shapes (time plan, cap across plans, fixed charge).
struct PrismPricingProviderConfig: Codable, Hashable, Sendable {
  var id: String
  /// Fixed charge: the charge's label and amount (yuan).
  var label: String?
  var amount: Double?
  var name: String?
  var timeZone: String?
  var rules: [PrismPricingRule]?
  /// Present on `time.cap` providers.
  var includedPricingConfigIds: [String]?
  /// Historical aliases retain the original cap/history identity.
  var historyProviderId: String?
  var pricingConfigId: String?
}

struct PrismPricingConfig: Codable, Hashable, Sendable {
  struct Relations: Codable, Hashable, Sendable {
    var requires: [String]
    var conflicts: [String]
  }

  let id: String
  /// `time.priority`, `time.cap` or `charge.fixed`.
  let kind: String
  let name: String
  let enabled: Bool
  let status: String?
  var provider: PrismPricingProviderConfig
  let versionId: String?
  let version: Double?
  let relations: Relations?
  let createdAt: String?
  let updatedAt: String?

  init(id: String, kind: String, name: String, enabled: Bool, status: String? = nil, provider: PrismPricingProviderConfig,
       versionId: String? = nil, version: Double? = nil, relations: Relations? = nil, createdAt: String? = nil, updatedAt: String? = nil) {
    self.id = id
    self.kind = kind
    self.name = name
    self.enabled = enabled
    self.status = status
    self.provider = provider
    self.versionId = versionId
    self.version = version
    self.relations = relations
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey { case id, kind, name, enabled, status, provider, versionId, version, relations, createdAt, updatedAt }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    kind = try c.decode(String.self, forKey: .kind)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    enabled = (try? c.decodeIfPresent(PrismJSONValue.self, forKey: .enabled))??.isTruthy ?? false
    status = try c.decodeIfPresent(String.self, forKey: .status)
    provider = try c.decode(PrismPricingProviderConfig.self, forKey: .provider)
    versionId = try c.decodeIfPresent(String.self, forKey: .versionId)
    version = try c.decodeIfPresent(Double.self, forKey: .version)
    relations = try? c.decodeIfPresent(Relations.self, forKey: .relations)
    createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
    updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
  }

  func with(provider: PrismPricingProviderConfig) -> PrismPricingConfig {
    var copy = self
    copy.provider = provider
    return copy
  }
}

struct PrismPricingRelease: Codable, Hashable, Sendable {
  var id: String
  var timeZone: String
  var configs: [PrismPricingConfig]
}

// MARK: Engine provider configs

struct PrismPriorityTimeProviderConfig: Sendable {
  var id: String
  var name: String?
  var pricingConfigId: String?
  var rules: [PrismPricingRule]
  var timeZone: String?
  var paidHistory: [String: Int] = [:]
}

struct PrismTimeCapProviderConfig: Sendable {
  var id: String
  var name: String?
  var pricingConfigId: String?
  var includedPricingConfigIds: [String]
  var rules: [PrismPricingRule]
  var timeZone: String?
  var paidHistory: [String: Int]?
}

enum PrismPricingProvider: Sendable {
  case priority(PrismPriorityTimeProviderConfig)
  case fixed(id: String, label: String?, amount: Double?)
}

enum PrismPricingConfigs {
  /// `quantizePricingProvider`: snaps every monetary field to whole cents (yuan values).
  static func quantizePricingProvider(_ provider: PrismPricingProviderConfig) throws -> PrismPricingProviderConfig {
    var result = provider
    if let amount = provider.amount {
      try assertNonNegativePrice(amount)
      result.amount = try PrismMoney.quantizeMoney(amount)
      return result
    }
    if provider.includedPricingConfigIds != nil {
      for rule in provider.rules ?? [] { try assertNonNegativePrice(rule.priceCap ?? .nan) }
      result.rules = try provider.rules.map { rules in
        try rules.map { rule in
          var copy = rule
          copy.priceCap = try PrismMoney.quantizeMoney(rule.priceCap ?? .nan)
          return copy
        }
      }
      return result
    }
    for rule in provider.rules ?? [] {
      guard let pricing = rule.pricing else { throw PrismDomainError.typeError("Cannot read properties of undefined (reading 'unitPrice')") }
      // A negative unit price is a legitimate stacking discount; the cap must still be a real bound.
      try assertFinitePrice(pricing.unitPrice)
      try assertNonNegativePrice(pricing.priceCap)
    }
    result.rules = try provider.rules.map { rules in
      try rules.map { rule in
        var copy = rule
        copy.pricing!.unitPrice = try PrismMoney.quantizeMoney(rule.pricing!.unitPrice)
        copy.pricing!.priceCap = try PrismMoney.quantizeMoney(rule.pricing!.priceCap)
        return copy
      }
    }
    return result
  }

  private static func assertNonNegativePrice(_ value: Double) throws {
    if !value.isFinite || value < 0 {
      throw PrismDomainError("Price must be a non-negative finite number.", "INVALID_PRICING_AMOUNT")
    }
  }

  private static func assertFinitePrice(_ value: Double) throws {
    if !value.isFinite { throw PrismDomainError("Price must be a finite number.", "INVALID_PRICING_AMOUNT") }
  }

  /// `createPricingProviderFromConfig`.
  static func provider(from config: PrismPricingConfig) throws -> PrismPricingProvider {
    switch config.kind {
    case "time.priority":
      return .priority(PrismPriorityTimeProviderConfig(
        id: config.provider.id, name: config.name, pricingConfigId: config.id,
        rules: config.provider.rules ?? [], timeZone: config.provider.timeZone, paidHistory: [:]))
    case "time.cap":
      throw PrismDomainError("Global cap pricing configs do not create charge providers.", "TIME_CAP_CONFIG_IS_NOT_PRICING_PROVIDER")
    case "charge.fixed":
      return .fixed(id: config.provider.id, label: config.provider.label, amount: config.provider.amount)
    default:
      throw PrismDomainError.typeError("Unknown pricing config kind \(config.kind).")
    }
  }
}
