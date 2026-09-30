import Foundation
import SwiftUI

@main enum ActivityCheck {
  static func main() throws {
    let legacy = Data(#"{"phase":"active","startedAtUnix":100,"endedAtUnix":null}"#.utf8)
    let oldState = try JSONDecoder().decode(StoreVisitAttributes.ContentState.self, from: legacy)
    precondition(oldState.bill == nil)
    // Legacy payloads without the aggregate keys decode with nils.
    let legacyBill = try JSONDecoder().decode(StoreVisitAttributes.Bill.self, from: Data(
      #"{"amountCents":600,"planLabel":"","asOfUnix":100}"#.utf8))
    precondition(legacyBill.remainingToCapCents == nil && legacyBill.billable == nil)
    precondition(legacyBill.nextEvent == nil && legacyBill.previousEvent == nil)
    let entry = Date(timeIntervalSince1970: 50)
    let now = Date(timeIntervalSince1970: 120)
    // A snapshot/update time must never masquerade as the last event.
    precondition(legacyBill.eventInterval(startedAt: entry, now: now) == nil)
    // The wrapped next event survives a round trip; the label is rendered by
    // the backend and passed through, with the generic fallback when absent.
    let richBill = StoreVisitAttributes.Bill(
      amountCents: 600, planLabel: "标准方案（日间）", asOfUnix: 100,
      remainingToCapCents: 0, billable: true,
      nextEvent: .init(atUnix: 160, label: "规则切换"),
      previousEvent: .init(atUnix: 100))
    let richData = try JSONEncoder().encode(richBill)
    precondition(richData.count < 4096)
    let richDecoded = try JSONDecoder().decode(StoreVisitAttributes.Bill.self, from: richData)
    precondition(richDecoded == richBill)
    precondition(richDecoded.nextEvent?.title == "规则切换")
    precondition(StoreVisitAttributes.NextEvent(atUnix: 1, label: "下次计费").title == "下次计费")
    precondition(StoreVisitAttributes.NextEvent(atUnix: 1, label: "").title == String(localized: "下一事件"))
    precondition(StoreVisitAttributes.NextEvent(atUnix: 1, label: nil).title == String(localized: "下一事件"))
    precondition(richDecoded.previousEvent?.atUnix == 100)
    precondition(richDecoded.eventInterval(startedAt: entry, now: now) ==
      Date(timeIntervalSince1970: 100)...Date(timeIntervalSince1970: 160))
    var invalid = richBill
    invalid.previousEvent = .init(atUnix: 49)
    precondition(invalid.eventInterval(startedAt: entry, now: now) == nil)
    invalid.previousEvent = .init(atUnix: 130)
    precondition(invalid.eventInterval(startedAt: entry, now: now) == nil)
    invalid.previousEvent = .init(atUnix: .nan)
    precondition(invalid.eventInterval(startedAt: entry, now: now) == nil)
    invalid = richBill
    invalid.nextEvent = .init(atUnix: 100)
    precondition(invalid.eventInterval(startedAt: entry, now: now) == nil)
    precondition(richBill.eventInterval(startedAt: entry, now: Date(timeIntervalSince1970: 160)) == nil)
    // Refreshing the bill leaves the interval unchanged.
    invalid = richBill
    invalid = .init(amountCents: invalid.amountCents, planLabel: "", asOfUnix: 119,
      nextEvent: invalid.nextEvent, previousEvent: invalid.previousEvent)
    precondition(invalid.eventInterval(startedAt: entry, now: now) == richBill.eventInterval(startedAt: entry, now: now))
    if #available(macOS 15.0, *) {
      let end = Date(timeIntervalSince1970: 1000)
      // Only system format types can be decoded by the remote widget renderer.
      let format = SystemFormatStyle.Timer(
        countingDownIn: entry..<end, showsHours: false, maxFieldCount: 1,
        maxPrecision: .seconds(1)).locale(Locale(identifier: "zh_Hans"))
      precondition(String(format.format(end.addingTimeInterval(-120)).characters).contains("2"))
      precondition(String(format.format(end.addingTimeInterval(-5)).characters).contains("秒"))
      precondition(format.format(end.addingTimeInterval(10)) == format.format(end))
    }
    let state = StoreVisitAttributes.ContentState(phase: "active", startedAtUnix: 100, endedAtUnix: nil, bill: richBill)
    let data = try JSONEncoder().encode(state)
    precondition(data.count < 4096)
    let decoded = try JSONDecoder().decode(StoreVisitAttributes.ContentState.self, from: data)
    precondition(decoded == state)
    print("Live Activity countdown and compatibility checks passed")
  }
}
