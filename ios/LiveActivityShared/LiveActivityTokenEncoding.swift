import Foundation

extension Data {
  var liveActivityHexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
