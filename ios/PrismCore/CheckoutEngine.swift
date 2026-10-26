import Foundation

/// `PreviewPlayerCheckoutResult` (application/src/settlement-service.ts): money in cents.
struct PrismCheckoutPreview: Sendable {
  struct SettlementPreview: Sendable {
    var playerId: String
    var sessionIds: [String]
    var subtotal: Int
    var total: Int
    var status: String = "preview"
    var previewedAt: Date
  }

  struct SessionPreview: Sendable {
    var sessionId: String
    var label: String?
    var startedAt: Date
    var endedAt: Date?
    var status: String?
    var subtotal: Int
    var total: Int
    var chargeItems: [PrismChargeItem]
    var adjustments: [PrismSettlementAdjustment]
  }

  struct Wallet: Sendable {
    var balanceBefore: Int
    var balanceAfter: Int
  }

  var settlementPreview: SettlementPreview
  var sessionPreviews: [SessionPreview]
  var chargeItems: [PrismChargeItem]
  var adjustments: [PrismSettlementAdjustment]
  var checkoutAdjustments: [PrismSettlementAdjustment]
  var pricingCapAdjustments: [PrismSettlementAdjustment]
  var wallet: Wallet
  var globalCapWindows: [PrismTimeCapPricingWindow]
}

/// The browser's live checkout preview: `createLiveBillingCalculator(snapshot).previewCheckout(playerId)`
/// (application/src/live-billing-snapshot.ts), i.e. `SettlementService.previewCheckout`
/// with read-only repositories over the snapshot and the versioned pricing resolvers.
enum PrismCheckoutEngine {
  static func preview(snapshot: PrismBillingSnapshot, playerId: String) throws -> PrismCheckoutPreview {
    var players: [String: PrismBillingSnapshot.Player] = [:]
    for player in snapshot.players { players[player.playerId] = player }
    guard let player = players[playerId] else { throw PrismDomainError("Player not found.", "PLAYER_NOT_FOUND") }
    let now = snapshot.capturedAt.prismMs
    let active = player.sessions.filter { $0.status == "active" }
    let unpaidClosed = player.sessions.filter { $0.status == "closed" && $0.paymentStatus == "unpaid" }
    let sessions = uniqueSessionsById(unpaidClosed + active)
    let details = try calculateUnifiedCheckoutDetails(snapshot: snapshot, player: player, closedSessions: sessions,
                                                      assetHoldings: player.holdings, now: now)
    return toPlayerCheckoutPreview(playerId: playerId, details: details, now: now)
  }

  private static func uniqueSessionsById(_ sessions: [PrismSession]) -> [PrismSession] {
    var byId = PrismOrderedMap<String, PrismSession>()
    for session in sessions { byId[session.id] = session }
    return byId.values
  }

  private struct SessionResult {
    var session: PrismSession
    var chargeItems: [PrismChargeItem]
    var adjustments: [PrismSettlementAdjustment]
  }

  private struct Details {
    var subtotal: Int
    var total: Int
    var sessionResults: [SessionResult]
    var unifiedAdjustments: [PrismSettlementAdjustment]
    var walletBalanceBefore: Int
    var globalCapAdjustments: [PrismSettlementAdjustment]
    var globalCapWindows: [PrismTimeCapPricingWindow]
  }

  // MARK: Versioned pricing (application/src/versioned-pricing.ts)

  private static func sessionPricing(_ snapshot: PrismBillingSnapshot, _ session: PrismSession) throws -> (configs: [PrismPricingConfig], timeZone: String) {
    var releases: [String: PrismPricingRelease] = [:]
    for release in snapshot.pricingReleases { releases[release.id] = release }
    var release: PrismPricingRelease? = nil
    if let releaseId = session.pricingReleaseId, !releaseId.isEmpty {
      release = releases[releaseId]
      if release == nil { throw PrismDomainError("Pinned pricing release not found.", "PRICING_RELEASE_NOT_FOUND") }
    }
    let configs = (release?.configs ?? snapshot.currentPricingConfigs).filter { $0.enabled && $0.status != "archived" }
    return (configs, release?.timeZone ?? "UTC")
  }

  /// `historyVersionedConfig`: a plan as its spending history is keyed.
  static func historyVersionedConfig(_ config: PrismPricingConfig) -> PrismPricingConfig {
    if config.kind == "time.priority", let historyProviderId = config.provider.historyProviderId, !historyProviderId.isEmpty {
      var provider = config.provider
      provider.id = historyProviderId
      return config.with(provider: provider)
    }
    guard let versionId = config.versionId, !versionId.isEmpty, config.version != 1 else { return config }
    var provider = config.provider
    provider.id = versionId
    return config.with(provider: provider)
  }

