import Foundation

protocol PrismRetryAfterProviding: Error { var retryAfter: TimeInterval? { get } }

func prismParsedDate(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

/// API offsets locate absolute instants. Personal event labels use the phone's display zone.
func prismDisplayDate(_ value: String, timeZone: TimeZone = .current) -> String {
  guard let date = prismParsedDate(value) else { return "—" }
  let formatter = DateFormatter()
  formatter.timeZone = timeZone
  formatter.dateStyle = .short; formatter.timeStyle = .short
  return formatter.string(from: date)
}
func prismDisplayClock(_ value: String, seconds: Bool = false, timeZone: TimeZone = .current) -> String {
  guard let date = prismParsedDate(value) else { return "—" }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX")
  formatter.timeZone = timeZone
  formatter.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
  return formatter.string(from: date)
}
func prismDisplayDay(_ value: String, timeZone: TimeZone = .current) -> String {
  guard let date = prismParsedDate(value) else { return "—" }
  let formatter = DateFormatter()
  formatter.timeZone = timeZone
  formatter.setLocalizedDateFormatFromTemplate("MMMd")
  return formatter.string(from: date)
}
/// The calendar day an instant falls on in the phone's zone, as `yyyy-MM-dd`.
func prismLocalDay(_ value: String, timeZone: TimeZone = .current) -> String {
  guard let date = prismParsedDate(value) else { return "" }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from: date)
}
func prismDisplayPeriod(_ start: String, _ end: String, timeZone: TimeZone = .current) -> String? {
  guard let startDate = prismParsedDate(start), let endDate = prismParsedDate(end), endDate >= startDate else { return nil }
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
  let startDay = formatter.string(from: startDate), endDay = formatter.string(from: endDate)
  var startClock = prismDisplayClock(start, timeZone: timeZone), endClock = prismDisplayClock(end, timeZone: timeZone)
  let startOffset = timeZone.secondsFromGMT(for: startDate), endOffset = timeZone.secondsFromGMT(for: endDate)
  if startOffset != endOffset {
    func offset(_ seconds: Int) -> String {
      let minutes = abs(seconds) / 60
      return String(format: "UTC%@%02d:%02d", seconds < 0 ? "-" : "+", minutes / 60, minutes % 60)
    }
    startClock += " " + offset(startOffset); endClock += " " + offset(endOffset)
  }
  if startDay == endDay { return startClock + " – " + endClock }
  let sameYear = startDay.prefix(4) == endDay.prefix(4)
  return (sameYear ? String(startDay.dropFirst(5)) : startDay) + " " + startClock + " – " + (sameYear ? String(endDay.dropFirst(5)) : endDay) + " " + endClock
}

/// Shop-rule editors still project UTC clocks using the shop's geographic IANA zone.
struct PrismRuleClock {
  let start: String; let end: String; let dayShift: Int
  let startDate: Date; let endDate: Date
}
func prismRuleClock(start: String, end: String, sourceZone: String, displayZone: String, referenceDate: String) -> PrismRuleClock? {
  let source = TimeZone(identifier: sourceZone) ?? TimeZone(secondsFromGMT: 0)!
  let display = TimeZone(identifier: displayZone) ?? TimeZone(secondsFromGMT: 0)!
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian)
  formatter.timeZone = source; formatter.dateFormat = "yyyy-MM-dd HH:mm"
  guard let startDate = formatter.date(from: referenceDate + " " + start), let sameDayEnd = formatter.date(from: referenceDate + " " + end) else { return nil }
  var sourceCalendar = Calendar(identifier: .gregorian); sourceCalendar.timeZone = source
  let endDate = start >= end ? sourceCalendar.date(byAdding: .day, value: 1, to: sameDayEnd)! : sameDayEnd
  formatter.timeZone = display; formatter.dateFormat = "HH:mm"
  let startClock = formatter.string(from: startDate), endClock = formatter.string(from: endDate)
  // Compare Gregorian civil dates, independent of either region's DST day length.
  var displayCalendar = Calendar(identifier: .gregorian); displayCalendar.timeZone = display
  var utcCalendar = Calendar(identifier: .gregorian); utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
  func civilDay(_ date: Date, _ calendar: Calendar) -> Date {
    utcCalendar.date(from: calendar.dateComponents([.year, .month, .day], from: date))!
  }
  let shift = Int(civilDay(startDate, displayCalendar).timeIntervalSince(civilDay(startDate, sourceCalendar)) / 86400)
  return PrismRuleClock(start: startClock, end: endClock, dayShift: shift, startDate: startDate, endDate: endDate)
}

