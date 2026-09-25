import Foundation

@main enum ActivityCheck {
  static func main() throws {
    let legacy = Data(#"{"phase":"active","startedAtUnix":100,"endedAtUnix":null}"#.utf8)
    let oldState = try JSONDecoder().decode(StoreVisitAttributes.ContentState.self, from: legacy)
    precondition(oldState.bill == nil)
    // Legacy payloads without the aggregate keys decode with nils.
    let legacyBill = try JSONDecoder().decode(StoreVisitAttributes.Bill.self, from: Data(
      #"{"amountCents":600,"planLabel":"","asOfUnix":100}"#.utf8))
    precondition(legacyBill.remainingToCapCents == nil && legacyBill.billable == nil)
    precondition(legacyBill.nextEvent == nil)
    // The wrapped next event survives a round trip; the label is rendered by
    // the backend and passed through, with the generic fallback when absent.
    let richBill = StoreVisitAttributes.Bill(
      amountCents: 600, planLabel: "标准方案（日间）", asOfUnix: 100,
      remainingToCapCents: 0, billable: true,
      nextEvent: .init(atUnix: 160, label: "规则切换"))
    let richData = try JSONEncoder().encode(richBill)
    precondition(richData.count < 4096)
    let richDecoded = try JSONDecoder().decode(StoreVisitAttributes.Bill.self, from: richData)
    precondition(richDecoded == richBill)
    precondition(richDecoded.nextEvent?.title == "规则切换")
    precondition(StoreVisitAttributes.NextEvent(atUnix: 1, label: "下次计费").title == "下次计费")
    precondition(StoreVisitAttributes.NextEvent(atUnix: 1, label: "").title == String(localized: "下一事件"))
    precondition(StoreVisitAttributes.NextEvent(atUnix: 1, label: nil).title == String(localized: "下一事件"))
    let state = StoreVisitAttributes.ContentState(phase: "active", startedAtUnix: 100, endedAtUnix: nil, bill: richBill)
    let data = try JSONEncoder().encode(state)
    precondition(data.count < 4096)
    let decoded = try JSONDecoder().decode(StoreVisitAttributes.ContentState.self, from: data)
    precondition(decoded == state)
    print("Live Activity countdown and compatibility checks passed")
  }
}
