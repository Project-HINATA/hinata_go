import Foundation

// JavaScript semantics the TypeScript billing engine relies on, reproduced so
// the Swift port gives the same answers: epoch-millisecond instants (NaN is an
// invalid Date), `Date.UTC`, `Date#toISOString`, `new Date(string)`, `Number()`,
// `String#localeCompare` and stable `Array#sort`.

/// Mirrors `PrismDomainError` in packages/core/src/errors.ts. Runtime errors that
/// TypeScript raises as `RangeError`/`TypeError` (invalid time zone, invalid
/// date) are reported with the codes `RANGE_ERROR` / `TYPE_ERROR`.
struct PrismDomainError: Error, Equatable, Sendable, CustomStringConvertible {
  let code: String
  let message: String

  init(code: String, message: String) {
    self.code = code
    self.message = message
  }

  init(_ message: String, _ code: String) {
    self.init(code: code, message: message)
  }

  var description: String { "\(code): \(message)" }

  static func rangeError(_ message: String) -> PrismDomainError { PrismDomainError(message, "RANGE_ERROR") }
  static func typeError(_ message: String) -> PrismDomainError { PrismDomainError(message, "TYPE_ERROR") }
}

/// Milliseconds since the Unix epoch, exactly like `Date#getTime()`; `.nan` is an invalid Date.
typealias PrismMs = Double

extension Date {
  /// The JavaScript `getTime()` of this instant. Instants created from integral
  /// milliseconds round-trip exactly.
  var prismMs: PrismMs {
    let value = timeIntervalSince1970 * 1000
    return value.isFinite ? value.rounded() : .nan
  }

  init(prismMs: PrismMs) {
    self.init(timeIntervalSince1970: prismMs / 1000)
  }
}

enum PrismJS {
  static let msPerDay: Double = 86_400_000
  static let maxTime: Double = 8.64e15

  // MARK: Calendar arithmetic (proleptic Gregorian, like ECMAScript)