struct PublicMachine: Decodable {
  let publicId: String
  let name: String
  let shop: Shop
  let webOnly: Bool?
  let capabilities: [String: Bool]?
  /// A card can be added at this cabinet's reader.
  var cardCapture: Bool? = nil
  func has(_ capability: String) -> Bool { capabilities == nil ? capability == "card" : capabilities?[capability] == true }
  var empty: Bool { capabilities != nil && !capabilities!.values.contains(true) }
  /// Nothing to operate here and nothing to confirm: a resource without hardware still bills in a shop that bills.
  var idle: Bool { empty && shop.billingEnabled != true }
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

struct PrismMunetAuthenticationResult {
  let code: String
  let suggestPasskey: Bool
}

struct PasskeyRegistrationOptions: Decodable {
  let challenge: String
  let rp: RelyingParty
  let user: Account
  struct RelyingParty: Decodable { let id: String }
  struct Account: Decodable { let id: String; let name: String; let displayName: String }
}
struct PasskeyRegistration: Encodable {
  let id: String
  let rawId: String
  let response: Response
  let type: String
  let clientExtensionResults: [String: String]
  let authenticatorAttachment: String
  struct Response: Encodable {
    let clientDataJSON: String
    let attestationObject: String
    let transports: [String]
  }
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

struct EmptyResponse: Decodable {
  let ok: Bool
}

/// What the server wants the player told, and how. `dialog` interrupts, `inline` belongs
/// next to what they touched, `none` only runs `flow` (expired, refresh, signin).
struct PrismNotice: Codable, Equatable {
  let code: String
  let level: String
  let display: String
  var presentation: String? = nil
  let flow: String
  var title: String? = nil
  let body: String
  var actions: [Action] = []
  struct Action: Codable, Equatable, Hashable { let kind: String; let label: String }
}

/// A notice has two natures: news (`info`, and `success`, which is news with a tick) and
/// `error`, meaning what the player asked for did not happen. Anything else (an older
/// server's `warning`) reads as an error.
func noticeIsError(_ level: String) -> Bool { level != "success" && level != "info" }

/// How long an inline notice stays: news fades by itself; an error stays until the player
/// acts again (`nil`), unless it sits on a control whose own label has to come back.
func noticeLasts(_ level: String, onControl: Bool = false) -> UInt64? {
  switch level {
  case "success": return 3_000_000_000
  case "info": return 4_000_000_000
  default: return onControl ? 5_000_000_000 : nil
  }
}

/// Controls briefly hold their result; field and status feedback lasts until replaced.
func noticeDuration(_ notice: PrismNotice, onControl: Bool) -> UInt64? {
  if onControl { return noticeLasts(notice.level, onControl: true) }
  if notice.presentation == "status" || notice.presentation == "field" { return nil }
  return noticeLasts(notice.level, onControl: notice.presentation == "toast")
}

/// A swipe's outcome on the row of the card it came from: the card's part, then the coin's,
/// each coloured by its own level.
struct CardFeedback: Equatable {
  let cardId: String
  let parts: [Part]
  struct Part: Equatable { let level: String; let text: String }
  /// The row reads as its worst part: an error, else news, else a success.
  var level: String {
    if parts.contains(where: { noticeIsError($0.level) }) { return "error" }
    return parts.contains(where: { $0.level == "info" }) ? "info" : "success"
  }
}

/// What confirming this resource would do to the player's billing, or why it cannot bill.
struct PrismResourceBilling: Decodable {
  var preview: Preview? = nil
  var error: Failure? = nil
  /// The plans this resource bills, shown as its pricing rules.
  var rules: Rules? = nil

  struct Change: Decodable { let planId: String; let planName: String }
  struct Preview: Decodable {
    let pricingConfigId: String; let planName: String; let changed: Bool
    let started: [Change]; let stopped: [Change]; let kept: [Change]
    /// Sent back with the confirmation: the server refuses one made against a state that has since changed.
    let revision: String
  }
  struct Failure: Decodable { let code: String; let message: String }

