import Foundation

/// Money arithmetic of packages/core/src/money.ts. Amounts are whole cents
/// (`Int`, 64-bit on every Apple platform); configuration and API boundaries speak yuan.
enum PrismMoney {
  static let centsPerYuan = 100
  static let maxSafeInteger = 9_007_199_254_740_991

  enum RoundingMode: Sendable { case floor, ceil, trunc, half }

  /// `centsOf`: yuan → cents, rounding half away from zero on the number's
  /// shortest decimal representation (exactly like the TypeScript string-based version).
  static func centsOf(_ yuan: Double) throws -> Int {
    guard yuan.isFinite else { throw PrismDomainError("Money must be a finite number.", "INVALID_MONEY") }
    let (digits, decimalExponent) = shortestDecimal(abs(yuan))
    let exponent = decimalExponent + 2 // yuan → cents
    var rounded: Int
    if exponent >= 0 {
      guard exponent <= 18 else { throw PrismDomainError("Cents must be a whole number.", "INVALID_MONEY") }
      let (scaled, overflow) = digits.multipliedReportingOverflow(by: pow10(exponent))
      guard !overflow else { throw PrismDomainError("Cents must be a whole number.", "INVALID_MONEY") }
      rounded = scaled
    } else if -exponent > 18 {
      rounded = 0
    } else {
      let divisor = pow10(-exponent)
      rounded = (digits + divisor / 2) / divisor
    }
    if yuan < 0 { rounded = -rounded }
    return try centsOfInteger(Double(rounded))
  }

  /// `centsOfInteger`: an exact count of cents.
  static func centsOfInteger(_ value: Double) throws -> Int {
    guard PrismJS.isSafeInteger(value) else { throw PrismDomainError("Cents must be a whole number.", "INVALID_MONEY") }
    return Int(value)
  }

  static func checkedCents(_ value: Int) throws -> Int {
    guard abs(value) <= maxSafeInteger else { throw PrismDomainError("Cents must be a whole number.", "INVALID_MONEY") }
    return value
  }

  /// `yuanOf`: cents → yuan for an output boundary.
  static func yuanOf(_ cents: Int) -> Double { cents == 0 ? 0 : Double(cents) / Double(centsPerYuan) }

  /// `quantizeMoney`: snaps a yuan amount to whole cents; non-finite input passes through.
  static func quantizeMoney(_ value: Double) throws -> Double {
    guard value.isFinite else { return value }
    return yuanOf(try centsOf(value))
  }

  static func unitsOf(_ value: Double) throws -> Double {
    guard PrismJS.isSafeInteger(value) else { throw PrismDomainError("Units must be a whole number.", "INVALID_UNITS") }
    return value == 0 ? 0 : value
  }

  static func assetQuantityOf(_ assetType: String, _ value: Double) throws -> Double {
    assetType == "currency" ? Double(try centsOf(value)) : try unitsOf(value)
  }

  static func assetQuantityFromStored(_ assetType: String, _ value: Double) throws -> Double {
    assetType == "currency" ? Double(try centsOfInteger(value)) : try unitsOf(value)
  }

  static func add(_ left: Int, _ right: Int) throws -> Int { try checkedCents(left + right) }
  static func sub(_ left: Int, _ right: Int) throws -> Int { try checkedCents(left - right) }

  static func sum<S: Sequence>(_ values: S) throws -> Int where S.Element == Int {
    var total = 0
    for value in values { total = try add(total, value) }
    return total
  }