  static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yoe = y - era * 400
    let mp = (month + 9) % 12
    let doy = (153 * mp + 2) / 5 + day - 1
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146_097 + doe - 719_468
  }

  static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
  }

  static func isLeap(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

  static func daysInMonth(_ year: Int, _ month: Int) -> Int {
    switch month {
    case 2: return isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: return 30
    default: return 31
    }
  }

  /// `Date.UTC(year, monthIndex, day, hours, minutes, seconds, ms)` including
  /// overflow normalisation, the 0–99 → 1900s year rule and TimeClip.
  static func dateUTC(_ year: Double, _ monthIndex: Double, _ day: Double = 1, _ hour: Double = 0,
                      _ minute: Double = 0, _ second: Double = 0, _ ms: Double = 0) -> PrismMs {
    let values = [year, monthIndex, day, hour, minute, second, ms]
    guard values.allSatisfy({ $0.isFinite }) else { return .nan }
    var y = year.rounded(.towardZero)
    if y >= 0 && y <= 99 { y += 1900 }
    let m = monthIndex.rounded(.towardZero)
    let ym = y + (m / 12).rounded(.down)
    guard abs(ym) < 400_000 else { return .nan }
    let mn = Int(m - (m / 12).rounded(.down) * 12)
    let dayNumber = Double(daysFromCivil(Int(ym), mn + 1, 1)) + day.rounded(.towardZero) - 1
    let time = hour.rounded(.towardZero) * 3_600_000 + minute.rounded(.towardZero) * 60_000
      + second.rounded(.towardZero) * 1000 + ms.rounded(.towardZero)
    let result = dayNumber * msPerDay + time
    guard result.isFinite, abs(result) <= maxTime else { return .nan }
    return result + 0 // normalise -0
  }

  struct UTCFields { let year: Int; let month: Int; let day: Int; let hour: Int; let minute: Int; let second: Int; let millisecond: Int; let weekday: Int }

  static func utcFields(_ ms: PrismMs) -> UTCFields {
    let days = Int((ms / msPerDay).rounded(.down))
    let inDay = Int(ms - Double(days) * msPerDay)
    let civil = civilFromDays(days)
    var weekday = (days + 4) % 7
    if weekday < 0 { weekday += 7 }
    return UTCFields(year: civil.year, month: civil.month, day: civil.day, hour: inDay / 3_600_000,
                     minute: inDay / 60_000 % 60, second: inDay / 1000 % 60, millisecond: inDay % 1000, weekday: weekday)
  }

  static func pad(_ value: Int, _ width: Int) -> String {
    let digits = String(abs(value))
    let padded = digits.count >= width ? digits : String(repeating: "0", count: width - digits.count) + digits
    return value < 0 ? "-" + padded : padded
  }

  /// `Date#toISOString()`; throws `RangeError: Invalid time value` for an invalid Date.
  static func isoString(_ ms: PrismMs) throws -> String {
    guard ms.isFinite, abs(ms) <= maxTime else { throw PrismDomainError.rangeError("Invalid time value") }
    let f = utcFields(ms)
    let year: String
    if f.year >= 0 && f.year <= 9999 { year = pad(f.year, 4) } else { year = (f.year < 0 ? "-" : "+") + pad(abs(f.year), 6) }
    return "\(year)-\(pad(f.month, 2))-\(pad(f.day, 2))T\(pad(f.hour, 2)):\(pad(f.minute, 2)):\(pad(f.second, 2)).\(pad(f.millisecond, 3))Z"
  }

  // MARK: Parsing

  /// `new Date(string)` for the ISO-8601 forms the API emits: date-only forms are
  /// UTC, date-times without an offset are local time (as in JavaScript). NaN if unparseable.
  static func parseDate(_ text: String) -> PrismMs {
    let chars = Array(text.trimmingCharacters(in: .whitespaces).utf8)
    var i = 0
    func digits(_ count: Int) -> Int? {
      guard i + count <= chars.count else { return nil }
      var value = 0
      for k in 0..<count {
        let c = chars[i + k]
        guard c >= 48 && c <= 57 else { return nil }
        value = value * 10 + Int(c - 48)
      }
      i += count
      return value
    }
    func take(_ c: UInt8) -> Bool {
      if i < chars.count && chars[i] == c { i += 1; return true }
      return false
    }
    var year: Int
    if i < chars.count && (chars[i] == 43 || chars[i] == 45) {
      let negative = chars[i] == 45
      i += 1
      guard let y = digits(6) else { return .nan }
      if negative && y == 0 { return .nan }
      year = negative ? -y : y
    } else {
      guard let y = digits(4) else { return .nan }
      year = y
    }
    var month = 1, day = 1
    if take(45) {
      guard let m = digits(2) else { return .nan }
      month = m
      if take(45) {
        guard let d = digits(2) else { return .nan }
        day = d
      }
    }
    // Like V8 and JavaScriptCore: any day 1–31 is accepted and overflows into the next month.
    guard month >= 1 && month <= 12, day >= 1, day <= 31 else { return .nan }
    if i == chars.count { return utcDate(year, month, day, 0, 0, 0, 0) }
    guard take(84) || take(116) || take(32) else { return .nan }
    guard let hour = digits(2), take(58), let minute = digits(2) else { return .nan }
    var second = 0, millisecond = 0
    if take(58) {
      guard let s = digits(2) else { return .nan }
      second = s
      if take(46) || take(44) {
        var fraction = 0, count = 0
        while i < chars.count, chars[i] >= 48, chars[i] <= 57 {
          if count < 3 { fraction = fraction * 10 + Int(chars[i] - 48) }
          count += 1
          i += 1
        }
        guard count > 0 else { return .nan }
        for _ in count..<max(count, 3) { fraction *= 10 }
        millisecond = fraction
      }
    }
    guard minute <= 59, second <= 59, hour <= 24, hour < 24 || (minute == 0 && second == 0 && millisecond == 0) else { return .nan }
    var offsetMs: Double? = nil
    if take(90) || take(122) {
      offsetMs = 0
    } else if i < chars.count && (chars[i] == 43 || chars[i] == 45) {
      let sign: Double = chars[i] == 45 ? -1 : 1
      i += 1
      guard let oh = digits(2) else { return .nan }
      _ = take(58)
      guard let om = digits(2), oh <= 23, om <= 59 else { return .nan }
      offsetMs = sign * Double(oh * 3_600_000 + om * 60_000)
    }
    guard i == chars.count else { return .nan }
    let local = utcDate(year, month, day, hour, minute, second, millisecond)
    guard local.isFinite else { return .nan }
    if let offsetMs { return clip(local - offsetMs) }
    // Local time, as JavaScript interprets an offset-less date-time.
    let zone = TimeZone.current
    var guess = local
    for _ in 0..<2 {
      guess = local - Double(zone.secondsFromGMT(for: Date(prismMs: guess))) * 1000
    }
    return clip(guess)
  }

  private static func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int, _ ms: Int) -> PrismMs {
    let days = Double(daysFromCivil(year, month, day))
    return clip(days * msPerDay + Double(hour * 3_600_000 + minute * 60_000 + second * 1000 + ms))
  }

  private static func clip(_ ms: Double) -> PrismMs {
    guard ms.isFinite, abs(ms) <= maxTime else { return .nan }
    return ms + 0
  }

  /// `Number(string)`.
  static func number(_ text: String) -> Double {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return 0 }
    switch trimmed {
    case "Infinity", "+Infinity": return .infinity
    case "-Infinity": return -.infinity
    default: break
    }
    let lower = trimmed.lowercased()
    for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where lower.hasPrefix(prefix) {
      let body = lower.dropFirst(2)
      guard !body.isEmpty else { return .nan }
      var value = 0.0
      for ch in body {
        guard let d = ch.hexDigitValue, d < radix else { return .nan }
        value = value * Double(radix) + Double(d)
      }
      return value
    }
    let allowed = Set("0123456789+-.eE")
    guard trimmed.allSatisfy({ allowed.contains($0) }) else { return .nan }
    var body = Substring(trimmed)
    if body.first == "+" || body.first == "-" { body = body.dropFirst() }
    guard let first = body.first, first.isNumber || first == "." else { return .nan }
    let mantissa = body.split(separator: "e", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let mantissaDigits = mantissa.split(separator: "E", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    guard mantissaDigits.contains(where: { $0.isNumber }) else { return .nan }
    return Double(trimmed) ?? .nan
  }

  /// `Number.isSafeInteger`.
  static func isSafeInteger(_ value: Double) -> Bool {
    value.isFinite && value.rounded(.towardZero) == value && abs(value) <= 9_007_199_254_740_991
  }

  // MARK: localeCompare

  /// CLDR root collation order (non-ignorable punctuation) for printable ASCII,
  /// exactly as `String#localeCompare` sorts it in Safari/Chrome/Bun.
  private static let asciiPrimaryOrder: [UInt8: Int] = {
    let order = " _-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$0123456789aAbBcCdDeEfFgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwWxXyYzZ"
    var map: [UInt8: Int] = [:]
    var weight = 0
    for byte in order.utf8 {
      if byte >= 65 && byte <= 90 { map[byte] = map[byte + 32]!; continue }
      weight += 1
      map[byte] = weight
    }
    return map
  }()

  /// `a.localeCompare(b)` with the default (root/en) collator: -1, 0 or 1.
  static func localeCompare(_ a: String, _ b: String) -> Int {
    if a == b { return 0 }
    let left = Array(a.utf8), right = Array(b.utf8)
    if left.allSatisfy({ $0 >= 32 && $0 < 127 }) && right.allSatisfy({ $0 >= 32 && $0 < 127 }) {
      let lp = left.map { asciiPrimaryOrder[$0] ?? 0 }, rp = right.map { asciiPrimaryOrder[$0] ?? 0 }
      for (x, y) in zip(lp, rp) where x != y { return x < y ? -1 : 1 }
      if lp.count != rp.count { return lp.count < rp.count ? -1 : 1 }
      for (x, y) in zip(left, right) {
        let xu = x >= 65 && x <= 90, yu = y >= 65 && y <= 90
        if xu != yu { return xu ? 1 : -1 }
      }
      return 0
    }
    // Outside printable ASCII, defer to the platform's ICU-backed collation.
    switch a.compare(b, options: [], range: nil, locale: Locale(identifier: "en_US")) {
    case .orderedAscending: return -1
    case .orderedDescending: return 1
    case .orderedSame: return 0
    }
  }
}

