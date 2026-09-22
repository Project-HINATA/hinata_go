import ActivityKit
import Foundation

struct StoreVisitAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let phase: String
    let startedAtUnix: Double
    let endedAtUnix: Double?
    var bill: Bill? = nil
  }

  struct Bill: Codable, Hashable {
    let amountCents: Int
    let planLabel: String
    let nextChargeAtUnix: Double?
    let nextRuleAtUnix: Double?
    let asOfUnix: Double

    var nextEvent: (date: Date, title: String)? {
      let charge = nextChargeAtUnix.flatMap { $0.isFinite && $0 > asOfUnix ? $0 : nil }
      let rule = nextRuleAtUnix.flatMap { $0.isFinite && $0 > asOfUnix ? $0 : nil }
      if let charge, let rule, charge == rule {
        return (Date(timeIntervalSince1970: charge), String(localized: "计费与规则切换"))
      }
      if let charge, charge < (rule ?? .infinity) {
        return (Date(timeIntervalSince1970: charge), String(localized: "下次计费"))
      }
      if let rule { return (Date(timeIntervalSince1970: rule), String(localized: "规则切换")) }
      return nil
    }
  }

  let sessionId: String
  let shopCode: String
  let shopName: String
  /// HTTPS origin of the deployment that started this activity, so a tap can be sent to the
  /// matching host (`link.neri.moe`, the beta host, ...). Optional because an activity left
  /// over from an earlier build must still decode after an upgrade; when it is missing or
  /// not HTTPS we simply do not attach a `widgetURL`.
  let origin: String?

  /// The ticket-free shop page for this visit, or nil when no usable origin was recorded.
  var shopURL: URL? {
    guard let origin, let base = URL(string: origin), base.scheme?.lowercased() == "https" else {
      return nil
    }
    return base.appendingPathComponent("t").appendingPathComponent(shopCode)
  }
}
