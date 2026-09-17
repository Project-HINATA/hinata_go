import Foundation

struct PrismInvocation {
  let origin: URL
  let shopCode: String
  let machinePublicId: String
}

/// A shop link with no machine segment: `/t/{shopCode}`. It opens the device-free shop
/// surface (bill, redeem, history, wallet, and self check-in where the shop allows it),
/// which is what a Live Activity or Dynamic Island tap targets.
struct PrismShopInvocation {
  let origin: URL
  let shopCode: String
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

  /// Matches exactly `/t/{shop}`. The machine form carries one more component, so the two
  /// shapes stay unambiguous on the shared `/t/` prefix.
  static func shopInvocation(from url: URL) -> PrismShopInvocation? {
    guard let origin = origin(from: url) else { return nil }
    let components = url.path.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count == 2, components[0] == "t" else { return nil }
    let shopCode = String(components[1]).removingPercentEncoding ?? String(components[1])
    guard !shopCode.isEmpty, shopCode.count <= 80,
          shopCode.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
      return nil
    }
    return PrismShopInvocation(origin: origin, shopCode: shopCode)
  }
}
