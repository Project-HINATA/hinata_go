import Foundation
import Combine

@MainActor
final class MachineLoginViewModel: ObservableObject {
  enum State: Equatable {
    case idle
    case loadingMachine
    /// Loads public shop information, just as loadingMachine loads the public machine.
    case loadingShop
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
  @Published private(set) var user: PrismUser?
  @Published private(set) var waitingPower = false
  @Published private(set) var checkoutPreview: PrismCheckout?
  /// Whether the bill for this invocation has been read at least once. The page shows "暂无待
  /// 结账单" for an empty preview, so it needs to tell that apart from a bill not yet read.
  @Published private(set) var billLoaded = false
  @Published private(set) var binding: PrismBinding?
  @Published private(set) var doorPassword: PrismDoorPassword?
  @Published private(set) var deviceBusy = false
  @Published private(set) var notice: String?
  /// The receipt from the last successful checkout, shown until the player dismisses it.
  @Published private(set) var settlement: PrismCheckoutResult?
  private var userId = ""
  private var polling: Task<Void, Never>?
  private var sceneActive = true
  private var visitRevision = 0
  var canUseCards: Bool { machine?.has("card") == true && (machine?.capabilities == nil || deviceState?.gate == "ready") && deviceState?.power != "off" }
  /// True when this session came from a bare `/t/{shopCode}` link: the device-free shop
  /// surface (bill, redeem, history, wallet) with no machine behind it.
  @Published private(set) var isShopOnly = false
  var showDeviceControls: Bool {
    guard machine?.capabilities != nil, machine?.empty != true else { return false }
    return deviceState == nil || deviceState?.gate != "ready" || deviceState?.power == "off" || machine?.has("door") == true || machine?.has("mahjong") == true
  }
  var needsQQBinding: Bool {
    isShopOnly ? user != nil && visit?.shop.billingEnabled == true && visit?.membership == nil : deviceState?.gate == "qq"
  }
  var showVisit: Bool { visit?.shop.billingEnabled == true }
  /// Whether the player's own state for this shop has been read. `summary == nil` also means
  /// "not read yet", so the page needs this to tell an empty shop apart from an unread one.
  @Published private(set) var playerStateLoaded = false

  /// Shop-link subtitle: the machine name on a device link, the billing state here.
  var shopBillingState: String {
    guard isShopOnly else { return "" }
    if summary?.activeSession != nil { return String(localized: "计费中") }
    // A shop that does not bill has no session to wait for, so it is answered straight away.
    if visit?.shop.billingEnabled != true { return String(localized: "本店未启用计费") }
    // "未入场" is only claimed once the player's own state has been read; reporting an unread
    // state as "未入场" is what flashed the wrong subtitle before the bill arrived.
    if state == .unauthenticated { return "" }
    guard playerStateLoaded else { return String(localized: "正在加载") }
    return String(localized: "未入场")
  }
  /// A signed-in shop player who may read the bill and settle it. Admission is absent by
  /// design: only a scanned machine ticket proves the player is on site.
  var canUseShopSurface: Bool { isShopOnly && visit?.membership != nil && visit?.shop.billingEnabled == true }
  /// The bill is what the device controls turn into once this player has checked in.
  var shopHasActiveSession: Bool { summary?.activeSession != nil }

  private(set) var api: PrismAPI
  private let passkey = PasskeyAuthenticationService()
  private let munet = MunetAuthenticationService()
  private let location = LocationService()
  private var invocationVersion = 0
  /// The link whose page is on screen. Re-tapping it refreshes in place instead of rebuilding,
  /// which is what used to discard a settlement receipt (a rebuild clears the active session).
  private var currentInvocation: URL?

  /// True when the page in front of the player cannot be used, so the same link should be
  /// re-run rather than merely refreshed.
  private var currentPageUnusable: Bool {
    if case .expired = state { return true }
    if case .failed = state { return true }
    return false
  }

  init(api: PrismAPI = .shared) {
    self.api = api
  }

