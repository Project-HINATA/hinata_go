import Foundation

// Asset types (packages/core/src/assets.ts), the available-asset reader
// (application/src/available-assets.ts) and the asset-definition effect
// provider (application/src/asset-definition-effects.ts), limited to what the
// checkout preview reads.

struct PrismPricingEffect: Codable, Hashable, Sendable {
  var id: String
  var name: String
  /// `free`, `discount`, `percentage-discount` or `surcharge`.
  var type: String
  /// `session` or `unified`.
  var scope: String?
  var value: Double?
  var consumable: Bool?
  var limitPerDay: Double?
  @PrismOptionalISODate var activeAt: Date?
  @PrismOptionalISODate var expiresAt: Date?
  var status: String?
  /// Opaque, as in TypeScript.
  var config: PrismJSONValue?

  private enum CodingKeys: String, CodingKey { case id, name, type, scope, value, consumable, limitPerDay, activeAt, expiresAt, status, config }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    type = try c.decode(String.self, forKey: .type)
    scope = try c.decodeIfPresent(String.self, forKey: .scope)
    value = try c.decodeIfPresent(Double.self, forKey: .value)
    consumable = try c.decodeIfPresent(Bool.self, forKey: .consumable)
    limitPerDay = try c.decodeIfPresent(Double.self, forKey: .limitPerDay)
    _activeAt = try c.decode(PrismOptionalISODate.self, forKey: .activeAt)
    _expiresAt = try c.decode(PrismOptionalISODate.self, forKey: .expiresAt)
    status = try c.decodeIfPresent(String.self, forKey: .status)
    config = try c.decodeIfPresent(PrismJSONValue.self, forKey: .config)
  }
}

struct PrismAssetDefinition: Codable, Hashable, Sendable {
  var type: String
  var code: String
  var name: String
  var stackable: Bool?
  var status: String?
  var pricingEffectId: String?
  var pricingEffect: PrismPricingEffect?
  @PrismOptionalISODate var activeAt: Date?
  @PrismOptionalISODate var expiresAt: Date?
  /// Opaque, as in TypeScript.
  var metadata: PrismJSONValue?

  private enum CodingKeys: String, CodingKey { case type, code, name, stackable, status, pricingEffectId, pricingEffect, activeAt, expiresAt, metadata }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    type = try c.decode(String.self, forKey: .type)
    code = try c.decode(String.self, forKey: .code)
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    stackable = try? c.decodeIfPresent(Bool.self, forKey: .stackable)
    status = try c.decodeIfPresent(String.self, forKey: .status)
    pricingEffectId = try c.decodeIfPresent(String.self, forKey: .pricingEffectId)
    pricingEffect = try c.decodeIfPresent(PrismPricingEffect.self, forKey: .pricingEffect)
    _activeAt = try c.decode(PrismOptionalISODate.self, forKey: .activeAt)
    _expiresAt = try c.decode(PrismOptionalISODate.self, forKey: .expiresAt)
    metadata = try c.decodeIfPresent(PrismJSONValue.self, forKey: .metadata)
  }
}

struct PrismAssetHolding: Codable, Hashable, Sendable {
  var id: String?
  var assetType: String
  var assetCode: String
  /// Stored integer: cents for currency, a whole count otherwise.
  var quantity: Double
  @PrismOptionalISODate var activeAt: Date?
  @PrismOptionalISODate var expiresAt: Date?
}

enum PrismAssetRules {
  static func isActiveInWindow(activeAt: Date?, expiresAt: Date?, _ now: PrismMs) -> Bool {
    if let activeAt, activeAt.prismMs > now { return false }
    if let expiresAt, expiresAt.prismMs <= now { return false }
    return true
  }

  static func key(_ type: String, _ code: String) -> String { "\(type)\u{0}\(code)" }

  /// `sumCurrencyHoldings`.
  static func sumCurrencyHoldings(_ holdings: [PrismAssetHolding]) throws -> Int {
    try PrismMoney.sum(holdings.filter { $0.assetType == "currency" }.map { try PrismMoney.centsOfInteger($0.quantity) })
  }

  /// `createAvailableAssetReader(...).resolveAvailableHoldings(holdings, { at, includeHidden: true })`:
  /// the holdings that are available with their definitions, in holding order.
  static func resolveAvailableHoldings(_ holdings: [PrismAssetHolding], definitions: [PrismAssetDefinition], at: PrismMs)
    -> [(holdingIndex: Int, definition: PrismAssetDefinition)] {
    var byKey: [String: PrismAssetDefinition] = [:]
    for definition in definitions { byKey[key(definition.type, definition.code)] = definition }
    var result: [(Int, PrismAssetDefinition)] = []
    for (index, holding) in holdings.enumerated() {
      guard let definition = byKey[key(holding.assetType, holding.assetCode)] else { continue }
      if holding.quantity <= 0 { continue }
      if !isActiveInWindow(activeAt: holding.activeAt, expiresAt: holding.expiresAt, at) { continue }
      if definition.status == "archived" { continue }
      if !isActiveInWindow(activeAt: definition.activeAt, expiresAt: definition.expiresAt, at) { continue }
      result.append((index, definition))
    }
    return result
  }
}

