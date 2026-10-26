import Foundation

// Settlement value types of packages/core/src/settlement.ts and pricing-time.ts,
// as they travel on the wire (JSON.stringify of the engine objects): money in
// integer cents, instants as ISO strings. In Swift: cents are `Int`, instants `Date`.

struct PrismPeriod: Codable, Hashable, Sendable {
  @PrismISODate var startedAt: Date
  @PrismISODate var endedAt: Date

  init(startedAt: Date, endedAt: Date) {
    self.startedAt = startedAt
    self.endedAt = endedAt
  }

  init(startedAtMs: PrismMs, endedAtMs: PrismMs) {
    self.init(startedAt: Date(prismMs: startedAtMs), endedAt: Date(prismMs: endedAtMs))
  }

  var startedAtMs: PrismMs { startedAt.prismMs }
  var endedAtMs: PrismMs { endedAt.prismMs }
}

struct PrismPricingHistoryContribution: Codable, Hashable, Sendable {
  var pricingConfigId: String
  var providerId: String
  var ruleId: String
  @PrismISODate var ruleAnchorAt: Date
  var amount: Int
}

/// `PricingSegmentExplanation`. `paidBefore` and `intervalCap` are yuan, like TypeScript.
struct PrismPricingSegmentExplanation: Codable, Hashable, Sendable {
  var timeZone: String?
  var planName: String?
  var pricing: PrismUnitPricing?
  var paidBefore: Double?
  var units: Double?
  var pricingConfigId: String
  var providerId: String
  var ruleId: String
  var ruleLabel: String
  var period: PrismPeriod
  var ruleTimeRange: PrismTimeRange?
  var intervalCap: Double
  var intervalCapReached: Bool
}

struct PrismChargeItem: Codable, Hashable, Sendable {
  var id: String
  var sessionId: String?
  var source: String
  var label: String
  /// Cents.
  var amount: Int
  var period: PrismPeriod?
  var pricingHistory: PrismPricingHistoryContribution?
  var pricingExplanation: PrismPricingSegmentExplanation?

  init(id: String, sessionId: String? = nil, source: String, label: String, amount: Int, period: PrismPeriod? = nil,
       pricingHistory: PrismPricingHistoryContribution? = nil, pricingExplanation: PrismPricingSegmentExplanation? = nil) {
    self.id = id
    self.sessionId = sessionId
    self.source = source
    self.label = label
    self.amount = amount
    self.period = period
    self.pricingHistory = pricingHistory
    self.pricingExplanation = pricingExplanation
  }

  private enum CodingKeys: String, CodingKey { case id, sessionId, source, label, amount, period, pricingHistory, pricingExplanation }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
    source = try c.decode(String.self, forKey: .source)
    label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    amount = try PrismMoney.centsOfInteger(try c.decode(Double.self, forKey: .amount))
    period = try c.decodeIfPresent(PrismPeriod.self, forKey: .period)
    pricingHistory = try c.decodeIfPresent(PrismPricingHistoryContribution.self, forKey: .pricingHistory)
    pricingExplanation = try c.decodeIfPresent(PrismPricingSegmentExplanation.self, forKey: .pricingExplanation)
  }
}

struct PrismPricingCapHistoryContribution: Codable, Hashable, Sendable {
  var capConfigId: String
  var capRuleId: String
  @PrismISODate var capAnchorAt: Date
  var includedPricingConfigIds: [String]
  var amount: Int
}

struct PrismSettlementAdjustment: Codable, Hashable, Sendable {
  var id: String
  var source: String
  var label: String
  /// Cents; negative for a discount.
  var amount: Int
  var pricingCapHistory: PrismPricingCapHistoryContribution?
}

/// `TimeCapPricingWindow`: a cross-plan cap window as settlement applied it (cents).
struct PrismTimeCapPricingWindow: Codable, Hashable, Sendable {
  struct Contribution: Codable, Hashable, Sendable {
    var sessionId: String
    var pricingConfigId: String
    var amount: Int
  }

  var key: String
  var capName: String?
  var capConfigId: String
  var capRuleId: String
  var ruleLabel: String
  @PrismISODate var windowStartedAt: Date
  @PrismISODate var windowEndedAt: Date
  var priceCap: Int
  var paidBefore: Int
  var currentAmount: Int
  var amountApplied: Int
  var heldBack: Int?
  var contributions: [Contribution]
}

struct PrismPastAppliedAdjustment: Codable, Hashable, Sendable {
  var source: String
  @PrismISODate var sessionStartedAt: Date
}

/// `PreviewSessionSettlementResult` (the per-session core preview).
struct PrismSessionSettlementPreview: Sendable {
  var subtotal: Int
  var total: Int
  var previewedAt: Date
  var chargeItems: [PrismChargeItem]
  var adjustments: [PrismSettlementAdjustment]
}

enum PrismSettlement {
  /// `previewSessionSettlement` with the browser's providers (synchronous port).
  static func previewSessionSettlement(
    session: PrismSession,
    pricingProviders: [PrismPricingProvider],
    effects: PrismAssetDefinitionEffects?,
    assetHoldings: [PrismAssetHolding],
    now: PrismMs,
    timeZone: String?,
    pastAppliedAdjustments: [PrismPastAppliedAdjustment]
  ) throws -> PrismSessionSettlementPreview {
    let available = assetHoldings.filter { isHoldingAvailableAt($0, now) }
    var chargeItems: [PrismChargeItem] = []
    for provider in pricingProviders {
      chargeItems.append(contentsOf: try PrismPricingTime.quote(provider, session: session, now: now))
    }
    for item in chargeItems where abs(item.amount) > PrismMoney.maxSafeInteger {
      throw PrismDomainError("Charge item amount must be a finite number.", "INVALID_CHARGE_AMOUNT")
    }
    let subtotal = try PrismMoney.sum(chargeItems.map(\.amount))
    var adjustments: [PrismSettlementAdjustment] = []
    if let effects {
      adjustments.append(contentsOf: try effects.apply(session: session, chargeItems: chargeItems, assetHoldings: available,
                                                       subtotal: subtotal, now: now, pastAppliedAdjustments: pastAppliedAdjustments))
    }
    var total = subtotal
    for adjustment in adjustments { total = try PrismMoney.add(total, adjustment.amount) }
    return PrismSessionSettlementPreview(subtotal: subtotal, total: max(0, total), previewedAt: Date(prismMs: now),
                                         chargeItems: chargeItems, adjustments: adjustments)
  }

  static func isHoldingAvailableAt(_ holding: PrismAssetHolding, _ now: PrismMs) -> Bool {
    if holding.quantity <= 0 { return false }
    if let activeAt = holding.activeAt, activeAt.prismMs > now { return false }
    if let expiresAt = holding.expiresAt, expiresAt.prismMs <= now { return false }
    return true
  }
}