  /// The plans a scanned resource bills, as the server resolved them for this player. Each
  /// plan's day is computed on the phone, as the web page computes it.
  struct Rules: Decodable {
    let plans: [Plan]
    /// Read before confirming: the unsettled bill so far, each plan's cap for the period it
    /// is in (none for an uncapped period), and the caps across plans. Money in yuan.
    var caps: Caps? = nil
    /// The shop's zone; rules are stored in UTC.
    let timeZone: String
    struct Plan: Decodable { let config: PrismPricingConfig; let role: String }
    struct Caps: Decodable { let unsettled: Double; let plans: [CapProgress]; let shared: [SharedCap] }
    struct CapProgress: Decodable {
      let pricingConfigId: String; let ruleId: String; let ruleLabel: String
      let priceCap: Double; let paidBefore: Double
      /// The window the cap is counting now.
      let startsAt: String; let endsAt: String
    }
    struct SharedCap: Decodable {
      let pricingConfigId: String; let ruleId: String; let ruleLabel: String
      let priceCap: Double; let paidBefore: Double; let startsAt: String; let endsAt: String
      let name: String; let config: PrismPricingConfig
    }
  }
}

/// A Home Assistant air conditioner as the device state reports it. The modes, fan speeds
/// and temperature range are the entity's own, so the controls only offer those.
struct PrismClimate: Decodable, Equatable {
  var mode: String
  var modes: [String]? = nil
  var temperature: Double? = nil
  var currentTemperature: Double? = nil
  var minTemperature: Double? = nil
  var maxTemperature: Double? = nil
  var temperatureStep: Double? = nil
  var fanMode: String? = nil
  var fanModes: [String]? = nil

  var isOn: Bool { mode != "off" }
  var choosableModes: [String] { (modes ?? []).filter { $0 != "off" } }

  /// The target after `steps` presses of − / +, kept inside the entity's range and step.
  func nudged(_ current: Double, by steps: Int) -> Double {
    let step = temperatureStep ?? 0.5
    let next = (current + Double(steps) * step).clamped(minTemperature ?? 16, maxTemperature ?? 30)
    return (next / step).rounded() * step
  }
}

private extension Double {
  func clamped(_ low: Double, _ high: Double) -> Double { Swift.min(high, Swift.max(low, self)) }
}
/// A platform binding code, with the shop's instructions already worded by the platform.
struct PrismBinding: Decodable {
  let code: String
  let expiresAt: String
  let lines: [PrismBindingPromptLine]
}

struct PrismBindingPromptLine: Decodable, Equatable { let text: String; let command: Bool }
struct PrismShopResponse: Decodable {
  let shop: Settings
  let membership: Membership?
  let entryPricing: [Pricing]
  var pricingSchedule: PrismPricingSchedule? = nil
  struct Membership: Decodable {
    let playerId: String
    var identityBound: Bool? = nil
    // Older APIs only created membership after verification; explicit false must win.
    var hasPlatformIdentity: Bool { identityBound ?? true }
  }
  func requiresPlatformBinding(hasActiveSession: Bool) -> Bool {
    shop.billingEnabled && shop.identityBindingRequired != false
      && membership?.hasPlatformIdentity != true && !hasActiveSession
  }
  struct Settings: Decodable {
    let name: String?
    var locationEnabled: Bool? = nil
    var identityBindingRequired: Bool? = nil
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
struct PrismCheckout: Decodable {
  let timeline: PrismBillTimeline?
  let settlementPreview: Settlement
  let chargeItems: [Item]; let adjustments: [Item]
  struct Settlement: Decodable { let total: Double }
  struct Item: Decodable, Identifiable { let id: String; let label: String; let amount: Double }
}
extension PrismCheckout {
  /// A bill the phone computed, as the server's preview would have sent it.
  init(_ view: PrismCheckoutPreviewView) {
    self.init(timeline: view.timeline, settlementPreview: .init(total: view.settlementPreview.total),
      chargeItems: view.chargeItems.map { .init(id: $0.id, label: $0.label, amount: $0.amount) },
      adjustments: view.adjustments.map { .init(id: $0.id, label: $0.label, amount: $0.amount) })
  }
}
struct PrismCardCapture: Decodable { let captureId: String; let expiresAt: String }
/// `waiting` until the reader reports a card or the window ends (`expired`); `added`, `bound` and
/// `exists` all leave the card on the account.
struct PrismCardCaptureResult: Decodable { let status: String; var cardType: String? = nil }
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
    var ruleId: String? = nil
    var startedAt: String? = nil
    var endedAt: String? = nil
    let pricing: PrismShopResponse.Pricing.Rule.Rate?
  }
}
