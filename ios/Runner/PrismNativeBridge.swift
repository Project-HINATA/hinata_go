import Flutter
import Foundation

@MainActor
final class PrismNativeBridge {
  static let shared = PrismNativeBridge()

  private let munet = MunetAuthenticationService()
  private let passkey = PasskeyAuthenticationService()
  private let location = LocationService()
  private var channel: FlutterMethodChannel?

  private init() {}

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "moe.neri.hinatago/prism_native",
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
        try await PrismAPI.shared.exchangeAppClipAuth(code: code)
        result(nil)
      case "authenticatePasskey":
        let options = try await PrismAPI.shared.passkeyOptions()
        let assertion = try await passkey.authenticate(options: options)
        try await PrismAPI.shared.loginWithPasskey(assertion)
        result(nil)
      case "cards":
        let cards = try await PrismAPI.shared.cards().cards
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
      case "request":
        guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else { throw PrismAPIError.invalidURL }
        var body: [String: Any]? = nil
        if let raw = arguments["body"] as? String { body = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] }
        if arguments["requireLocation"] as? Bool == true {
          guard body != nil else { throw PrismAPIError.invalidResponse }
          let position = try await location.currentLocation()
          body?["location"] = ["lat": position.latitude, "lng": position.longitude, "accuracy": position.accuracy]
        }
        let data = try await PrismAPI.shared.requestJSON(path: path, body: body)
        result(String(data: data, encoding: .utf8))
      case "loginMachine":
        guard let arguments = call.arguments as? [String: Any],
              let cardId = arguments["cardId"] as? String,
              let ticket = arguments["ticket"] as? String else {
          result(FlutterError(code: "invalid_arguments", message: "缺少机台登录参数", details: nil))
          return
        }
        let position: LocationSample? = arguments["requireLocation"] as? Bool == false ? nil : try await location.currentLocation()
        channel?.invokeMethod("machineLoginSending", arguments: nil)
        let response = try await PrismAPI.shared.loginMachine(MachineLoginRequest(
          cardId: cardId,
          lat: position?.latitude,
          lng: position?.longitude,
          accuracy: position?.accuracy,
          ticket: ticket,
        ))
        result(String(data: try JSONEncoder().encode(response), encoding: .utf8))
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      var details: [String: Any]? = nil
      var code = isAuthenticationCancellation(error) ? "authentication_cancelled" : "prism_error"
      var message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      if let apiError = error as? PrismAPIError, case .server(let rawMessage) = apiError {
        // Flutter applies its own app language, which may differ from iOS.
        message = rawMessage
        if apiError.isSessionExpired { code = "session_expired" }
        if rawMessage == "请先登录" { code = "authentication_required" }
      }
      if let apiError = error as? PrismAPIError, case .api(let apiCode, let rawMessage) = apiError {
        code = apiCode
        message = rawMessage
        if apiError.isSessionExpired { code = "session_expired" }
        if apiCode == "AUTHENTICATION_REQUIRED" { code = "authentication_required" }
      }
      if let apiError = error as? PrismAPIError, case .http(let status, let apiCode, let rawMessage) = apiError {
        code = apiCode; message = rawMessage; details = ["statusCode": status]
      }
      if let locationError = error as? LocationError {
        switch locationError {
        case .denied: code = "location_denied"
        case .unavailable: code = "location_unavailable"
        }
      }
      if error is URLError { code = "network_error" }
      result(FlutterError(
        code: code,
        message: message,
        details: details,
      ))
    }
  }
}
