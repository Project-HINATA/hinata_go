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
    /// Accepted for wire compatibility but no longer rendered: one session can
    /// stack several billing plans on one timeline, so a single plan name would
    /// mislead. The UI shows only unambiguous aggregates.
    let planLabel: String
    let asOfUnix: Double
    // Additive aggregates of the stacked billing-plan timelines. Older push
    // payloads simply lack these keys (decoded as nil), and older extensions
    // ignore them, so both directions stay wire compatible. The server owns
    // the pricing rules; Swift only renders what it is told. Every value is
    // "as of the last push" — the backend re-pushes at every boundary that
    // changes them (rule switches, cap-window switches, anchor rollovers,
    // charge points), so no horizon bookkeeping lives on this side.
    /// Amount still chargeable before the effective cap, min over the caps in
    /// force at push time; 0 means capped.
    var remainingToCapCents: Int? = nil
    /// False while no stacked plan is billable ("非营业") at this moment.
    var billable: Bool? = nil
    /// The backend's next scheduled recompute-and-push for this session — the
    /// minimum over every alarm source (charges, rule switches, cap-window
    /// switches, billable transitions) after dedup. When present, the UI
    /// renders its countdown as THE next event.
    var nextEvent: NextEvent? = nil
  }

  /// The single next event on the session's alarm timeline, pre-merged by the
  /// backend: coincident events arrive as one entry with a combined label.
  struct NextEvent: Codable, Hashable {
    let atUnix: Double
    /// Server-rendered text for the event (e.g. "下次计费"); the backend owns
    /// the wording. Empty or missing renders the generic "下一事件".
    var label: String? = nil

    var title: String {
      guard let label, !label.isEmpty else { return String(localized: "下一事件") }
      return label
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