/// `AssetSettlementEffectConfig`: the effect's opaque config with the effect's own fields over it.
struct PrismAssetEffectConfig: Sendable {
  var type: String
  var scope: String?
  var value: Double?
  var consumable: Bool?
  var limitPerDay: Double?
  var minSubtotal: Double?
  var startDate: String?
  var endDate: String?
  var daysOfWeek: [Double]?
  var applicableSessionLabels: [String]?
  var applicablePricingConfigIds: [String]?
  var applicableRuleIds: [String]?
}

enum PrismAssetEffectRules {
  /// `resolveAssetDefinitionEffectConfig`.
  static func resolve(_ definition: PrismAssetDefinition, at: PrismMs) -> PrismAssetEffectConfig? {
    guard let effect = definition.pricingEffect else { return nil }
    if effect.status == "archived" || !PrismAssetRules.isActiveInWindow(activeAt: effect.activeAt, expiresAt: effect.expiresAt, at) { return nil }
    let config = effect.config ?? .null
    func strings(_ key: String) -> [String]? {
      config[key]?.arrayValue.map { $0.compactMap(\.stringValue) }
    }
    return PrismAssetEffectConfig(
      type: effect.type, scope: effect.scope, value: effect.value, consumable: effect.consumable, limitPerDay: effect.limitPerDay,
      minSubtotal: config["minSubtotal"]?.numberValue,
      startDate: config["startDate"]?.stringValue,
      endDate: config["endDate"]?.stringValue,
      daysOfWeek: config["daysOfWeek"]?.arrayValue.map { $0.compactMap(\.numberValue) },
      applicableSessionLabels: strings("applicableSessionLabels"),
      applicablePricingConfigIds: strings("applicablePricingConfigIds"),
      applicableRuleIds: strings("applicableRuleIds"))
  }

  /// `isAssetEffectConfigAvailable`.
  static func isAvailable(_ config: PrismAssetEffectConfig, at: PrismMs, timeZone: String) throws -> Bool {
    let today = try PrismZones.formatLocalDate(at, timeZone)
    if let start = config.startDate, !start.isEmpty, today < start { return false }
    if let end = config.endDate, !end.isEmpty, today > end { return false }
    if let days = config.daysOfWeek, !days.isEmpty {
      // new Date(`${date}T00:00:00Z`).getUTCDay() || 7
      let ms = PrismJS.parseDate("\(today)T00:00:00Z")
      let weekday = ms.isFinite ? PrismJS.utcFields(ms).weekday : 0
      if !days.contains(Double(weekday == 0 ? 7 : weekday)) { return false }
    }
    return true
  }

  /// `calculateAssetEffectDiscount`.
  static func discount(_ subtotal: Int, _ config: PrismAssetEffectConfig) throws -> Int {
    switch config.type {
    case "free": return subtotal
    case "discount": return min(subtotal, try PrismMoney.centsOf(config.value ?? 0))
    case "percentage-discount":
      let basisPoints = try PrismMoney.centsOf(config.value ?? 0)
      return try PrismMoney.mulDivRound(subtotal, Double(basisPoints), 10_000, .half)
    default: return 0
    }
  }

  static func isChargeItemEligible(_ item: PrismChargeItem, _ config: PrismAssetEffectConfig) -> Bool {
    guard let history = item.pricingHistory else { return false }
    if let ids = config.applicablePricingConfigIds, !ids.isEmpty, !ids.contains(history.pricingConfigId) { return false }
    if let ids = config.applicableRuleIds, !ids.isEmpty, !ids.contains(history.ruleId) { return false }
    return true
  }

  static func source(_ assetType: String, _ assetCode: String) -> String {
    assetCode.hasPrefix("\(assetType).") ? assetCode : "\(assetType).\(assetCode)"
  }

  /// When the effect applies: at the session's start if the definition was active then, else now.
  static func effectiveAt(_ definition: PrismAssetDefinition?, sessionStartedAt: PrismMs, now: PrismMs) -> PrismMs? {
    guard let definition else { return nil }
    if PrismAssetRules.isActiveInWindow(activeAt: definition.activeAt, expiresAt: definition.expiresAt, sessionStartedAt) { return sessionStartedAt }
    if PrismAssetRules.isActiveInWindow(activeAt: definition.activeAt, expiresAt: definition.expiresAt, now) { return now }
    return nil
  }
}

