import Foundation

/// Wall-clock arithmetic of packages/core/src/pricing-time.ts (`getZonedParts`,
/// `zonedLocalTimeToUtc`, `parseLocalDateTime`, `formatLocalDate`, `addLocalDays`)
/// and the display helpers of api-time.ts. TypeScript reads IANA zones through
/// `Intl.DateTimeFormat`; here Foundation's `TimeZone` supplies the same offsets.
/// The algorithms (including the three-step offset iteration that resolves DST
/// gaps and overlaps) are reproduced verbatim so gaps/overlaps land on the same instants.
enum PrismZones {
  struct Parts: Hashable, Sendable {
    let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, weekday: Int
  }

  private static let lock = NSLock()
  nonisolated(unsafe) private static var cache: [String: TimeZone] = [:]

  static func zone(_ identifier: String) throws -> TimeZone {
    lock.lock()
    defer { lock.unlock() }
    if let cached = cache[identifier] { return cached }
    guard let zone = TimeZone(identifier: identifier) else {
      throw PrismDomainError.rangeError("Invalid time zone specified: \(identifier)")
    }
    cache[identifier] = zone
    return zone
  }

  /// `getZonedParts`: the wall clock of `ms` in `timeZone` (seconds truncated, like Intl).
  static func parts(_ ms: PrismMs, _ timeZone: String) throws -> Parts {
    var local = ms
    if timeZone != "UTC" {
      let zone = try zone(timeZone)
      guard ms.isFinite else { throw PrismDomainError.rangeError("Invalid time value") }
      local = ms + Double(zone.secondsFromGMT(for: Date(prismMs: ms))) * 1000
    } else if !ms.isFinite {
      throw PrismDomainError.rangeError("Invalid time value")
    }
    let f = PrismJS.utcFields(local)
    return Parts(year: f.year, month: f.month, day: f.day, hour: f.hour, minute: f.minute, second: f.second, weekday: f.weekday)
  }

  static func zonedLocalTimeToUtc(year: Double, month: Double, day: Double, hour: Double, minute: Double, _ timeZone: String) throws -> PrismMs {
    var utc = PrismJS.dateUTC(year, month - 1, day, hour, minute, 0, 0)
    if timeZone == "UTC" { return utc }
    for _ in 0..<3 {
      let offset = try timeZoneOffsetMs(utc, timeZone)
      utc = PrismJS.dateUTC(year, month - 1, day, hour, minute, 0, 0) - offset
    }
    return utc
  }

  static func timeZoneOffsetMs(_ ms: PrismMs, _ timeZone: String) throws -> Double {
    let p = try parts(ms, timeZone)
    let localAsUtc = PrismJS.dateUTC(Double(p.year), Double(p.month - 1), Double(p.day), Double(p.hour), Double(p.minute), Double(p.second), 0)
    return localAsUtc - ms
  }

  /// `parseLocalDateTime(localDate, time, timeZone)`.
  static func parseLocalDateTime(_ localDate: String, _ time: String, _ timeZone: String) throws -> PrismMs {
    let fields = localDate.split(separator: "-", omittingEmptySubsequences: false).map { PrismJS.number(String($0)) }
    let minutes = parseClockMinutes(time)
    func field(_ index: Int) -> Double { index < fields.count ? fields[index] : .nan }
    return try zonedLocalTimeToUtc(year: field(0), month: field(1), day: field(2),
                                   hour: (minutes / 60).rounded(.down),
                                   minute: minutes.truncatingRemainder(dividingBy: 60), timeZone)
  }

  /// `parseClockMinutes("HH:mm")`.
  static func parseClockMinutes(_ time: String) -> Double {
    let fields = time.split(separator: ":", omittingEmptySubsequences: false).map { PrismJS.number(String($0)) }
    guard fields.count >= 2 else { return .nan }
    return fields[0] * 60 + fields[1]
  }

  static func formatLocalDate(_ ms: PrismMs, _ timeZone: String) throws -> String {
    formatLocalDate(try parts(ms, timeZone))
  }

  static func formatLocalDate(_ p: Parts) -> String {
    "\(p.year)-\(PrismJS.pad(p.month, 2))-\(PrismJS.pad(p.day, 2))"
  }

  /// `addLocalDays(localDate, days)` (calendar arithmetic in UTC).
  static func addLocalDays(_ localDate: String, _ days: Double) -> String {
    let fields = localDate.split(separator: "-", omittingEmptySubsequences: false).map { PrismJS.number(String($0)) }
    func field(_ index: Int) -> Double { index < fields.count ? fields[index] : .nan }
    let ms = PrismJS.dateUTC(field(0), field(1) - 1, field(2) + days, 0, 0, 0, 0)
    guard ms.isFinite else { return "NaN-NaN-NaN" }
    let f = PrismJS.utcFields(ms)
    return "\(f.year)-\(PrismJS.pad(f.month, 2))-\(PrismJS.pad(f.day, 2))"
  }

  /// The `{ date, time }` that `timestampDisplayParts(formatOffsetTimestamp(iso, timeZone))`
  /// yields for an instant: its wall-clock date (`YYYY-MM-DD`) and time (`HH:mm`) in `timeZone`.
  static func displayParts(_ ms: PrismMs, _ timeZone: String) throws -> (date: String, time: String) {
    if timeZone == "UTC" {
      let iso = try PrismJS.isoString(ms)
      let chars = Array(iso)
      guard chars.count >= 16, iso.first != "+", iso.first != "-" else { throw PrismDomainError.typeError("Cannot read properties of null") }
      return (String(chars[0..<10]), String(chars[11..<16]))
    }
    _ = try PrismJS.isoString(ms)
    let p = try parts(ms, timeZone)
    guard p.year >= 0 && p.year <= 9999 else { throw PrismDomainError.typeError("Cannot read properties of null") }
    return ("\(PrismJS.pad(p.year, 4))-\(PrismJS.pad(p.month, 2))-\(PrismJS.pad(p.day, 2))",
            "\(PrismJS.pad(p.hour, 2)):\(PrismJS.pad(p.minute, 2))")
  }

  /// `formatOffsetTimestamp(iso, timeZone)` for an instant: local wall time with
  /// milliseconds and the zone's offset (`Z` when it is zero).
  static func offsetTimestamp(_ ms: PrismMs, _ timeZone: String) throws -> String {
    if timeZone == "UTC" { return try PrismJS.isoString(ms) }
    _ = try PrismJS.isoString(ms)
    let p = try parts(ms, timeZone)
    let local = "\(PrismJS.pad(p.year, 4))-\(PrismJS.pad(p.month, 2))-\(PrismJS.pad(p.day, 2))T\(PrismJS.pad(p.hour, 2)):\(PrismJS.pad(p.minute, 2)):\(PrismJS.pad(p.second, 2))"
    let localMs = PrismJS.dateUTC(Double(p.year), Double(p.month - 1), Double(p.day), Double(p.hour), Double(p.minute), Double(p.second), 0)
    let offsetMinutes = Int(((localMs - (ms / 1000).rounded(.down) * 1000) / 60_000 + 0.5).rounded(.down))
    let minutes = abs(offsetMinutes)
    let offset = "\(offsetMinutes < 0 ? "-" : "+")\(PrismJS.pad(minutes / 60, 2)):\(PrismJS.pad(minutes % 60, 2))"
    let millis = PrismJS.utcFields(ms).millisecond
    return "\(local).\(PrismJS.pad(millis, 3))\(offsetMinutes == 0 ? "Z" : offset)"
  }
}
