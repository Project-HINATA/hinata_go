import Foundation
import Combine

@MainActor
final class MachineLoginViewModel: ObservableObject {
  enum State: Equatable {
    case idle
    case loadingMachine
    case unauthenticated
    case loadingCards
    case cardsFailed(String)
    case completed
    case expired
    case ready
    case locating
    case sending
    case success
    case failed(String)
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var machine: PublicMachine?
  @Published private(set) var cards: [ArcadeCard] = []
  @Published private(set) var errorMessage: String?
  @Published private(set) var ticket: String?
  @Published private(set) var shopCode: String?
  @Published private(set) var publicId: String?

  @Published private(set) var activeCardId: String?
  @Published private(set) var authenticating: String?

  @Published private(set) var visit: PrismShopResponse?
  @Published private(set) var deviceState: PrismDeviceState?
  @Published private(set) var summary: PrismSummary?
  @Published private(set) var assets: [PrismAssets.Holding] = []
  @Published private(set) var history: [PrismHistory.Session] = []
  @Published private(set) var user: ArcadeLinkUser?
  @Published private(set) var waitingPower = false
  @Published private(set) var checkoutPreview: PrismCheckout?
  @Published private(set) var binding: PrismBinding?
  @Published private(set) var doorPassword: PrismDoorPassword?
  @Published private(set) var deviceBusy = false
  @Published private(set) var notice: String?
  private var userId = ""
  private var polling: Task<Void, Never>?
  private var visitRevision = 0
  var canUseCards: Bool { machine?.has("card") == true && (machine?.capabilities == nil || deviceState?.gate == "ready") && deviceState?.power != "off" }
  var showDeviceControls: Bool {
    guard machine?.capabilities != nil, machine?.empty != true else { return false }
    return deviceState == nil || deviceState?.gate != "ready" || deviceState?.power == "off" || machine?.has("door") == true || machine?.has("mahjong") == true
  }
  var showVisit: Bool { visit?.shop.billingEnabled == true }

  let api: ArcadeLinkAPI
  private let passkey = PasskeyAuthenticationService()
  private let munet = MunetAuthenticationService()
  private let location = LocationService()
  private var invocationVersion = 0

  init(api: ArcadeLinkAPI = .shared) {
    self.api = api
  }

  func handleInvocation(_ url: URL) async {
    guard let invocation = InvocationParser.invocation(from: url) else {
      invocationVersion += 1
      shopCode = nil
      publicId = nil
      ticket = nil
      state = .failed(String(localized: "无效的机台地址"))
      errorMessage = nil
      return
    }
    await start(shopCode: invocation.shopCode, publicId: invocation.machinePublicId)
  }

  func start(shopCode: String, publicId: String) async {
    invocationVersion += 1
    polling?.cancel()
    visit = nil; deviceState = nil; summary = nil; binding = nil; doorPassword = nil; checkoutPreview = nil; notice = nil; user = nil; waitingPower = false
    let version = invocationVersion
    self.shopCode = shopCode
    self.publicId = publicId
    state = .loadingMachine
    machine = nil
    cards = []
    activeCardId = nil
    authenticating = nil
    ticket = nil
    errorMessage = nil
    do {
      let session = try await api.startMachineSession(shopCode: shopCode, publicId: publicId)
      guard version == invocationVersion else { return }
      ticket = session.ticket
      machine = session.machine
      let me = try await api.me()
      guard version == invocationVersion else { return }
      user = me.user
      guard me.user != nil else {
        state = machine?.empty == true ? .ready : .unauthenticated
        return
      }
      userId = me.user!.id
      await reloadCards()
    } catch {
      guard version == invocationVersion else { return }
      fail(error)
    }
  }

  func authenticateWithPasskey() async {
    guard state == .unauthenticated, authenticating == nil else { return }
    authenticating = "passkey"
    let version = invocationVersion
    errorMessage = nil
    defer { if version == invocationVersion { authenticating = nil } }
    do {
      let options = try await api.passkeyOptions()
      let assertion = try await passkey.authenticate(options: options)
      try await api.loginWithPasskey(assertion)
      guard version == invocationVersion else { return }
      await reloadCards()
    } catch {
      guard version == invocationVersion else { return }
      if !isAuthenticationCancellation(error) {
        errorMessage = friendlyMessage(error)
      }
    }
  }

