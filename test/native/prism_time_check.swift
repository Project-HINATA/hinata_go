import Foundation
#if os(Linux)
// Corelibs Foundation does not ship Apple's String localization initializer.
extension String { init(localized value: String) { self = value } }
#endif

@main struct PrismTimeCheck {
  static func main() throws {
    let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    let newYork = TimeZone(identifier: "America/New_York")!
    let at = "2026-10-03T10:08:00.123+08:00"
    precondition(prismParsedDate(at) == prismParsedDate("2026-10-03T02:08:00.123Z"))
    precondition(prismDisplayClock(at, timeZone: shanghai) == "10:08")
    precondition(prismDisplayClock(at, timeZone: tokyo) == "11:08")
    precondition(prismDisplayPeriod(at, "2026-10-03T11:54:00.123+08:00", timeZone: tokyo) == "11:08 – 12:54")
    precondition(prismParsedDate("2026-10-03T11:54:00.123+08:00")!.timeIntervalSince(prismParsedDate(at)!) == 106 * 60)
    precondition(prismDisplayPeriod("2026-10-03T23:50:00+08:00", "2026-10-04T00:10:00+08:00", timeZone: shanghai) == "10-03 23:50 – 10-04 00:10")
    let start = "2026-11-01T01:10:00-04:00", end = "2026-11-01T01:20:00-05:00"
    precondition(prismParsedDate(end)!.timeIntervalSince(prismParsedDate(start)!) == 70 * 60)
    precondition(prismDisplayPeriod(start, end, timeZone: newYork) == "01:10 UTC-04:00 – 01:20 UTC-05:00")
    precondition(prismDisplayClock("invalid", timeZone: tokyo) == "—")
    precondition(prismDisplayPeriod("invalid", end) == nil)
    precondition(prismDisplayPeriod(end, start) == nil)
    let clock = prismRuleClock(start: "02:00", end: "19:00", sourceZone: "UTC", displayZone: "Asia/Shanghai", referenceDate: "2026-10-03")!
    precondition(clock.start == "10:00" && clock.end == "03:00" && clock.dayShift == 0)
    precondition(clock.endDate.timeIntervalSince(clock.startDate) == 17 * 3600)
    let shifted = prismRuleClock(start: "22:00", end: "23:00", sourceZone: "UTC", displayZone: "Asia/Tokyo", referenceDate: "2026-10-03")!
    precondition(shifted.start == "07:00" && shifted.end == "08:00" && shifted.dayShift == 1)
    let decoded = try JSONDecoder().decode(PrismBillTimeline.self, from: Data(#"{"totals":[],"tracks":[],"events":[{"at":"2026-10-03T10:08:00+08:00","time":"02:08","date":"2026-10-03","entries":[{"kind":"end","name":"计费","startedAt":"2026-10-03T10:08:00+08:00","endedAt":"2026-10-03T11:54:00+08:00","periodLabel":"02:08 – 03:54"}]}]}"#.utf8))
    let event = decoded.events[0], entry = event.entries[0]
    precondition(prismDisplayClock(event.at, timeZone: tokyo) == "11:08")
    precondition(prismDisplayPeriod(entry.startedAt!, entry.endedAt!, timeZone: tokyo) == "11:08 – 12:54")
    print("Native time checks passed: carried offsets, phone/shop zones, midnight, DST, unchanged duration and stale labels.")
  }
}
