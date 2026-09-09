import Foundation

struct ArcadeLinkInvocation {
  let shopCode: String
  let machinePublicId: String
}

enum InvocationParser {
  static let host = "link.neri.moe"

  static func invocation(from url: URL) -> ArcadeLinkInvocation? {
    guard url.scheme?.lowercased() == "https",
          url.host?.lowercased() == host else {
      return nil
    }

    let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count == 3, components[0] == "t" else {
      return nil
    }

    let values = components.dropFirst().map {
      String($0).removingPercentEncoding ?? String($0)
    }
    guard values.allSatisfy({ value in
      !value.isEmpty && value.count <= 80 &&
        value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }) else {
      return nil
    }
    return ArcadeLinkInvocation(shopCode: values[0], machinePublicId: values[1])
  }
}
