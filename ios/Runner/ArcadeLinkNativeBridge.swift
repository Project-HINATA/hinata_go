import Flutter
import Foundation

@MainActor
final class ArcadeLinkNativeBridge {
  static let shared = ArcadeLinkNativeBridge()

  private let munet = MunetAuthenticationService()
  private let passkey = PasskeyAuthenticationService()
  private let location = LocationService()
  private var channel: FlutterMethodChannel?

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "moe.neri.hinatago/arcadelink_native",
      binaryMessenger: messenger,
    )
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor [weak self] in
        guard let self else { return }
        await self.handle(call, result: result)
      }
    }
    self.channel = channel
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    do {
      switch call.method {
      case "authenticateMunet":
        let code = try await munet.authenticate()
        try await ArcadeLinkAPI.shared.exchangeAppClipAuth(code: code)
        result(nil)
      case "authenticatePasskey":
        let options = try await ArcadeLinkAPI.shared.passkeyOptions()
        let assertion = try await passkey.authenticate(options: options)
        try await ArcadeLinkAPI.shared.loginWithPasskey(assertion)
        result(nil)
      case "cards":
        let cards = try await ArcadeLinkAPI.shared.cards().cards
        result(cards.map { card in
          var value: [String: Any] = [
            "id": card.id,
            "label": card.label,
            "accessCode": card.accessCode,
          ]
          if let disabledAt = card.disabledAt {
            value["disabledAt"] = disabledAt
          }
          return value
        })
      case "loginMachine":
        guard let arguments = call.arguments as? [String: Any],
              let cardId = arguments["cardId"] as? String,
              let ticket = arguments["ticket"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "缺少机台登录参数", details: nil))
          return
        }
        let position = try await location.currentLocation()
        channel?.invokeMethod("machineLoginSending", arguments: nil)
        try await ArcadeLinkAPI.shared.loginMachine(MachineLoginRequest(
          cardId: cardId,
          lat: position.latitude,
          lng: position.longitude,
          accuracy: position.accuracy,
          ticket: ticket,
        ))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(
        code: "arcadelink_error",
        message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
        details: nil,
      ))
    }
  }
}