extension Array {
  /// Stable sort with a JavaScript-style comparator (negative, zero/NaN, positive),
  /// i.e. `Array#sort` semantics for a consistent comparator.
  func prismSorted(_ compare: (Element, Element) -> Double) -> [Element] {
    enumerated().sorted { lhs, rhs in
      let c = compare(lhs.element, rhs.element)
      if c < 0 { return true }
      if c > 0 { return false }
      return lhs.offset < rhs.offset
    }.map { $0.element }
  }
}

/// A `Map` with JavaScript insertion-order iteration.
struct PrismOrderedMap<Key: Hashable, Value> {
  private(set) var keys: [Key] = []
  private var storage: [Key: Value] = [:]

  init() {}

  subscript(key: Key) -> Value? {
    get { storage[key] }
    set {
      if let newValue {
        if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
      } else if storage.removeValue(forKey: key) != nil {
        keys.removeAll { $0 == key }
      }
    }
  }

  func has(_ key: Key) -> Bool { storage[key] != nil }
  var count: Int { keys.count }
  var values: [Value] { keys.map { storage[$0]! } }
  var entries: [(key: Key, value: Value)] { keys.map { ($0, storage[$0]!) } }
}

/// An opaque JSON value (`metadata`, effect `config`), kept as TypeScript keeps it.
enum PrismJSONValue: Codable, Hashable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([PrismJSONValue])
  case object([String: PrismJSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null }
    else if let value = try? container.decode(Bool.self) { self = .bool(value) }
    else if let value = try? container.decode(Double.self) { self = .number(value) }
    else if let value = try? container.decode(String.self) { self = .string(value) }
    else if let value = try? container.decode([PrismJSONValue].self) { self = .array(value) }
    else { self = .object(try container.decode([String: PrismJSONValue].self)) }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  /// JavaScript truthiness.
  var isTruthy: Bool {
    switch self {
    case .null: return false
    case .bool(let value): return value
    case .number(let value): return value != 0 && !value.isNaN
    case .string(let value): return !value.isEmpty
    case .array, .object: return true
    }
  }

  subscript(key: String) -> PrismJSONValue? {
    if case .object(let object) = self { return object[key] }
    return nil
  }

  var numberValue: Double? { if case .number(let value) = self { return value }; return nil }
  var stringValue: String? { if case .string(let value) = self { return value }; return nil }
  var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
  var arrayValue: [PrismJSONValue]? { if case .array(let value) = self { return value }; return nil }
}

