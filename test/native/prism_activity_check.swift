import Foundation

@main enum ActivityCheck {
  static func main() throws {
    let legacy = Data(#"{"phase":"active","startedAtUnix":100,"endedAtUnix":null}"#.utf8)
    let oldState = try JSONDecoder().decode(StoreVisitAttributes.ContentState.self, from: legacy)
    precondition(oldState.bill == nil)
    func bill(_ charge: Double?, _ rule: Double?) -> StoreVisitAttributes.Bill {
      .init(amountCents: 1234, planLabel: "标准方案（日间）", nextChargeAtUnix: charge, nextRuleAtUnix: rule, asOfUnix: 100)
    }
    precondition(bill(130, 160).nextEvent?.date.timeIntervalSince1970 == 130)
    precondition(bill(160, 130).nextEvent?.date.timeIntervalSince1970 == 130)
    precondition(bill(130, 130).nextEvent?.title == String(localized: "计费与规则切换"))
    precondition(bill(nil, 160).nextEvent?.date.timeIntervalSince1970 == 160)
    precondition(bill(90, nil).nextEvent == nil)
    precondition(bill(nil, nil).nextEvent == nil)
    let state = StoreVisitAttributes.ContentState(phase: "active", startedAtUnix: 100, endedAtUnix: nil, bill: bill(130, 160))
    let data = try JSONEncoder().encode(state)
    precondition(data.count < 4096)
    let decoded = try JSONDecoder().decode(StoreVisitAttributes.ContentState.self, from: data)
    precondition(decoded == state)
    print("Live Activity countdown and compatibility checks passed")
  }
}