  func authenticateWithMunet() async {
    guard state == .unauthenticated, authenticating == nil else { return }
    authenticating = "munet"
    let version = invocationVersion
    errorMessage = nil
    defer { if version == invocationVersion { authenticating = nil } }
    do {
      let code = try await munet.authenticate()
      try await api.exchangeAppClipAuth(code: code)
      guard version == invocationVersion else { return }
      await reloadCards()
    } catch {
      guard version == invocationVersion else { return }
      if !isAuthenticationCancellation(error) {
        errorMessage = friendlyMessage(error)
      }
    }
  }

  func logout() async {
    guard !deviceBusy, ![.locating, .sending].contains(state) else { return }
    do {
      _ = try await api.requestJSON(path: "/api/v1/auth/logout", body: [:])
      invocationVersion += 1
      polling?.cancel()
      visit = nil; binding = nil; summary = nil; doorPassword = nil; checkoutPreview = nil; deviceState = nil; notice = nil; assets = []; history = []; userId = ""; user = nil
      state = ticket == nil ? .expired : .unauthenticated
      cards = []
      errorMessage = nil
    } catch { errorMessage = String(localized: "退出账号失败，请重试") }
  }

  func reloadCards() async {
    let version = invocationVersion
    state = .loadingCards
    errorMessage = nil
    do {
      let response = try await api.cards()
      guard version == invocationVersion else { return }
      cards = response.cards.filter { $0.disabledAt == nil }
      state = .ready
      if machine?.capabilities != nil { await refreshVisit() }
    } catch {
      guard version == invocationVersion else { return }
      let message = friendlyMessage(error)
      state = (error as? ArcadeLinkAPIError)?.isSessionExpired == true ? .expired : .cardsFailed(message)
    }
  }

  func clearError() { errorMessage = nil }

  func login(card: ArcadeCard) async {
    guard state == .ready, !deviceBusy, canUseCards else { return }
    guard let ticket else {
      state = .expired
      errorMessage = nil
      return
    }
    activeCardId = card.id
    state = .locating
    errorMessage = nil
    do {
      let position: LocationSample? = (machine?.shop.locationEnabled ?? machine?.shop.machineGeo) == false ? nil : try await location.currentLocation()
      guard self.ticket == ticket else { return }
      state = .sending
      _ = try await api.loginMachine(MachineLoginRequest(
        cardId: card.id,
        lat: position?.latitude,
        lng: position?.longitude,
        accuracy: position?.accuracy,
        ticket: ticket,
      ))
      guard self.ticket == ticket else { return }
      try? await Task.sleep(for: .seconds(3))
      guard self.ticket == ticket else { return }
      expire()
    } catch {
      guard self.ticket == ticket else { return }
      let message = friendlyMessage(error)
      if ["DEVICE_RESULT_UNKNOWN", "DEVICE_UNAVAILABLE", "OPERATION_PENDING"].contains((error as? ArcadeLinkAPIError)?.code ?? "") || error is URLError { expire(); return }
      if (error as? ArcadeLinkAPIError)?.isSessionExpired == true { state = .expired } else { state = .ready }
      activeCardId = nil
      errorMessage = state == .expired ? nil : message
      if ["QQ_BINDING_REQUIRED", "CHECKIN_REQUIRED"].contains((error as? ArcadeLinkAPIError)?.code ?? "") { await refreshVisit() }
    }
  }

  private func shopPath(_ suffix: String = "") -> String {
    "/api/v1/shops/\(shopCode ?? "")" + (suffix.isEmpty ? "" : "/" + suffix)
  }