  /// Runs a link that has already been arbitrated by `InvocationRouter`.
  ///
  /// The arbitration is deliberately not done here: which of two deliveries should win depends
  /// on where each came from, and only the system callback knows that.
  func handleResolvedInvocation(_ url: URL) async {
    if url == currentInvocation {
      // Already showing this link: refresh rather than rebuild, so the receipt and any
      // in-progress sheet survive a replay of the link already on screen.
      if currentPageUnusable {
        await reloadCurrentOrigin()
      } else if ![.loadingMachine, .loadingShop, .loadingCards].contains(state) {
        await refreshVisit(silent: true)
      }
      return
    }
    currentInvocation = url
    let api = self.api
    // A bare shop link and a machine link share the `/t/` prefix; the machine form has one
    // extra path component, so the two are unambiguous.
    if let invocation = InvocationParser.invocation(from: url) {
      self.api = api.atOrigin(invocation.origin)
      await start(shopCode: invocation.shopCode, publicId: invocation.machinePublicId)
      return
    }
    if let shop = InvocationParser.shopInvocation(from: url) {
      self.api = api.atOrigin(shop.origin)
      await startShop(shopCode: shop.shopCode)
      return
    }
    invocationVersion += 1
    shopCode = nil
    publicId = nil
    ticket = nil
    isShopOnly = false
    state = .failed(String(localized: "无效的机台地址"))
    errorMessage = nil
  }

  /// Re-runs the current link, used when the page it produced is no longer usable.
  private func reloadCurrentOrigin() async {
    guard let url = currentInvocation else { return }
    currentInvocation = nil
    await handleResolvedInvocation(url)
  }

  /// Device-free entry point for `/t/{shopCode}`: loads the shop and the signed-in player's
  /// state without ever asking for a machine or a ticket.
  func startShop(shopCode: String) async {
    await start(shopCode: shopCode, publicId: nil)
  }

  func start(shopCode: String, publicId: String?) async {
    let api = self.api
    invocationVersion += 1
    polling?.cancel()
    assets = []; history = []
    visit = nil; deviceState = nil; summary = nil; binding = nil; doorPassword = nil; checkoutPreview = nil; billLoaded = false; notice = nil; settlement = nil; user = nil; waitingPower = false
    let version = invocationVersion
    self.shopCode = shopCode
    self.publicId = publicId
    isShopOnly = publicId == nil
    state = isShopOnly ? .loadingShop : .loadingMachine
    playerStateLoaded = false
    deviceBusy = false
    machine = nil
    cards = []
    activeCardId = nil
    authenticating = nil
    ticket = nil
    errorMessage = nil
    do {
      if let publicId {
        let session = try await api.startMachineSession(shopCode: shopCode, publicId: publicId)
        guard version == invocationVersion else { return }
        ticket = session.ticket
        machine = session.machine
      } else {
        let shop: PrismShopResponse = try await api.request(shopPath())
        guard version == invocationVersion else { return }
        visit = shop
      }
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
    let api = self.api
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
    let api = self.api
    guard state == .unauthenticated, authenticating == nil else { return }
    authenticating = "munet"
    let version = invocationVersion
    errorMessage = nil
    defer { if version == invocationVersion { authenticating = nil } }
    do {
      let code = try await munet.authenticate(origin: api.baseURL)
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
    let api = self.api
    let version = invocationVersion
    guard !deviceBusy, ![.locating, .sending].contains(state) else { return }
    do {
      _ = try await api.requestJSON(path: "/api/v1/auth/logout", body: [:])
      guard version == invocationVersion else { return }
      invocationVersion += 1
      polling?.cancel()
      // A shop link keeps its card across sign-out: the shop is public data, and the player
      // should still see which shop they are dealing with above the sign-in buttons.
      if isShopOnly {
        state = .unauthenticated
      } else {
        state = ticket == nil ? .expired : .unauthenticated
      }
      cards = []
      user = nil; userId = ""; summary = nil; checkoutPreview = nil; billLoaded = false
      playerStateLoaded = false; settlement = nil; binding = nil; doorPassword = nil
      assets = []; history = []; deviceState = nil; notice = nil
      errorMessage = nil
    } catch { guard version == invocationVersion else { return }; errorMessage = String(localized: "退出账号失败，请重试") }
  }

  func reloadCards() async {
    let api = self.api
    let version = invocationVersion
    state = .loadingCards
    errorMessage = nil
    do {
      if !isShopOnly {
        let response = try await api.cards()
        guard version == invocationVersion else { return }
        cards = response.cards.filter { $0.disabledAt == nil }
      }
      if machine?.capabilities != nil || isShopOnly { await refreshVisit() }
      guard version == invocationVersion else { return }
      if state == .loadingCards { state = .ready }
    } catch {
      guard version == invocationVersion else { return }
      let message = friendlyMessage(error)
      state = (error as? PrismAPIError)?.isSessionExpired == true ? .expired : .cardsFailed(message)
    }
  }

  func clearError() { errorMessage = nil }

  func login(card: ArcadeCard) async {
    let api = self.api
    let version = invocationVersion
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
      guard version == invocationVersion, self.ticket == ticket else { return }
      state = .sending
      let result = try await api.loginMachine(MachineLoginRequest(
        cardId: card.id,
        lat: position?.latitude,
        lng: position?.longitude,
        accuracy: position?.accuracy,
        ticket: ticket,
      ))
      guard version == invocationVersion, self.ticket == ticket else { return }
      state = .success
      await refreshVisit()
      if ["failed", "unknown"].contains(result.coin?.status ?? "") { errorMessage = String(localized: "刷卡已完成，投币请求失败，请联系店员。") }
      try? await Task.sleep(nanoseconds: 1_000_000_000)
      if version == invocationVersion, state == .success { state = .ready }
    } catch {
      guard version == invocationVersion, self.ticket == ticket else { return }
      let message = friendlyMessage(error)
      if (error as? PrismAPIError)?.isSessionExpired == true { state = .expired } else { state = .ready }
      activeCardId = nil
      errorMessage = state == .expired ? nil : message
      if ["QQ_BINDING_REQUIRED", "CHECKIN_REQUIRED"].contains((error as? PrismAPIError)?.code ?? "") { await refreshVisit() }
    }
  }

  private func shopPath(_ suffix: String = "") -> String {
    "/api/v1/shops/\(shopCode ?? "")" + (suffix.isEmpty ? "" : "/" + suffix)
  }

  func setSceneActive(_ active: Bool) async {
    guard active != sceneActive else { return }
    sceneActive = active
    if !active {
      // Initial account loading owns the transition to ready, even if authentication or
      // foreground activation briefly makes the scene inactive.
      if state != .loadingCards { visitRevision += 1 }
      polling?.cancel()
      polling = nil
    } else if !deviceBusy, ![.loadingMachine, .loadingShop, .loadingCards, .locating, .sending].contains(state) {
      await refreshVisit(silent: true)
    }
  }

  private func scheduleRefresh() {
    guard sceneActive, ticket != nil || needsQQBinding else { return }
    polling?.cancel()
    polling = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
      guard let self, self.sceneActive, !self.deviceBusy, !Task.isCancelled else { return }
      self.polling = nil
      await self.refreshVisit(silent: true)
    }
  }

