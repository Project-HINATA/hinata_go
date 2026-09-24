import Foundation

func prismParsedDate(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

struct PublicMachine: Decodable {
  let publicId: String
  let name: String
  let shop: Shop
  let webOnly: Bool?
  let capabilities: [String: Bool]?
  let coinAfterSwipe: Bool?
  func has(_ capability: String) -> Bool { capabilities == nil ? capability == "card" : capabilities?[capability] == true }
  var empty: Bool { capabilities != nil && !capabilities!.values.contains(true) }
}

struct Shop: Decodable {
  let name: String
  let heroUrl: String?
  var locationEnabled: Bool? = nil
  let machineGeo: Bool?
  let billingEnabled: Bool?
  let webUrl: String?
  let latitude: Double
  let longitude: Double
  let radiusMeters: Double
}

struct PrismUser: Decodable {
  let id: String
  let username: String
  let displayName: String
}

struct ArcadeCard: Decodable, Identifiable {
  let id: String
  let label: String
  let accessCode: String
  let disabledAt: String?
}

struct MachineSessionResponse: Decodable {
  let ticket: String
  let expiresIn: Int
  let machine: PublicMachine
}

struct MeResponse: Decodable {
  let user: PrismUser?
}

struct CardsResponse: Decodable {
  let cards: [ArcadeCard]
}

struct PasskeyRequestOptions: Decodable {
  let challenge: String
  let rpId: String
}

struct PasskeyAssertion: Encodable {
  let id: String
  let rawId: String
  let response: PasskeyAssertionResponse
  let type: String
}

struct PasskeyAssertionResponse: Encodable {
  let clientDataJSON: String
  let authenticatorData: String
  let signature: String
  let userHandle: String?
}

struct MachineLoginRequest: Encodable {
  let cardId: String
  let lat: Double?
  let lng: Double?
  let accuracy: Double?
  let ticket: String
}

struct EmptyResponse: Decodable {
  let ok: Bool
}

struct SwipeResult: Codable {
  let ok: Bool?
  let coin: Coin?
  struct Coin: Codable { let status: String; let operationId: String? }
  var message: String {
    switch coin?.status {
    case "sent": return String(localized: "已刷卡并投一币")
    case "skipped": return String(localized: "刷卡已完成，投币冷却中，本次未投币。")
    case "failed": return String(localized: "刷卡已完成，投币请求失败，请联系店员。")
    case "unknown": return String(localized: "刷卡已完成，投币结果待确认，请检查机台，不要重复刷卡。")
    default: return String(localized: "本次登录已完成")
    }
  }
}
struct PrismDeviceState: Decodable { let gate: String; let power: String; var coinUsed: Bool? = nil; var mahjong: PrismMahjong? = nil }
struct PrismBinding: Decodable { let code: String; let expiresAt: String }
struct PrismDoorPassword: Decodable { let temporaryPassword: String; let expiresAt: String }
struct PrismShopResponse: Decodable {
  let shop: Settings
  let membership: Membership?
  let entryPricing: [Pricing]
  var pricingSchedule: PrismPricingSchedule? = nil
  struct Membership: Decodable { let playerId: String }
  struct Settings: Decodable {
    let name: String?
    var locationEnabled: Bool? = nil
    let billingEnabled: Bool; let checkinGeo: Bool; let checkoutGeo: Bool
    let autoRegister: Bool; let botContact: String; let timeZone: String
    /// Public cover art path, served from the shop page so a shop link can show the same
    /// card as a device link.
    var heroUrl: String? = nil
  }
  struct Pricing: Decodable, Identifiable {
    let id: String; let name: String; let kind: String; let provider: Provider
    struct Provider: Decodable { let timeZone: String?; let amount: Double?; let rules: [Rule]? }
    struct Rule: Decodable, Identifiable {
      let id: String; let label: String; let status: String?
      let timeRange: Range?; let dateTimeRange: Range?; let displayDateTimeRange: Range?; let pricing: Rate?
      let priceCap: Double?; let weekdays: [Int]?; let specificDates: [String]?
      struct Range: Decodable { let start: String; let end: String }
      struct Rate: Decodable { let unitMinutes: Double; let unitPrice: Double; let roundGraceMinutes: Double; let priceCap: Double }
      var detail: String {
        var values = [label]
        if let timeRange { values.append(timeRange.start == timeRange.end ? String(localized: "全天") : "\(timeRange.start)–\(timeRange.end)") }
        if let pricing {
          values.append("\(pricing.unitPrice.formatted()) / \(pricing.unitMinutes.formatted()) " + String(localized: "分钟"))
          if pricing.roundGraceMinutes > 0 { values.append(String(localized: "宽限") + " \(pricing.roundGraceMinutes.formatted()) " + String(localized: "分钟")) }
        }
        if let cap = pricing?.priceCap ?? priceCap, cap > 0 { values.append(String(localized: "封顶") + " \(cap.formatted())") }
        if let dateTimeRange { values.append("\(dateTimeRange.start)–\(dateTimeRange.end)") }
        if let weekdays { values.append(weekdays.filter { (0...6).contains($0) }.map { DateFormatter().shortWeekdaySymbols[$0] }.joined(separator: "、")) }
        if let specificDates { values.append(specificDates.joined(separator: ", ")) }
        return values.joined(separator: " · ")
      }
    }
  }
}
struct PrismSummary: Decodable {
  let activeSession: Session?
  let wallet: [Wallet]
  struct Session: Decodable { let id: String; let startedAt: String }
  struct Wallet: Decodable { let assetCode: String; let quantity: Double }
}
struct PrismAssets: Decodable {
  let holdings: [Holding]
  struct Holding: Decodable, Identifiable { let id: String; let assetCode: String; let assetName: String?; let quantity: Double }
}
struct PrismHistory: Decodable {
  let records: [Record]
  let nextOffset: Int?
  struct Record: Decodable, Identifiable {
    let id: String; let settledAt: String; let startedAt: String?; let endedAt: String?; let total: Double; let sessionCount: Int
  }
}
struct PrismCheckout: Decodable {
  let timeline: PrismBillTimeline?
  let settlementPreview: Settlement
  let chargeItems: [Item]; let adjustments: [Item]
  struct Settlement: Decodable { let total: Double }
  struct Item: Decodable, Identifiable { let id: String; let label: String; let amount: Double }
}
/// Shared receipt from `player/checkout/confirm` and `player/checkout/latest`.
struct PrismCheckoutResult: Decodable {
  let timeline: PrismBillTimeline?
  let playerSettlement: Settlement
  let chargeItems: [Item]
  let adjustments: [Item]
  let wallet: Wallet?
  let settlements: [SessionSettlement]?
  struct SessionSettlement: Decodable {
    let settlement: Detail
    struct Detail: Decodable { let sessionId: String; let startedAt: String?; let endedAt: String? }
  }
  struct Settlement: Decodable { let total: Double; let settledAt: String }
  struct Item: Decodable, Identifiable { let id: String; let label: String; let amount: Double }
  struct Wallet: Decodable { let balanceAfter: Double }
  var bill: PrismCheckout {
    PrismCheckout(timeline: timeline, settlementPreview: .init(total: playerSettlement.total),
      chargeItems: chargeItems.map { .init(id: $0.id, label: $0.label, amount: $0.amount) },
      adjustments: adjustments.map { .init(id: $0.id, label: $0.label, amount: $0.amount) })
  }
}
struct PrismLatestCheckout: Decodable { let receipt: PrismCheckoutResult? }
struct PrismDevices: Decodable {
  let devices: [Device]
  struct Device: Decodable, Identifiable {
    let publicId: String; let name: String
    var id: String { publicId }
  }
}

struct PrismPricingSchedule: Decodable {
  let localDate: String; let timeZone: String; let groups: [Group]
  struct Group: Decodable, Identifiable {
    let id: String; let name: String; let kind: String; let amount: Double?; let timeZone: String?; let segments: [Segment]
  }
  struct Segment: Decodable {
    let startLabel: String; let endLabel: String; let label: String; let isClosed: Bool?; let priceCap: Double?
    let pricing: PrismShopResponse.Pricing.Rule.Rate?
  }
}


struct PrismMahjong: Decodable {
  let capacity: Int
  let seats: [Seat]
  struct Seat: Decodable { let name: String; let mine: Bool; let playing: Bool }
}

struct PrismBillTimeline: Decodable {
  let totals: [Total]
  struct Total: Decodable { let name: String; let amount: Double }
  let tracks: [Track]
  let events: [Event]
  struct Track: Decodable, Identifiable {
    let id: String; let name: String; let lane: Int; let color: Int
    let startedAt: String; let endedAt: String
  }
  struct Event: Decodable { let at: String; let time: String; let date: String; let entries: [Entry] }
  struct Entry: Decodable {
    let trackId: String?; let kind: String; let name: String
    let periodLabel: String?
    let rule: String?; let nextRule: String?; let amount: Double?
    let startedAt: String?; let endedAt: String?
    let unitMinutes: Double?; let unitPrice: Double?; let units: Double?
    let cap: Double?; let paidBefore: Double?
  }
}