  func refreshVisit() async {
    guard machine?.capabilities != nil, state != .unauthenticated else { return }
    visitRevision += 1
    polling?.cancel()
    let revision = visitRevision
    let version = invocationVersion
    do {
      let shop: PrismShopResponse = try await api.request(shopPath())
      let me = try await api.me()
      guard version == invocationVersion, revision == visitRevision else { return }
      guard me.user != nil else { state = .unauthenticated; return }
      var currentDevice = deviceState
      if let ticket {
        do { currentDevice = try await api.request("/api/v1/devices/session/state?ticket=\(ticket)") }
        catch {
          guard (error as? ArcadeLinkAPIError)?.isSessionExpired == true else { throw error }
          expire()
        }
      }
      var currentSummary: PrismSummary?
      var currentAssets: [PrismAssets.Holding] = []
      var currentHistory: [PrismHistory.Session] = []
      if shop.shop.billingEnabled && shop.membership != nil {
        currentSummary = try await api.request(shopPath("player/me"))
        let holdings: PrismAssets = try await api.request(shopPath("player/assets")); currentAssets = holdings.holdings
        let records: PrismHistory = try await api.request(shopPath("player/sessions/history")); currentHistory = records.sessions
      }
      guard version == invocationVersion, revision == visitRevision else { return }
      userId = me.user!.id
      visit = shop; deviceState = currentDevice; summary = currentSummary; assets = currentAssets; history = currentHistory; user = me.user
      if currentDevice?.power != "off" { waitingPower = false }
      if shop.membership != nil { binding = nil }
      polling?.cancel()
      if ticket != nil, currentDevice?.gate == "qq", binding == nil || (binding.flatMap { value -> Date? in let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.date(from: value.expiresAt) ?? ISO8601DateFormatter().date(from: value.expiresAt) } ?? .distantPast) <= Date() {
        let value: PrismBinding = try await api.request(shopPath("qq-binding"), body: [:])
        guard version == invocationVersion, revision == visitRevision else { return }
        binding = value
      }
      if ticket != nil, currentDevice?.gate == "qq" || currentDevice?.power == "off" || machine?.has("mahjong") == true {
        polling = Task { [weak self] in
          do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
          guard let self, !self.deviceBusy, !Task.isCancelled else { return }
          await self.refreshVisit()
        }
      }
    } catch {
      if version == invocationVersion, revision == visitRevision {
        if (error as? ArcadeLinkAPIError)?.code == "AUTHENTICATION_REQUIRED" { state = .unauthenticated }
        errorMessage = friendlyMessage(error)
      }
    }
  }

  private func perform(_ action: () async throws -> Void) async {
    guard !deviceBusy, ![.locating, .sending, .success].contains(state) else { return }
    let version = invocationVersion
    visitRevision += 1
    polling?.cancel()
    deviceBusy = true; errorMessage = nil
    defer { if version == invocationVersion { deviceBusy = false } }
    do { try await action() }
    catch {
      if version == invocationVersion {
        if (error as? ArcadeLinkAPIError)?.isSessionExpired == true || ["DEVICE_RESULT_UNKNOWN", "OPERATION_PENDING"].contains((error as? ArcadeLinkAPIError)?.code ?? "") { expire() }
        else if (error as? ArcadeLinkAPIError)?.code == "COIN_ALREADY_USED" { deviceState?.coinUsed = true }
        else { errorMessage = friendlyMessage(error) }
      }
    }
  }

  func expire() { ticket = nil; state = .expired; activeCardId = nil; polling?.cancel(); errorMessage = nil }
  func pricingDate(_ date: String) async throws -> PrismShopResponse { try await api.request(shopPath() + "?date=" + date) }

  func bindQQ() async {
    await perform {
      let version = invocationVersion
      let value: PrismBinding = try await api.request(shopPath("qq-binding"), body: [:])
      guard version == invocationVersion else { return }
      binding = value
      await refreshVisit()
    }
  }