  /// `value * numerator / denominator` with explicit rounding, without intermediate overflow.
  static func mulDivRound(_ value: Int, _ numerator: Double, _ denominator: Double, _ mode: RoundingMode) throws -> Int {
    _ = try checkedCents(value)
    guard PrismJS.isSafeInteger(numerator), PrismJS.isSafeInteger(denominator) else {
      throw PrismDomainError("mulDivRound expects integer numerator and denominator; scale them first.", "INVALID_MONEY_RATIO")
    }
    guard denominator != 0 else { throw PrismDomainError("Cannot divide money by zero.", "INVALID_MONEY_RATIO") }
    var num = Int(numerator), den = Int(denominator)
    if den < 0 { num = -num; den = -den }
    let (quotient, remainder) = try truncatingMulDiv(value, num, den)
    if remainder == 0 { return try checkedCents(quotient) }
    switch mode {
    case .trunc: return try checkedCents(quotient)
    case .floor: return try checkedCents(remainder < 0 ? quotient - 1 : quotient)
    case .ceil: return try checkedCents(remainder > 0 ? quotient + 1 : quotient)
    case .half:
      let magnitude = remainder.magnitude.multipliedFullWidth(by: 2)
      let reachesHalf = magnitude.high > 0 || magnitude.low >= UInt(den)
      if reachesHalf { return try checkedCents(remainder < 0 ? quotient - 1 : quotient + 1) }
      return try checkedCents(quotient)
    }
  }

  /// Largest-remainder split of `total` over non-negative integer weights; parts sum to `total`.
  static func allocate(_ total: Int, _ weights: [Double]) throws -> [Int] {
    _ = try checkedCents(total)
    if weights.isEmpty { return [] }
    for weight in weights where !PrismJS.isSafeInteger(weight) || weight < 0 {
      throw PrismDomainError("allocate expects non-negative integer weights; scale them first.", "INVALID_MONEY_RATIO")
    }
    let ints = weights.map { Int($0) }
    let divisor = ints.reduce(0, +)
    if divisor == 0 { return ints.indices.map { $0 == ints.count - 1 ? total : 0 } }
    var floors: [Int] = [], remainders: [Int] = []
    var allocated = 0
    for weight in ints {
      let (quotient, remainder) = try truncatingMulDiv(total, weight, divisor)
      floors.append(remainder < 0 ? quotient - 1 : quotient)
      remainders.append(remainder < 0 ? remainder + divisor : remainder)
      allocated += floors.last!
    }
    var residual = total - allocated
    let order = remainders.enumerated().sorted { a, b in
      a.element == b.element ? a.offset < b.offset : a.element > b.element
    }.map { $0.offset }
    var result = try floors.map { try checkedCents($0) }
    var cursor = 0
    while residual > 0 {
      let target = order[cursor % order.count]
      result[target] = try checkedCents(result[target] + 1)
      residual -= 1
      cursor += 1
    }
    return result
  }

  /// (a * b) / d truncated toward zero with its remainder, `d > 0`, exact for 128-bit products.
  private static func truncatingMulDiv(_ a: Int, _ b: Int, _ d: Int) throws -> (Int, Int) {
    let negative = (a < 0) != (b < 0)
    let product = a.magnitude.multipliedFullWidth(by: b.magnitude)
    let divisor = UInt(d)
    guard product.high < divisor else { throw PrismDomainError("Cents must be a whole number.", "INVALID_MONEY") }
    let (q, r) = divisor.dividingFullWidth(product)
    guard q <= UInt(Int.max) else { throw PrismDomainError("Cents must be a whole number.", "INVALID_MONEY") }
    let quotient = Int(q), remainder = Int(r)
    return negative ? (-quotient, -remainder) : (quotient, remainder)
  }

  private static func pow10(_ exponent: Int) -> Int {
    var value = 1
    for _ in 0..<exponent { value *= 10 }
    return value
  }

  /// The shortest round-tripping decimal digits of a finite non-negative double
  /// (what `Number#toString` prints) as `digits × 10^exponent`.
  static func shortestDecimal(_ value: Double) -> (digits: Int, exponent: Int) {
    if value == 0 { return (0, 0) }
    let text = value.description // Swift prints the shortest round-trip representation.
    let parts = text.lowercased().split(separator: "e", maxSplits: 1)
    let mantissa = String(parts[0])
    var exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    let pieces = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let whole = String(pieces[0])
    let fraction = pieces.count > 1 ? String(pieces[1]) : ""
    var digitString = whole + fraction
    exponent -= fraction.count
    while digitString.count > 1 && digitString.hasPrefix("0") { digitString.removeFirst() }
    while digitString.count > 1 && digitString.hasSuffix("0") { digitString.removeLast(); exponent += 1 }
    return (Int(digitString) ?? 0, exponent)
  }
}