  private static func pricingProviders(_ snapshot: PrismBillingSnapshot, _ player: PrismBillingSnapshot.Player,
                                       _ session: PrismSession, _ now: PrismMs) throws -> [PrismPricingProvider] {
    let pinned = try sessionPricing(snapshot, session)
    let sessionConfigIds = session.pricingConfigIds ?? []
    let configs = (sessionConfigIds.isEmpty ? pinned.configs : pinned.configs.filter { sessionConfigIds.contains($0.id) })
      .filter { $0.kind != "time.cap" }
      .map(historyVersionedConfig)
    if configs.isEmpty { return [] }
    let storeTimeZone = pinned.timeZone
    // withRuntimePricingHistory: the plan's history for exactly the keys this session reads.
    var keys: [String] = []
    var resolved: [PrismPricingConfig] = []
    for config in configs {
      guard config.kind == "time.priority" else { resolved.append(config); continue }
      var provider = config.provider
      provider.timeZone = provider.timeZone ?? storeTimeZone
      provider.pricingConfigId = config.id
      resolved.append(config.with(provider: provider))
      let engine = PrismPriorityTimeProviderConfig(id: provider.id, name: provider.name, pricingConfigId: config.id,
                                                   rules: provider.rules ?? [], timeZone: provider.timeZone)
      keys.append(contentsOf: try PrismPricingTime.collectPriorityHistoryKeys(
        engine, startedAt: session.startedAt.prismMs, endedAt: session.endedAt?.prismMs ?? now))
    }
    var paidHistory: [String: Int] = [:]
    for key in keys { paidHistory[key] = player.pricingPaidHistory[key] ?? 0 }
    return try resolved.map { config in
      var provider = try PrismPricingConfigs.provider(from: config)
      if case .priority(var engine) = provider {
        engine.paidHistory = paidHistory
        provider = .priority(engine)
      }
      return provider
    }
  }

  private static func globalCapConfigs(_ snapshot: PrismBillingSnapshot, _ sessions: [PrismSession], timeZone: String) throws -> [PrismTimeCapProviderConfig] {
    var releases = PrismOrderedMap<String, PrismSession>()
    for session in sessions { releases[session.pricingReleaseId ?? "legacy"] = session }
    if releases.count > 1 {
      throw PrismDomainError("Unsettled sessions use different pricing releases.", "PRICING_RELEASE_MISMATCH")
    }
    var result: [PrismTimeCapProviderConfig] = []
    for session in releases.values {
      let pinned = try sessionPricing(snapshot, session)
      let timePlanIds = pinned.configs.filter { $0.kind == "time.priority" }.map(\.id)
      for config in pinned.configs where config.kind == "time.cap" {
        result.append(PrismTimeCapProviderConfig(
          id: config.provider.id, name: config.name,
          pricingConfigId: config.version == 1 ? config.id : (config.versionId ?? config.id),
          includedPricingConfigIds: timePlanIds, rules: config.provider.rules ?? [],
          timeZone: config.provider.timeZone ?? pinned.timeZone, paidHistory: nil))
      }
    }
    return result
  }

  // MARK: calculateUnifiedCheckoutDetails

  private static let adjustmentPattern = try! NSRegularExpression(pattern: ":asset-definition:([^:]+):([^:]+)(?::([^:]+))?:")