// MARK: Wire instants

/// A required instant carried as an ISO string on the wire (`Date#toJSON`).
@propertyWrapper
struct PrismISODate: Codable, Hashable, Sendable {
  var wrappedValue: Date
  init(wrappedValue: Date) { self.wrappedValue = wrappedValue }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    wrappedValue = Date(prismMs: try prismDecodeInstant(container))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try PrismJS.isoString(wrappedValue.prismMs))
  }
}

/// An optional instant: absent or null decode to nil; nil is omitted when encoding
/// (`undefined` in TypeScript).
@propertyWrapper
struct PrismOptionalISODate: Codable, Hashable, Sendable {
  var wrappedValue: Date?
  init(wrappedValue: Date?) { self.wrappedValue = wrappedValue }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    wrappedValue = container.decodeNil() ? nil : Date(prismMs: try prismDecodeInstant(container))
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    if let value = wrappedValue { try container.encode(try PrismJS.isoString(value.prismMs)) } else { try container.encodeNil() }
  }
}

private func prismDecodeInstant(_ container: SingleValueDecodingContainer) throws -> PrismMs {
  if let text = try? container.decode(String.self) { return PrismJS.parseDate(text) }
  // A number is already epoch milliseconds (`new Date(number)`).
  return try container.decode(Double.self)
}

extension KeyedDecodingContainer {
  func decode(_ type: PrismOptionalISODate.Type, forKey key: Key) throws -> PrismOptionalISODate {
    try decodeIfPresent(type, forKey: key) ?? PrismOptionalISODate(wrappedValue: nil)
  }
}

extension KeyedEncodingContainer {
  mutating func encode(_ value: PrismOptionalISODate, forKey key: Key) throws {
    guard let date = value.wrappedValue else { return }
    try encode(try PrismJS.isoString(date.prismMs), forKey: key)
  }
}