  func refreshVisit(silent: Bool = false) async {
    let api = self.api
    // Shop-only mode has no machine, so the machine gate cannot apply there.
    guard sceneActive || state == .loadingCards, machine?.capabilities != nil || isShopOnly,
          state != .unauthenticated else { return }
    visitRevision += 1
    polling?.cancel()
    let revision = visitRevision
    let version = invocationVersion
    do {
      let shop: PrismShopResponse = try await api.request(shopPath())
      let me = try await api.me()
      guard version == invocationVersion, revision == visitRevision else { return }
      // The shop is public data, so the card is settled before the signed-in state is judged.
      // Clearing it here is what made a signed-out shop page lose its card entirely.
      visit = shop
      guard me.user != nil else {
        state = .unauthenticated
        user = nil; summary = nil; checkoutPreview = nil; billLoaded = false; playerStateLoaded = false; assets = []; history = []; settlement = nil
        return
      }
      var currentDevice = deviceState
      if let ticket {
        do { currentDevice = try await api.request("/api/v1/devices/session/state?ticket=\(ticket)") }
        catch {
          guard (error as? PrismAPIError)?.isSessionExpired == true else { throw error }
          expire()
        }
      }
      var currentSummary: PrismSummary?
      if shop.shop.billingEnabled && shop.membership != nil {
        currentSummary = try await api.request(shopPath("player/me"))
      }
      // Publish the shop player's summary and bill together. The inline view never starts
      // another request when it appears or changes height.
      var currentPreview: PrismCheckout?
      if isShopOnly, currentSummary?.activeSession != nil {
        currentPreview = try await api.request(shopPath("player/checkout/preview"), body: [:])
      }
      guard version == invocationVersion, revision == visitRevision else { return }
      playerStateLoaded = true
      if isShopOnly { checkoutPreview = currentPreview; billLoaded = true }
      if userId != me.user!.id { assets = []; history = [] }
      userId = me.user!.id
      deviceState = currentDevice; summary = currentSummary; user = me.user
      if let shopCode = self.shopCode {
        await StoreVisitLiveActivityManager.shared.reconcile(
          session: currentSummary?.activeSession,
          shopCode: shopCode,
          shopName: shop.shop.name ?? machine?.shop.name ?? "PRiSM",
          // Only HTTPS origins can carry a universal link; debug loopback origins are skipped.
          origin: api.baseURL.scheme?.lowercased() == "https" ? api.baseURL : nil
        )
      }
      guard version == invocationVersion, revision == visitRevision else { return }
      if currentDevice?.power != "off" { waitingPower = false }
      if shop.membership != nil { binding = nil }
      polling?.cancel()
      if needsQQBinding, binding.flatMap({ prismParsedDate($0.expiresAt) }) ?? .distantPast <= Date() {
        let value: PrismBinding = try await api.request(shopPath("qq-binding"), body: [:])
        guard version == invocationVersion, revision == visitRevision else { return }
        binding = value
      }
      if needsQQBinding || (ticket != nil && (currentDevice?.power == "off" || machine?.has("mahjong") == true)) {
        scheduleRefresh()
      }
    } catch {
      if version == invocationVersion, revision == visitRevision {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if silent, error is URLError {
          scheduleRefresh()
          return
        }
        if (error as? PrismAPIError)?.code == "AUTHENTICATION_REQUIRED" { state = .unauthenticated }
        errorMessage = friendlyMessage(error)
      }
    }
  }

