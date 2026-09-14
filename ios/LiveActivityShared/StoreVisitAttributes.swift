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
}
