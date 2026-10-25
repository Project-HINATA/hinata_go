import Foundation

/// `Session` (packages/core/src/session.ts) as the snapshot carries it.
struct PrismSession: Codable, Hashable, Sendable {
  var id: String
  var playerId: String
  @PrismISODate var startedAt: Date
  @PrismOptionalISODate var endedAt: Date?
  /// `active` or `closed`.
  var status: String?
  var pricingConfigIds: [String]?
  var pricingConfigId: String?
  var pricingReleaseId: String?
  /// `unpaid` or `paid`.
  var paymentStatus: String?
  var label: String?
  /// Opaque; billing reads only the truthiness of `deviceOperated` / `hasDeviceActivity`.
  var metadata: PrismJSONValue?

  /// `Boolean(metadata?.deviceOperated || metadata?.hasDeviceActivity)`.
  var hasDeviceActivity: Bool {
    (metadata?["deviceOperated"]?.isTruthy ?? false) || (metadata?["hasDeviceActivity"]?.isTruthy ?? false)
  }
}

/// The `billingSnapshot` of `GET /api/v1/shops/:shop/player/billing-inputs`
/// (`LiveBillingSnapshot` after JSON.stringify): money in integer cents (paid
/// histories, holdings), pricing configs in yuan, instants as ISO strings.
/// `metadata` and effect `config` objects stay opaque; unknown keys are ignored.
struct PrismBillingSnapshot: Decodable, Sendable {
  struct Player: Decodable, Sendable {
    var playerId: String
    var sessions: [PrismSession]
    var holdings: [PrismAssetHolding]
    var pastAppliedAdjustments: [PrismPastAppliedAdjustment]
    /// `${pricingConfigId}@${providerId}@${ruleId}@${ruleAnchorAt ISO}` → cents.
    var pricingPaidHistory: [String: Int]
    /// `${capConfigId}@${capRuleId}@${capAnchorAt ISO}` → cents.
    var capPaidHistory: [String: Int]

    private enum CodingKeys: String, CodingKey { case playerId, sessions, holdings, pastAppliedAdjustments, pricingPaidHistory, capPaidHistory }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      playerId = try c.decode(String.self, forKey: .playerId)
      sessions = try c.decodeIfPresent([PrismSession].self, forKey: .sessions) ?? []
      holdings = try c.decodeIfPresent([PrismAssetHolding].self, forKey: .holdings) ?? []
      pastAppliedAdjustments = try c.decodeIfPresent([PrismPastAppliedAdjustment].self, forKey: .pastAppliedAdjustments) ?? []
      pricingPaidHistory = try Self.cents(c.decodeIfPresent([String: Double].self, forKey: .pricingPaidHistory) ?? [:])
      capPaidHistory = try Self.cents(c.decodeIfPresent([String: Double].self, forKey: .capPaidHistory) ?? [:])
    }

    private static func cents(_ values: [String: Double]) throws -> [String: Int] {
      try values.mapValues { try PrismMoney.centsOfInteger($0) }
    }
  }

  var version: Int
  @PrismISODate var capturedAt: Date
  var assetDefinitions: [PrismAssetDefinition]
  var currentPricingConfigs: [PrismPricingConfig]
  var pricingReleases: [PrismPricingRelease]
  var players: [Player]

  private enum CodingKeys: String, CodingKey { case version, capturedAt, assetDefinitions, currentPricingConfigs, pricingReleases, players }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = (try? c.decode(Int.self, forKey: .version)) ?? 0
    guard version == 1 else {
      throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "Unsupported live billing snapshot")
    }
    _capturedAt = try c.decode(PrismISODate.self, forKey: .capturedAt)
    assetDefinitions = try c.decodeIfPresent([PrismAssetDefinition].self, forKey: .assetDefinitions) ?? []
    currentPricingConfigs = try c.decodeIfPresent([PrismPricingConfig].self, forKey: .currentPricingConfigs) ?? []
    pricingReleases = try c.decodeIfPresent([PrismPricingRelease].self, forKey: .pricingReleases) ?? []
    players = try c.decodeIfPresent([Player].self, forKey: .players) ?? []
  }
}