  private func perform(_ action: () async throws -> Void) async {
    guard !deviceBusy, ![.locating, .sending].contains(state) else { return }
    let version = invocationVersion
    visitRevision += 1
    polling?.cancel()
    deviceBusy = true; errorMessage = nil
    defer { if version == invocationVersion { deviceBusy = false } }
    do { try await action() }
    catch {
      if version == invocationVersion {
        if (error as? PrismAPIError)?.isSessionExpired == true { expire() }
        else if (error as? PrismAPIError)?.code == "COIN_ALREADY_USED" { deviceState?.coinUsed = true }
        else { errorMessage = friendlyMessage(error) }
      }
    }
  }

  func expire() { ticket = nil; state = .expired; activeCardId = nil; polling?.cancel(); errorMessage = nil }
  func pricingDate(_ date: String) async throws -> PrismShopResponse { try await api.request(shopPath() + "?date=" + date) }

  func bindQQ() async {
    let api = self.api
    await perform {
      let version = invocationVersion
      let value: PrismBinding = try await api.request(shopPath("qq-binding"), body: [:])
      guard version == invocationVersion else { return }
      binding = value
      await refreshVisit()
    }
  }

  private func operation(_ key: String, path: String, body: [String: Any], requiresLocation: Bool) async throws -> Data {
    let api = self.api
    let version = invocationVersion
    let storageKey = "prism.operation.\(api.baseURL.absoluteString).\(userId).\(shopCode ?? "").\(key)"
    let legacyKey = "prism.operation.\(userId).\(shopCode ?? "").\(key)"
    if api.baseURL.absoluteString == "https://link.neri.moe", UserDefaults.standard.data(forKey: storageKey) == nil,
       let legacy = UserDefaults.standard.data(forKey: legacyKey) {
      UserDefaults.standard.set(legacy, forKey: storageKey)
      UserDefaults.standard.removeObject(forKey: legacyKey)
    }
    let saved = UserDefaults.standard.data(forKey: storageKey)
    if saved != nil && key.hasPrefix("device.") { throw PrismAPIError.api(code: "OPERATION_PENDING", message: "操作失败，请重新扫码后重试") }
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
      if let error = error as? PrismAPIError, case .http(let status, let code, _) = error, status < 500, code != "OPERATION_PENDING", code != "DEVICE_RESULT_UNKNOWN" {
        UserDefaults.standard.removeObject(forKey: storageKey)
      }
      if key.hasPrefix("device."), error is URLError { throw PrismAPIError.api(code: "DEVICE_RESULT_UNKNOWN", message: "设备连接失败，请重新扫码后重试") }
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
    let requiresLocation = (visit?.shop.locationEnabled ?? visit?.shop.checkinGeo) == true
    // Shop-only mode has no ticket: the server accepts a ticket-free entry when the shop
    // opts in, still requiring consent and (when configured) an on-site fix.
    guard let ticket else {
      guard isShopOnly else { expire(); return }
      await perform {
        _ = try await operation("entry.remote", path: shopPath("player/remote-entry"), body: ["consent": true], requiresLocation: requiresLocation)
        await refreshVisit()
      }
      return
    }
    await perform {
      _ = try await operation("entry.\(ticket)", path: shopPath("player/session/start"), body: ["ticket": ticket, "consent": true], requiresLocation: requiresLocation)
      await refreshVisit()
    }
  }
  func loadAccountSection(_ section: Int) async throws {
    guard !deviceBusy else { return }
    let api = self.api
    let version = invocationVersion
    visitRevision += 1
    polling?.cancel()
    deviceBusy = true
    errorMessage = nil
    defer {
      if version == invocationVersion {
        deviceBusy = false
        if needsQQBinding || deviceState?.power == "off" || machine?.has("mahjong") == true { scheduleRefresh() }
      }
    }
    if section == 0 {
      // The preview is replaced once the read returns, never cleared up front: an empty value
      // is what the page shows as "暂无待结账单", so clearing it first made the bill blank out
      // and then reappear whenever this ran twice in a row.
      let current: PrismSummary = try await api.request(shopPath("player/me"))
      let preview: PrismCheckout? = current.activeSession == nil ? nil : try await api.request(shopPath("player/checkout/preview"), body: [:])
      guard version == invocationVersion, !Task.isCancelled else { throw CancellationError() }
      summary = current; checkoutPreview = preview
      billLoaded = true
    } else if section == 2 {
      let records: PrismHistory = try await api.request(shopPath("player/sessions/history"))
      guard version == invocationVersion, !Task.isCancelled else { throw CancellationError() }
      history = records.sessions
    } else if section == 3 {
      let holdings: PrismAssets = try await api.request(shopPath("player/assets"))
      guard version == invocationVersion, !Task.isCancelled else { throw CancellationError() }
      assets = holdings.holdings
    }
  }