/// `createAssetDefinitionEffectProvider(assetDefinitions)`: per-session offers.
struct PrismAssetDefinitionEffects: Sendable {
  var definitions: [PrismAssetDefinition]

  func apply(session: PrismSession, chargeItems: [PrismChargeItem], assetHoldings: [PrismAssetHolding], subtotal: Int,
             now: PrismMs, pastAppliedAdjustments: [PrismPastAppliedAdjustment]) throws -> [PrismSettlementAdjustment] {
    if !(subtotal > 0) { return [] }
    var adjustments: [PrismSettlementAdjustment] = []
    var remainingSubtotal = subtotal
    let timeZone = "UTC"
    var byKey: [String: PrismAssetDefinition] = [:]
    for definition in definitions { byKey[PrismAssetRules.key(definition.type, definition.code)] = definition }
    var remainingChargeAmounts: [String: Int] = [:]
    for item in chargeItems { remainingChargeAmounts[item.id] = item.amount }
    let startedAt = session.startedAt.prismMs

    for (holdingIndex, holding) in assetHoldings.enumerated() {
      if !(remainingSubtotal > 0) { break }
      if holding.quantity <= 0 { continue }
      let definition = byKey[PrismAssetRules.key(holding.assetType, holding.assetCode)]
      guard let definition, definition.status != "archived",
            let effectiveAt = PrismAssetEffectRules.effectiveAt(definition, sessionStartedAt: startedAt, now: now) else { continue }
      guard let config = PrismAssetEffectRules.resolve(definition, at: effectiveAt), config.scope != "unified" else { continue }
      if !(try PrismAssetEffectRules.isAvailable(config, at: effectiveAt, timeZone: timeZone)) { continue }
      if let labels = config.applicableSessionLabels, !labels.isEmpty {
        guard let label = session.label, !label.isEmpty, labels.contains(label) else { continue }
      }
      var eligibleSubtotal = remainingSubtotal
      let targeted = (config.applicablePricingConfigIds?.isEmpty == false || config.applicableRuleIds?.isEmpty == false)
        ? chargeItems.filter { PrismAssetEffectRules.isChargeItemEligible($0, config) }
        : nil
      if let targeted {
        let targetedRemaining = try PrismMoney.sum(targeted.map { remainingChargeAmounts[$0.id] ?? 0 })
        eligibleSubtotal = min(remainingSubtotal, targetedRemaining)
      }
      if !(eligibleSubtotal > 0) { continue }
      if let minimum = config.minSubtotal, minimum != 0, !minimum.isNaN, eligibleSubtotal < (try PrismMoney.centsOf(minimum)) { continue }
      if let limit = config.limitPerDay, limit != 0, !limit.isNaN {
        let today = try PrismZones.formatLocalDate(effectiveAt, timeZone)
        let source = PrismAssetEffectRules.source(holding.assetType, holding.assetCode)
        var usesToday = 0
        for adjustment in pastAppliedAdjustments where adjustment.source == source {
          if try PrismZones.formatLocalDate(adjustment.sessionStartedAt.prismMs, timeZone) == today { usesToday += 1 }
        }
        if Double(usesToday) >= limit { continue }
      }
      let discountAmount = try PrismAssetEffectRules.discount(eligibleSubtotal, config)
      if !(discountAmount > 0) { continue }
      if let targeted {
        var toDeduct = discountAmount
        for item in targeted {
          if !(toDeduct > 0) { break }
          let current = remainingChargeAmounts[item.id] ?? 0
          let deducted = min(current, toDeduct)
          remainingChargeAmounts[item.id] = try PrismMoney.sub(current, deducted)
          toDeduct = try PrismMoney.sub(toDeduct, deducted)
        }
      }
      let holdingKey = holding.id ?? (holdingIndex > 0 ? String(holdingIndex) : "")
      let id = holdingKey.isEmpty
        ? "\(session.id):asset-definition:\(holding.assetType):\(holding.assetCode):\(config.type)"
        : "\(session.id):asset-definition:\(holding.assetType):\(holding.assetCode):\(holdingKey):\(config.type)"
      adjustments.append(PrismSettlementAdjustment(
        id: id, source: PrismAssetEffectRules.source(holding.assetType, holding.assetCode),
        label: definition.name, amount: -discountAmount, pricingCapHistory: nil))
      remainingSubtotal = try PrismMoney.sub(remainingSubtotal, discountAmount)
    }
    return adjustments
  }
}