  private func operation(_ key: String, path: String, body: [String: Any], requiresLocation: Bool) async throws -> Data {
    let version = invocationVersion
    let storageKey = "prism.operation.\(userId).\(shopCode ?? "").\(key)"
    let saved = UserDefaults.standard.data(forKey: storageKey)
    if saved != nil && key.hasPrefix("device.") { throw ArcadeLinkAPIError.api(code: "OPERATION_PENDING", message: "本次会话已失效") }
    var payload = saved == nil ? body : try JSONSerialization.jsonObject(with: saved!) as! [String: Any]
    if saved == nil { payload["operationId"] = UUID().uuidString }
    if requiresLocation {
      let sample = try await location.currentLocation()
      payload["location"] = ["lat": sample.latitude, "lng": sample.longitude, "accuracy": sample.accuracy]
    }
    guard version == invocationVersion else { throw CancellationError() }
    UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: payload), forKey: storageKey)
    do {
      let data = try await api.requestJSON(path: path, body: payload)
      UserDefaults.standard.removeObject(forKey: storageKey)
      guard version == invocationVersion else { throw CancellationError() }
      return data
    } catch {
      if let error = error as? ArcadeLinkAPIError, case .http(let status, let code, _) = error, status < 500, code != "OPERATION_PENDING", code != "DEVICE_RESULT_UNKNOWN" {
        UserDefaults.standard.removeObject(forKey: storageKey)
      }
      if key.hasPrefix("device."), error is URLError { throw ArcadeLinkAPIError.api(code: "DEVICE_RESULT_UNKNOWN", message: "本次会话已失效") }
      throw error
    }
  }

  func device(_ action: String, consent: Bool = false) async {
    guard let ticket else { return }
    await perform {
      let data = try await operation("device.\(ticket).\(action)", path: "/api/v1/devices/session/actions", body: ["ticket": ticket, "action": action, "consent": consent], requiresLocation: action == "door.open" ? (visit?.shop.locationEnabled ?? visit?.shop.checkinGeo) == true : (machine?.shop.locationEnabled ?? machine?.shop.machineGeo) != false)
      if action == "door.open" { doorPassword = try JSONDecoder().decode(PrismDoorPassword.self, from: data) }
      else if action == "coin" { deviceState?.coinUsed = true }
      else if action == "power.on" { waitingPower = true }
      await refreshVisit()
    }
  }
  func enter() async {
    guard let ticket else { expire(); return }
    await perform {
      _ = try await operation("entry.\(ticket)", path: shopPath("player/session/start"), body: ["ticket": ticket, "consent": true], requiresLocation: (visit?.shop.locationEnabled ?? visit?.shop.checkinGeo) == true)
      await refreshVisit()
    }
  }
  func previewCheckout() async {
    await perform {
      let version = invocationVersion
      let value: PrismCheckout = try await api.request(shopPath("player/checkout/preview"), body: [:])
      guard version == invocationVersion else { return }
      checkoutPreview = value
    }
  }
  func checkout() async {
    await perform {
      _ = try await operation("checkout", path: shopPath("player/checkout/confirm"), body: [:], requiresLocation: (visit?.shop.locationEnabled ?? visit?.shop.checkoutGeo) == true)
      checkoutPreview = nil; notice = String(localized: "结账成功，计费已结束")
      await refreshVisit()
    }
  }
  func redeem(_ code: String) async {
    await perform {
      _ = try await operation("redeem", path: shopPath("player/redeem"), body: ["code": code], requiresLocation: false)
      notice = String(localized: "兑换成功")
      await refreshVisit()
    }
  }

  private func fail(_ error: Error) {
    let message = friendlyMessage(error)
    state = (error as? ArcadeLinkAPIError)?.isSessionExpired == true ? .expired : .failed(message)
    errorMessage = nil
  }
  private func friendlyMessage(_ error: Error) -> String {
    if error is URLError { return String(localized: "网络连接失败，请检查网络后重试") }
    if let apiError = error as? ArcadeLinkAPIError {
      return apiError.errorDescription ?? String(localized: "操作失败，请稍后重试")
    }
    if let locationError = error as? LocationError {
      return locationError.errorDescription ?? String(localized: "定位获取失败")
    }
    return String(localized: "操作失败，请稍后重试")
  }
}
