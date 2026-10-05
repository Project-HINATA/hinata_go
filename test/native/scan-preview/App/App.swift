import SwiftUI

@main @MainActor struct ScanPreviewApp: App {
  @StateObject private var model: MachineLoginViewModel
  init() {
    let authHeld = ProcessInfo.processInfo.arguments.contains("auth-held")
    FixtureProtocol.holdNextIdentityResponse = authHeld
    FixtureProtocol.holdNextPowerResponse = !authHeld
    FixtureProtocol.handler = { request in
      func ok(_ data: [String: Any]) -> (Int, [String: Any]) { (200, ["data": data]) }
      switch request.url!.path {
      case "/api/v1/me": return ok(["user": ["id": "u", "username": "test", "displayName": "测试玩家"]])
      case "/api/v1/machines/session/start":
        return ok(["ticket": "v1.opaque-ticket", "expiresIn": 300, "machine": ["publicId": "device", "name": "测试机台", "capabilities": ["card": true, "power": true, "mahjong": true], "shop": ["name": "测试店铺", "latitude": 35, "longitude": 139, "radiusMeters": 80, "machineGeo": false, "billingEnabled": false]]])
      case "/api/v1/cards": return ok(["cards": [["id": "card", "label": "测试 Aime", "accessCode": "01234567890123456789"]]])
      case "/api/v1/devices/session/state": return ok(["gate": "ready", "power": "unmanaged", "mahjong": ["capacity": 4, "seats": []]])
      case "/api/v1/devices/session/power": return ok(["power": "on"])
      case "/api/v1/shops/store": return ok(["shop": ["name": "测试店铺", "billingEnabled": false], "membership": NSNull(), "entryPricing": []])
      default: return (404, ["error": ["code": "UNEXPECTED", "message": "Unexpected preview request"]])
      }
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixtureProtocol.self]
    _model = StateObject(wrappedValue: MachineLoginViewModel(api: PrismAPI(configuration: configuration)))
  }
  var body: some Scene {
    WindowGroup {
      MachineLoginView(presentsAppClipNotice: true).environmentObject(model)
        .task { await model.handleResolvedInvocation(URL(string: "https://link.neri.moe/t/store/device")!) }
    }
  }
}