  private static func calculateUnifiedCheckoutDetails(snapshot: PrismBillingSnapshot, player: PrismBillingSnapshot.Player,
                                                      closedSessions: [PrismSession], assetHoldings: [PrismAssetHolding],
                                                      now: PrismMs) throws -> Details {
    if closedSessions.isEmpty {
      throw PrismDomainError("Player has no sessions to settle.", "PLAYER_HAS_NO_UNSETTLED_SESSIONS")
    }
    let timeZone = "UTC"
    let effects = PrismAssetDefinitionEffects(definitions: snapshot.assetDefinitions)
    let orderedSessions = uniqueSessionsById(closedSessions).prismSorted { $0.startedAt.prismMs - $1.startedAt.prismMs }
    let anchorSession = orderedSessions.prismSorted { $1.startedAt.prismMs - $0.startedAt.prismMs }[0]
    let currentHoldings = assetHoldings
    let resolved = PrismAssetRules.resolveAvailableHoldings(currentHoldings, definitions: snapshot.assetDefinitions, at: now)
    var availableDefinitions: [String: PrismAssetDefinition] = [:]
    for entry in resolved { availableDefinitions[PrismAssetRules.key(entry.definition.type, entry.definition.code)] = entry.definition }
    var availableHoldings = resolved.map { currentHoldings[$0.holdingIndex] }
    let walletBalanceBefore = try PrismAssetRules.sumCurrencyHoldings(availableHoldings)
    var totalAmount = 0
    var overallSubtotal = 0
    var accumulatedAdjustments = player.pastAppliedAdjustments
    var sessionResults: [SessionResult] = []

    for var session in orderedSessions {
      if session.metadata?["deviceOperated"]?.isTruthy ?? false {
        var object: [String: PrismJSONValue] = [:]
        if case .object(let existing)? = session.metadata { object = existing }
        object["deviceOperated"] = .bool(true)
        session.metadata = .object(object)
      }
      let providers = try pricingProviders(snapshot, player, session, now)
      let preview = try PrismSettlement.previewSessionSettlement(
        session: session, pricingProviders: providers, effects: effects, assetHoldings: availableHoldings,
        now: now, timeZone: timeZone, pastAppliedAdjustments: accumulatedAdjustments)
      let sessionRawSubtotal = try PrismMoney.sum(preview.chargeItems.map(\.amount))
      let sessionRawTotal = try PrismMoney.add(sessionRawSubtotal, try PrismMoney.sum(preview.adjustments.map(\.amount)))
      overallSubtotal = try PrismMoney.add(overallSubtotal, sessionRawSubtotal)
      totalAmount = try PrismMoney.add(totalAmount, sessionRawTotal)

      // Consumable offers used by this session leave the holdings the next session sees.
      for adjustment in preview.adjustments {
        let id = adjustment.id as NSString
        guard let match = adjustmentPattern.firstMatch(in: adjustment.id, range: NSRange(location: 0, length: id.length)) else { continue }
        let assetType = id.substring(with: match.range(at: 1))
        let assetCode = id.substring(with: match.range(at: 2))
        let holdingKey = match.range(at: 3).location == NSNotFound ? nil : id.substring(with: match.range(at: 3))
        guard let definition = availableDefinitions[PrismAssetRules.key(assetType, assetCode)] else { continue }
        guard definition.status != "archived",
              let effectiveAt = PrismAssetEffectRules.effectiveAt(definition, sessionStartedAt: session.startedAt.prismMs, now: now) else { continue }
        guard PrismAssetEffectRules.resolve(definition, at: effectiveAt)?.consumable == true else { continue }
        let index = availableHoldings.firstIndex { holding in
          (holdingKey.map { !$0.isEmpty } ?? false
            ? holding.id == holdingKey
            : holding.assetType == assetType && holding.assetCode == assetCode) && holding.quantity > 0
        } ?? availableHoldings.firstIndex { $0.assetType == assetType && $0.assetCode == assetCode && $0.quantity > 0 }
        if let index {
          let holding = availableHoldings[index]
          let consumed = try PrismMoney.assetQuantityOf(holding.assetType, 1)
          availableHoldings[index].quantity = try PrismMoney.assetQuantityFromStored(holding.assetType, holding.quantity - consumed)
        }
      }
      for adjustment in preview.adjustments {
        accumulatedAdjustments.append(PrismPastAppliedAdjustment(source: adjustment.source, sessionStartedAt: session.startedAt))
      }
      sessionResults.append(SessionResult(session: session, chargeItems: preview.chargeItems, adjustments: preview.adjustments))
    }

    var unifiedAdjustments: [PrismSettlementAdjustment] = []
    var globalCapAdjustments: [PrismSettlementAdjustment] = []
    let chargeItemsForGlobalCaps = sessionResults.flatMap { result in
      result.chargeItems.map { item -> PrismChargeItem in
        if let sessionId = item.sessionId, !sessionId.isEmpty { return item }
        var copy = item
        copy.sessionId = result.session.id
        return copy
      }
    }
    let capConfigs = try globalCapConfigs(snapshot, orderedSessions, timeZone: timeZone)
    // Every cap across plans limits the same charges together, so a charge is held back once.
    // The history read is exactly the windows the settlement visits (collectTimeCapPricingHistoryLookupKeys).
    let capSettlement = try PrismPricingTime.settleTimeCaps(configs: capConfigs, chargeItems: chargeItemsForGlobalCaps,
                                                            paidHistory: player.capPaidHistory)
    for adjustment in capSettlement.adjustments {
      globalCapAdjustments.append(adjustment)
      unifiedAdjustments.append(adjustment)
      totalAmount = try PrismMoney.add(totalAmount, adjustment.amount)
    }

    // Offers over the whole bill.
    let unifiedHoldings = availableHoldings.filter { $0.quantity > 0 }
    for (holdingIndex, holding) in unifiedHoldings.enumerated() {
      if holding.quantity <= 0 || !(totalAmount > 0) { break }
      let definition = availableDefinitions[PrismAssetRules.key(holding.assetType, holding.assetCode)]
      guard let definition, definition.status != "archived",
            let effectiveAt = PrismAssetEffectRules.effectiveAt(definition, sessionStartedAt: anchorSession.startedAt.prismMs, now: now) else { continue }
      guard let config = PrismAssetEffectRules.resolve(definition, at: effectiveAt), config.scope == "unified" else { continue }
      if !(try PrismAssetEffectRules.isAvailable(config, at: effectiveAt, timeZone: timeZone)) { continue }
      if let minimum = config.minSubtotal, minimum != 0, !minimum.isNaN, totalAmount < (try PrismMoney.centsOf(minimum)) { continue }
      if let limit = config.limitPerDay, limit != 0, !limit.isNaN {
        let today = try PrismZones.formatLocalDate(effectiveAt, timeZone)
        let source = PrismAssetEffectRules.source(holding.assetType, holding.assetCode)
        var usesToday = 0
        for adjustment in accumulatedAdjustments where adjustment.source == source {
          if try PrismZones.formatLocalDate(adjustment.sessionStartedAt.prismMs, timeZone) == today { usesToday += 1 }
        }
        if Double(usesToday) >= limit { continue }
      }
      let discountAmount = try PrismAssetEffectRules.discount(totalAmount, config)
      if !(discountAmount > 0) { continue }
      let source = PrismAssetEffectRules.source(holding.assetType, holding.assetCode)
      let holdingKey = holding.id ?? (holdingIndex > 0 ? String(holdingIndex) : "")
      let id = holdingKey.isEmpty
        ? "\(anchorSession.id):asset-definition:\(holding.assetType):\(holding.assetCode):\(config.type)"
        : "\(anchorSession.id):asset-definition:\(holding.assetType):\(holding.assetCode):\(holdingKey):\(config.type)"
      unifiedAdjustments.append(PrismSettlementAdjustment(id: id, source: source, label: definition.name, amount: -discountAmount, pricingCapHistory: nil))
      totalAmount = try PrismMoney.sub(totalAmount, discountAmount)
      accumulatedAdjustments.append(PrismPastAppliedAdjustment(source: source, sessionStartedAt: anchorSession.startedAt))
    }

    return Details(subtotal: max(0, overallSubtotal), total: max(0, totalAmount), sessionResults: sessionResults,
                   unifiedAdjustments: unifiedAdjustments, walletBalanceBefore: walletBalanceBefore,
                   globalCapAdjustments: globalCapAdjustments, globalCapWindows: capSettlement.windows)
  }

