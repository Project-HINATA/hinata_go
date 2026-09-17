import ActivityKit
import Foundation

struct StoreVisitAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let phase: String
    let startedAtUnix: Double
    let endedAtUnix: Double?
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