  func previewCheckout() async {
    let api = self.api
    await perform {
      let version = invocationVersion
      let value: PrismCheckout = try await api.request(shopPath("player/checkout/preview"), body: [:])
      guard version == invocationVersion else { return }
      checkoutPreview = value
    }
  }
  func checkout() async {
    await perform {
      let data = try await operation("checkout", path: shopPath("player/checkout/confirm"), body: [:], requiresLocation: (visit?.shop.locationEnabled ?? visit?.shop.checkoutGeo) == true)
      // Keep the receipt before refreshing: the active session disappears on refresh, which
      // is exactly what used to drop the player straight back to the admission view.
      settlement = try? JSONDecoder().decode(PrismCheckoutResult.self, from: data)
      checkoutPreview = nil; notice = String(localized: "结账成功，计费已结束")
      await refreshVisit()
    }
  }
  /// Dismisses the settlement receipt and returns to the normal page.
  func clearSettlement() { settlement = nil }
  func redeem(_ code: String) async {
    await perform {
      _ = try await operation("redeem", path: shopPath("player/redeem"), body: ["code": code], requiresLocation: false)
      notice = String(localized: "兑换成功")
      await refreshVisit()
    }
  }

  private func fail(_ error: Error) {
    let message = friendlyMessage(error)
    state = (error as? PrismAPIError)?.isSessionExpired == true ? .expired : .failed(message)
    errorMessage = nil
  }
  private func friendlyMessage(_ error: Error) -> String {
    if error is URLError { return String(localized: "网络连接失败，请检查网络后重试") }
    if let apiError = error as? PrismAPIError {
      return apiError.errorDescription ?? String(localized: "操作失败，请稍后重试")
    }
    if let locationError = error as? LocationError {
      return locationError.errorDescription ?? String(localized: "定位获取失败")
    }
    return String(localized: "操作失败，请稍后重试")
  }
}