  private static func toPlayerCheckoutPreview(playerId: String, details: Details, now: PrismMs) -> PrismCheckoutPreview {
    let sessionPreviews = details.sessionResults.map { result -> PrismCheckoutPreview.SessionPreview in
      let subtotal = result.chargeItems.reduce(0) { $0 + $1.amount }
      let total = subtotal + result.adjustments.reduce(0) { $0 + $1.amount }
      return PrismCheckoutPreview.SessionPreview(
        sessionId: result.session.id, label: result.session.label, startedAt: result.session.startedAt,
        endedAt: result.session.endedAt, status: result.session.status, subtotal: subtotal, total: total,
        chargeItems: result.chargeItems, adjustments: result.adjustments)
    }
    return PrismCheckoutPreview(
      settlementPreview: .init(playerId: playerId, sessionIds: details.sessionResults.map(\.session.id), subtotal: details.subtotal,
                               total: details.total, previewedAt: Date(prismMs: now)),
      sessionPreviews: sessionPreviews,
      chargeItems: details.sessionResults.flatMap(\.chargeItems),
      adjustments: details.sessionResults.flatMap(\.adjustments) + details.unifiedAdjustments,
      checkoutAdjustments: details.unifiedAdjustments.filter { $0.pricingCapHistory == nil },
      pricingCapAdjustments: details.globalCapAdjustments,
      wallet: .init(balanceBefore: details.walletBalanceBefore, balanceAfter: details.walletBalanceBefore - details.total),
      globalCapWindows: details.globalCapWindows)
  }
}
