import Foundation

struct PrismInvocation {
  let origin: URL
  let shopCode: String
  let machinePublicId: String
}

enum InvocationParser {
  static func origin(from url: URL) -> URL? {
    guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil else { return nil }
    var parts = URLComponents(); parts.scheme = "https"; parts.host = host.lowercased(); parts.port = url.port
    return parts.url
  }

  static func invocation(from url: URL) -> PrismInvocation? {
    guard let origin = origin(from: url) else {
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
    return PrismInvocation(origin: origin, shopCode: values[0], machinePublicId: values[1])
  }
}
