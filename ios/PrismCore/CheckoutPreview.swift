import Foundation

/// `checkoutPreviewView(result)` (prism-web/src/checkout-preview.ts) after
/// JSON.stringify: yuan amounts, ISO `previewedAt`, and the bill timeline.
struct PrismCheckoutPreviewView: Codable, Hashable, Sendable {
  struct SettlementPreview: Codable, Hashable, Sendable {
    var playerId: String
    var sessionIds: [String]
    var subtotal: Double
    var total: Double
    var status: String
    var previewedAt: String
  }

  /// A charge item or adjustment line.
  struct Line: Codable, Hashable, Sendable {
    var id: String
    var label: String
    var amount: Double
  }

  struct Wallet: Codable, Hashable, Sendable {
    var balanceBefore: Double
    var balanceAfter: Double
  }

  var timeline: PrismBillTimeline
  var settlementPreview: SettlementPreview
  var chargeItems: [Line]
  var adjustments: [Line]
  var wallet: Wallet
}

extension PrismCheckoutPreview {
  /// The bill timeline inputs of this preview (what the server returns as `PrismBillInputs`).
  var billInputs: PrismBillInputs {
    PrismBillInputs(
      at: settlementPreview.previewedAt,
      sessions: sessionPreviews.map { session in
        PrismBillInputs.Session(sessionId: session.sessionId, label: session.label, startedAt: session.startedAt,
                                endedAt: session.endedAt, chargeItems: session.chargeItems)
      },
      adjustments: adjustments,
      globalCapWindows: globalCapWindows)
  }

  func view() -> PrismCheckoutPreviewView {
    (try? viewOrThrow()) ?? PrismCheckoutPreviewView(
      timeline: .empty,
      settlementPreview: .init(playerId: settlementPreview.playerId, sessionIds: settlementPreview.sessionIds,
                               subtotal: PrismMoney.yuanOf(settlementPreview.subtotal), total: PrismMoney.yuanOf(settlementPreview.total),
                               status: settlementPreview.status, previewedAt: ""),
      chargeItems: chargeItems.map { .init(id: $0.id, label: $0.label, amount: PrismMoney.yuanOf($0.amount)) },
      adjustments: adjustments.map { .init(id: $0.id, label: $0.label, amount: PrismMoney.yuanOf($0.amount)) },
      wallet: .init(balanceBefore: PrismMoney.yuanOf(wallet.balanceBefore), balanceAfter: PrismMoney.yuanOf(wallet.balanceAfter)))
  }

  /// As `view()`, but surfaces the error TypeScript would throw (e.g. an invalid instant).
  func viewOrThrow() throws -> PrismCheckoutPreviewView {
    let inputs = billInputs
    let timeline = try prismBuildBillTimeline(at: inputs.at, timeZone: nil, planNames: nil, sessions: inputs.sessions,
                                              adjustments: inputs.adjustments, globalCapWindows: inputs.globalCapWindows)
    return PrismCheckoutPreviewView(
      timeline: timeline,
      settlementPreview: .init(playerId: settlementPreview.playerId, sessionIds: settlementPreview.sessionIds,
                               subtotal: PrismMoney.yuanOf(settlementPreview.subtotal), total: PrismMoney.yuanOf(settlementPreview.total),
                               status: settlementPreview.status, previewedAt: try PrismJS.isoString(settlementPreview.previewedAt.prismMs)),
      chargeItems: chargeItems.map { .init(id: $0.id, label: $0.label, amount: PrismMoney.yuanOf($0.amount)) },
      adjustments: adjustments.map { .init(id: $0.id, label: $0.label, amount: PrismMoney.yuanOf($0.amount)) },
      wallet: .init(balanceBefore: PrismMoney.yuanOf(wallet.balanceBefore), balanceAfter: PrismMoney.yuanOf(wallet.balanceAfter)))
  }
}
