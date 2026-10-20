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
  @Published private(set) var history: [PrismHistory.Record] = []
  @Published private(set) var historyNextOffset: Int?
  @Published private(set) var user: PrismUser?
  @Published private(set) var waitingPower = false
  @Published private(set) var checkoutPreview: PrismCheckout?
  /// Whether the bill for this invocation has been read at least once. The page shows "暂无待
  /// 结账单" for an empty preview, so it needs to tell that apart from a bill not yet read.
  @Published private(set) var billLoaded = false
  @Published private(set) var binding: PrismBinding?
  @Published private(set) var suggestPasskey = false
  @Published private(set) var addingPasskey = false
  @Published private(set) var doorPassword: PrismDoorPassword?
  /// What the game did with the last swiped card; see `SwipeResult.card`.
  @Published private(set) var cardOutcome = "sent"
  /// A swipe's outcome, shown on its card row for a few seconds without holding the page.
  @Published private(set) var cardFeedback: CardFeedback?
  private var cardFeedbackTask: Task<Void, Never>?
  /// A problem that needs the player: shown as an alert with the server's buttons.
  @Published private(set) var dialogNotice: PrismNotice?
  private var dialogRetry: (() async -> Void)?
  /// An expected outcome of an action, shown for a moment under the control named by
  /// `inlineNoticeAnchor` (coin, power, door, climate, mahjong, entry, checkout, redeem…).
  @Published private(set) var inlineNotice: PrismNotice?
  @Published private(set) var inlineNoticeAnchor = ""
  private var inlineNoticeTask: Task<Void, Never>?
  private var powerWaitTask: Task<Void, Never>?
  /// Something in the shop is watching this device's Home Assistant, so state is pushed.
  private var liveWatching = false
  private var liveSocket: URLSessionWebSocketTask?
  /// A failed live connection is retried no sooner than this, backing off up to a minute.
  private var liveRetryAt = Date.distantPast
  private var liveFailures = 0
  @Published private(set) var deviceBusy = false
  @Published private(set) var notice: String?
  /// The latest settled bill, retained until a new admission supersedes it.
  @Published private(set) var settlement: PrismCheckoutResult?
  @Published private(set) var checkoutCelebrating = false
  private var userId = ""
  private var polling: Task<Void, Never>?
  private var readBackoff = PrismReadBackoff()
  private var metadataReadAt = Date.distantPast
  private var powerPolling: Task<Void, Never>?
  private var powerGeneration = UUID()
  private var powerObserved = false
  private var powerBackoff = PrismReadBackoff()
  private var refreshRunning = false
  private var refreshPending = false
  private var refreshError: String?
  private var sceneActive = true
  private var visitRevision = 0
  var canUseCards: Bool { machine?.has("card") == true && (machine?.capabilities == nil || deviceState?.gate == "ready") && deviceState?.power != "off" }
  /// True when this session came from a bare `/t/{shopCode}` link: the device-free shop
  /// surface (bill, redeem, history, wallet) with no machine behind it.
  @Published private(set) var isShopOnly = false
  var showDeviceControls: Bool {
    guard machine?.capabilities != nil, machine?.empty != true else { return false }
    return deviceState == nil || deviceState?.gate != "ready" || deviceState?.power == "off" || machine?.has("door") == true || machine?.has("mahjong") == true || machine?.has("climate") == true
  }
  var showNoDeviceActions: Bool {
    guard !isShopOnly, let machine else { return false }
    if machine.empty { return true }
    guard let device = deviceState, device.gate == "ready" else { return false }
    if machine.has("door") || machine.has("climate") || (machine.has("power") && device.power == "off") { return false }
    if canUseCards || (device.power != "off" && machine.has("coin") && machine.coinAfterSwipe != true) { return false }
    if machine.has("mahjong"), device.power != "off", let table = device.mahjong,
       table.seats.contains(where: { $0.mine }) || table.seats.count < table.capacity { return false }
    return true
  }
  var needsPlatformBinding: Bool {
    isShopOnly
      ? user != nil && visit?.requiresPlatformBinding(hasActiveSession: shopHasActiveSession) == true
      : deviceState?.gate == "binding"
  }
  var showVisit: Bool { visit?.shop.billingEnabled == true }
  /// Whether the player's own state for this shop has been read. `summary == nil` also means
  /// "not read yet", so the page needs this to tell an empty shop apart from an unread one.
  @Published private(set) var playerStateLoaded = false

  /// Shop-link subtitle: the machine name on a device link, the billing state here.
  var shopBillingState: String {
    guard isShopOnly else { return "" }
    if summary?.activeSession != nil { return String(localized: "计费中") }
    if settlement != nil { return String(localized: "结账成功") }
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
    closeLiveState()
    polling?.cancel(); cancelPowerRead()
    shopCode = nil
    checkoutCelebrating = false; settlement = nil
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
    closeLiveState()
    let version = invocationVersion
    polling?.cancel()
    cancelPowerRead(); powerObserved = false; powerBackoff.succeed(); readBackoff.succeed(); metadataReadAt = .distantPast
    await api.invalidateReads()
    guard version == invocationVersion else { return }
    assets = []; history = []; historyNextOffset = nil
    visit = nil; deviceState = nil; summary = nil; binding = nil; doorPassword = nil; checkoutPreview = nil; billLoaded = false; notice = nil; settlement = nil; checkoutCelebrating = false; user = nil; waitingPower = false
    powerWaitTask?.cancel(); inlineNotice = nil; cardFeedbackTask?.cancel(); cardFeedback = nil
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
    suggestPasskey = false; addingPasskey = false
    ticket = nil
    errorMessage = nil
    do {
      async let identity = api.me()
      if let publicId {
        let session = try await api.startMachineSession(shopCode: shopCode, publicId: publicId)
        guard version == invocationVersion else { return }
        ticket = session.ticket
        machine = session.machine
      } else {
        let shop: PrismShopResponse = try await api.request(shopPath())
        guard version == invocationVersion else { return }
        visit = shop
        metadataReadAt = Date()
      }
      // The public hero is visible while authentication is still loading.
      state = .loadingCards
      let me = try await identity
      guard version == invocationVersion else { return }
      user = me.user
      guard me.user != nil else {
        state = machine?.empty == true ? .ready : .unauthenticated
        return
      }
      userId = me.user!.id
      StoreVisitLiveActivityManager.shared.startPushToStartTracking(api: api)
      await reloadCards(initialIdentity: me.user)
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
      let result = try await munet.authenticate(origin: api.baseURL)
      try await api.exchangeAppClipAuth(code: result.code)
      guard version == invocationVersion else { return }
      suggestPasskey = result.suggestPasskey
      await reloadCards()
    } catch {
      guard version == invocationVersion else { return }
      if !isAuthenticationCancellation(error) {
        errorMessage = friendlyMessage(error)
      }
    }
  }

  func skipPasskeySetup() {
    guard !addingPasskey else { return }
    suggestPasskey = false
    errorMessage = nil
  }

  func addSuggestedPasskey() async {
    guard suggestPasskey, user != nil, !addingPasskey, !deviceBusy else { return }
    let api = self.api
    let version = invocationVersion
    addingPasskey = true; errorMessage = nil
    defer { if version == invocationVersion { addingPasskey = false } }
    do {
      let options = try await api.passkeyRegistrationOptions()
      guard version == invocationVersion else { return }
      let credential = try await passkey.register(options: options)
      guard version == invocationVersion else { return }
      try await api.registerPasskey(credential)
      guard version == invocationVersion else { return }
      suggestPasskey = false
    } catch {
      guard version == invocationVersion else { return }
      if !isAuthenticationCancellation(error) { errorMessage = friendlyMessage(error) }
    }
  }

  func logout() async {
    let api = self.api
    let version = invocationVersion
    guard !deviceBusy, ![.locating, .sending].contains(state) else { return }
    deviceBusy = true
    visitRevision += 1
    polling?.cancel()
    cancelPowerRead()
    defer { deviceBusy = false }
    do {
      // Unregister while authentication is still valid, and await the entire sweep.
      await StoreVisitLiveActivityManager.shared.unregisterAllPushTokens(api: api)
      _ = try await api.requestJSON(path: "/api/v1/auth/logout", body: [:])
      guard version == invocationVersion else { return }
      invocationVersion += 1
    closeLiveState()
      polling?.cancel()
      // A shop link keeps its card across sign-out: the shop is public data, and the player
      // should still see which shop they are dealing with above the sign-in buttons.
      if isShopOnly {
        state = .unauthenticated
      } else {
        state = ticket == nil ? .expired : .unauthenticated
      }
      cards = []
      suggestPasskey = false; addingPasskey = false
      user = nil; userId = ""; summary = nil; checkoutPreview = nil; billLoaded = false
      playerStateLoaded = false; settlement = nil; checkoutCelebrating = false; binding = nil; doorPassword = nil
      assets = []; history = []; historyNextOffset = nil; deviceState = nil; notice = nil
      errorMessage = nil
    } catch { guard version == invocationVersion else { return }; errorMessage = String(localized: "退出账号失败，请重试") }
  }

  func reloadCards(initialIdentity: PrismUser? = nil) async {
    let api = self.api
    let version = invocationVersion
    if state != .loadingCards { state = .loadingCards }
    errorMessage = nil
    do {
      readBackoff.succeed()
      async let context: Void = refreshVisit(silent: true, initialIdentity: initialIdentity)
      if !isShopOnly {
        let response = try await api.cards()
        guard version == invocationVersion else { return }
        cards = response.cards.filter { $0.disabledAt == nil }
      }
      guard version == invocationVersion else { return }
      if state == .loadingCards { state = .ready }
      await context
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
    cardFeedbackTask?.cancel(); cardFeedback = nil
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
      cardOutcome = result.card ?? "sent"
      let notices = result.notices ?? []
      // The card row carries the outcome; only a problem that needs the player interrupts.
      var parts = notices.filter { $0.display == "inline" }.map { CardFeedback.Part(level: $0.level, text: $0.body) }
      if parts.isEmpty {
        parts = [CardFeedback.Part(level: cardOutcome == "failed" ? "error" : cardOutcome == "not_read" ? "warning" : "success", text: rowText(cardOutcome))]
        if result.notices == nil, ["failed", "unknown"].contains(result.coin?.status ?? "") {
          parts.append(CardFeedback.Part(level: "warning", text: String(localized: "投币失败")))
        }
      }
      state = .ready
      showCardFeedback(CardFeedback(cardId: card.id, parts: parts))
      if let dialog = notices.first(where: { $0.display == "dialog" }) { dialogNotice = dialog }
      await refreshVisit()
    } catch {
      guard version == invocationVersion, self.ticket == ticket else { return }
      if let notice = present(error, retry: { [weak self] in await self?.login(card: card) }), notice.display == "inline" {
        state = .ready
        showCardFeedback(CardFeedback(cardId: card.id, parts: [CardFeedback.Part(level: notice.level, text: notice.body)]))
        return
      }
      if state != .expired { state = .ready }
      activeCardId = nil
      if ["PLATFORM_BINDING_REQUIRED", "CHECKIN_REQUIRED"].contains((error as? PrismAPIError)?.code ?? ""),
         (error as? PrismAPIError)?.notice == nil { await refreshVisit() }
    }
  }

  /// For a server that predates notices: the card result alone.
  private func rowText(_ outcome: String) -> String {
    switch outcome {
    case "ok": return String(localized: "登录成功")
    case "failed", "not_read": return String(localized: "登录失败")
    default: return String(localized: "已刷卡")
    }
  }

  private func showCardFeedback(_ feedback: CardFeedback) {
    cardFeedback = feedback
    cardFeedbackTask?.cancel()
    cardFeedbackTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: feedback.level == "success" ? 3_000_000_000 : 5_000_000_000)
      guard !Task.isCancelled else { return }
      self?.cardFeedback = nil
    }
  }

  /// The one place problems reach the player. A server notice decides: run its flow,
  /// interrupt with an alert, or hand it back to be shown inline. Without one (no
  /// network, no location) the local message is shown as before.
  @discardableResult
  func present(_ error: Error, retry: (() async -> Void)? = nil) -> PrismNotice? {
    guard let notice = (error as? PrismAPIError)?.notice ?? localNotice(error) else {
      if (error as? PrismAPIError)?.isSessionExpired == true { expire() } else { errorMessage = friendlyMessage(error) }
      return nil
    }
    switch notice.flow {
    case "expired": expire()
    case "refresh": Task { [weak self] in await self?.refreshVisit() }
    case "signin":
      state = .unauthenticated; user = nil; userId = ""; cards = []; deviceState = nil; cancelPowerRead()
    default: break
    }
    if notice.display == "dialog" {
      dialogRetry = retry
      dialogNotice = notice
    }
    return notice
  }

  /// Problems found on the phone that are part of normal use, worded like the server's.
  private func localNotice(_ error: Error) -> PrismNotice? {
    func inline(_ code: String, _ level: String, _ body: String) -> PrismNotice {
      PrismNotice(code: code, level: level, display: "inline", flow: "none", body: body)
    }
    if case LocationError.unavailable = error { return inline("LOCATION_UNAVAILABLE", "warning", String(localized: "定位获取失败，请重试")) }
    if (error as? PrismAPIError)?.code == "DEVICE_RESULT_UNKNOWN" {
      return inline("DEVICE_RESULT_UNKNOWN", "warning", String(localized: "网络异常，请重试"))
    }
    return nil
  }

  var canRetryNotice: Bool { dialogRetry != nil }

  func dismissNotice(retrying: Bool) {
    let retry = retrying ? dialogRetry : nil
    dialogNotice = nil
    dialogRetry = nil
    if let retry { Task { await retry() } }
  }

  private func showInline(_ notice: PrismNotice, anchor: String) {
    inlineNotice = notice
    inlineNoticeAnchor = anchor
    inlineNoticeTask?.cancel()
    inlineNoticeTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: notice.level == "success" ? 3_000_000_000 : 5_000_000_000)
      guard !Task.isCancelled else { return }
      self?.inlineNotice = nil
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
      cancelPowerRead()
      closeLiveState()
    } else if ![.loadingMachine, .loadingShop, .loadingCards].contains(state) {
      StoreVisitLiveActivityManager.shared.recoverExistingActivities(api: self.api)
      if deviceBusy { refreshPending = true; scheduleRefresh() }
      else { await refreshVisit(silent: true) }
    }
  }

  private func scheduleRefresh() {
    // Binding completion ends binding polling; ordinary bill pages do not poll.
    let needsRead = needsPlatformBinding
      || (ticket != nil && (deviceState == nil || machine?.has("mahjong") == true))
      || (isShopOnly && !playerStateLoaded)
      || readBackoff.failures > 0
    guard sceneActive, !checkoutCelebrating, needsRead,
          ![.unauthenticated, .expired, .completed].contains(state) else { return }
    polling?.cancel()
    let delay = max(3, readBackoff.remaining())
    polling = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: UInt64(min(delay, 3600) * 1_000_000_000)) } catch { return }
      guard let self, self.sceneActive, !Task.isCancelled else { return }
      self.polling = nil
      if self.deviceBusy { self.scheduleRefresh(); return }
      await self.refreshVisit(silent: true, dynamicOnly: true)
    }
  }

  func refreshVisit(silent: Bool = false, dynamicOnly: Bool = false, initialIdentity: PrismUser? = nil) async {
    guard !checkoutCelebrating else { return }
    let api = self.api
    // Shop-only mode has no machine, so the machine gate cannot apply there.
    guard sceneActive || state == .loadingCards, machine?.capabilities != nil || isShopOnly,
          state != .unauthenticated else { return }
    // Foreground/replayed invocations cannot bypass an outage or Retry-After cooldown.
    if silent && readBackoff.remaining() > 0 { scheduleRefresh(); return }
    // Foreground events and manual refreshes share the same serial read loop.
    guard !refreshRunning else { refreshPending = true; return }
    refreshRunning = true
    defer {
      refreshRunning = false
      if refreshPending && sceneActive && !deviceBusy {
        refreshPending = false
        Task { [weak self] in await self?.refreshVisit(silent: true) }
      } else { scheduleRefresh() }
    }
    visitRevision += 1
    polling?.cancel()
    polling = nil
    let revision = visitRevision
    let version = invocationVersion
    do {
      if !silent { await api.invalidateReads(); readBackoff.succeed() }
      var fullRead = !dynamicOnly || visit == nil || Date().timeIntervalSince(metadataReadAt) >= 30
      if dynamicOnly && isShopOnly && needsPlatformBinding {
        struct Status: Decodable { struct Binding: Decodable { let playerId: String }; let bindings: [Binding] }
        let status: Status = try await api.request(shopPath("platform-binding"))
        if !status.bindings.isEmpty { fullRead = true; await api.invalidateReads() }
      }
      var currentDevice = deviceState
      if let ticket {
        do {
          var value: PrismDeviceState = try await api.request("/api/v1/devices/session/state?ticket=\(ticket)&includePower=0")
          guard version == invocationVersion, revision == visitRevision else { return }
          if value.gate != deviceState?.gate {
            fullRead = true
            if deviceState != nil { await api.invalidateReads() }
            guard version == invocationVersion, revision == visitRevision else { return }
            powerObserved = false; cancelPowerRead()
          }
          if machine?.has("power") == true { value.power = deviceState?.gate == value.gate ? (deviceState?.power ?? "unknown") : "unknown" }
          currentDevice = value
          deviceState = value
          schedulePowerRead(force: !dynamicOnly)
        } catch {
          guard (error as? PrismAPIError)?.isSessionExpired == true else { throw error }
          expire(); return
        }
      }
      var shop: PrismShopResponse
      let me: MeResponse
      if fullRead {
        if let initialIdentity {
          shop = try await api.request(shopPath()); me = MeResponse(user: initialIdentity)
        } else {
          async let shopRead: PrismShopResponse = api.request(shopPath())
          async let identityRead = api.me()
          (shop, me) = try await (shopRead, identityRead)
        }
        metadataReadAt = Date()
      } else {
        guard let currentShop = visit else { return }
        shop = currentShop; me = MeResponse(user: user)
      }
      guard version == invocationVersion, revision == visitRevision else { return }
      if fullRead, me.user?.id != userId {
        await api.invalidateReads()
        shop = try await api.request(shopPath())
        guard version == invocationVersion, revision == visitRevision else { return }
        if !userId.isEmpty {
          cards = []; assets = []; history = []; historyNextOffset = nil; checkoutPreview = nil
          billLoaded = false; binding = nil; doorPassword = nil; settlement = nil; summary = nil
          user = me.user; userId = me.user?.id ?? ""
          if !isShopOnly && me.user != nil {
            let currentCards = try await api.cards()
            guard version == invocationVersion, revision == visitRevision else { return }
            cards = currentCards.cards.filter { $0.disabledAt == nil }
          }
        }
      }
      // The shop is public data, so the card is settled before the signed-in state is judged.
      // Clearing it here is what made a signed-out shop page lose its card entirely.
      visit = shop
      guard me.user != nil else {
        state = .unauthenticated
        user = nil; userId = ""; cards = []; summary = nil; checkoutPreview = nil; billLoaded = false; playerStateLoaded = false; assets = []; history = []; historyNextOffset = nil; settlement = nil
        binding = nil; doorPassword = nil; deviceState = nil; cancelPowerRead()
        return
      }
      var currentSummary: PrismSummary? = fullRead ? nil : summary
      if fullRead && shop.shop.billingEnabled && shop.membership != nil {
        currentSummary = try await api.request(shopPath("player/me"))
      }
      // Publish the shop player's summary and bill together. The inline view never starts
      // another request when it appears or changes height.
      var currentPreview: PrismCheckout? = fullRead ? nil : checkoutPreview
      if fullRead, isShopOnly, currentSummary?.activeSession != nil {
        currentPreview = try await api.request(shopPath("player/checkout/preview"), body: [:])
      }
      var latest: PrismCheckoutResult? = fullRead ? nil : settlement
      if fullRead, isShopOnly, shop.membership != nil, shop.shop.billingEnabled, currentSummary?.activeSession == nil {
        let result: PrismLatestCheckout = try await api.request(shopPath("player/checkout/latest"))
        latest = result.receipt
      }
      guard version == invocationVersion, revision == visitRevision else { return }
      playerStateLoaded = true
      if isShopOnly { checkoutPreview = currentPreview; settlement = latest; billLoaded = true }
      if userId != me.user!.id { assets = []; history = []; historyNextOffset = nil }
      userId = me.user!.id
      // Power may have completed while metadata was loading; retain that independent result.
      if var value = currentDevice { value.power = deviceState?.power ?? value.power; deviceState = value }
      summary = currentSummary; user = me.user
      StoreVisitLiveActivityManager.shared.startPushToStartTracking(api: api)
      if let shopCode = self.shopCode {
        await StoreVisitLiveActivityManager.shared.reconcile(
          session: currentSummary?.activeSession,
          shopCode: shopCode,
          shopName: shop.shop.name ?? machine?.shop.name ?? "PRiSM",
          // Only HTTPS origins can carry a universal link; debug loopback origins are skipped.
          origin: api.baseURL.scheme?.lowercased() == "https" ? api.baseURL : nil,
          api: api,
          receipt: latest
        )
      }
      guard version == invocationVersion, revision == visitRevision else { return }
      if !needsPlatformBinding { binding = nil }
      polling?.cancel()
      if needsPlatformBinding, binding.flatMap({ prismParsedDate($0.expiresAt) }) ?? .distantPast <= Date() {
        binding = nil
        let value: PrismBinding = try await api.request(shopPath("platform-binding"), body: [:])
        guard version == invocationVersion, revision == visitRevision else { return }
        binding = value
      }
      if errorMessage == refreshError { errorMessage = nil }
      refreshError = nil
      readBackoff.succeed()
    } catch {
      if version == invocationVersion, revision == visitRevision {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        readBackoff.fail(retryAfter: (error as? PrismAPIError)?.retryAfter)
        if silent, error is URLError || (error as? PrismAPIError)?.isTransientReadFailure == true { return }
        if (error as? PrismAPIError)?.code == "AUTHENTICATION_REQUIRED" {
          state = .unauthenticated; user = nil; userId = ""; cards = []; deviceState = nil
          summary = nil; binding = nil; checkoutPreview = nil; settlement = nil; assets = []; history = []
          playerStateLoaded = false; billLoaded = false; cancelPowerRead(); await api.invalidateReads()
        }
        refreshError = friendlyMessage(error)
        errorMessage = refreshError
      }
    }
  }

  private func cancelPowerRead() {
    powerGeneration = UUID(); powerPolling?.cancel(); powerPolling = nil
  }

  /// Listen for this device's power and air-conditioner state while its page is ready.
  private func openLiveState() {
    guard liveSocket == nil, Date() >= liveRetryAt, sceneActive, deviceState?.gate == "ready", let ticket,
          machine?.has("power") == true || machine?.has("climate") == true,
          let socket = try? api.deviceLiveSocket(ticket: ticket) else { return }
    liveSocket = socket
    socket.resume()
    receiveLive(socket, version: invocationVersion)
  }

  func closeLiveState() {
    liveSocket?.cancel(with: .normalClosure, reason: nil)
    liveSocket = nil
    liveWatching = false
  }

  private func receiveLive(_ socket: URLSessionWebSocketTask, version: Int) {
    socket.receive { [weak self] result in
      Task { @MainActor [weak self] in
        guard let self, self.liveSocket === socket, self.invocationVersion == version else { return }
        guard case .success(let message) = result, case .string(let text) = message,
              let data = text.data(using: .utf8) else {
          // Closed or failed: fall back to polling, and wait before trying again.
          self.liveSocket = nil
          self.liveWatching = false
          self.liveFailures += 1
          self.liveRetryAt = Date().addingTimeInterval(min(60, 5 * pow(2, Double(self.liveFailures - 1))))
          self.schedulePowerRead()
          return
        }
        struct Frame: Decodable { let type: String; let watching: Bool?; let power: String?; let climate: PrismClimate? }
        if let frame = try? JSONDecoder().decode(Frame.self, from: data) {
          if frame.type == "hello" { self.liveFailures = 0 }
          if frame.type == "hello" || frame.type == "watching" { self.liveWatching = frame.watching ?? false }
          if self.liveWatching, let power = frame.power, power == "on" || power == "off" {
            self.deviceState?.power = power
            self.powerObserved = true
            if power == "on" { self.waitingPower = false }
          }
          if self.liveWatching, let climate = frame.climate { self.deviceState?.climate = climate }
          if self.liveWatching { self.cancelPowerRead() } else { self.schedulePowerRead() }
        }
        self.receiveLive(socket, version: version)
      }
    }
  }

  /// HA is an independent observation; only the server's action precondition authorizes use.
  private func schedulePowerRead(force: Bool = false) {
    openLiveState()
    // Pushed state replaces polling while the device is watched and its power is known.
    if liveWatching, ["on", "off"].contains(deviceState?.power ?? "") { return }
    guard machine?.has("power") == true, deviceState?.gate == "ready", let ticket,
          sceneActive, !deviceBusy, ![.locating, .sending].contains(state), powerPolling == nil,
          force || !powerObserved || waitingPower || deviceState?.power == "off" || deviceState?.power == "unknown" else { return }
    let version = invocationVersion, generation = UUID(), api = self.api
    powerGeneration = generation
    powerPolling = Task { [weak self] in
      defer { if self?.powerGeneration == generation { self?.powerPolling = nil } }
      while !Task.isCancelled {
        guard let self, self.invocationVersion == version, self.sceneActive else { return }
        if self.powerBackoff.remaining() > 0 {
          do { try await Task.sleep(nanoseconds: UInt64(min(self.powerBackoff.remaining(), 3600) * 1_000_000_000)) }
          catch { return }
          continue
        }
        do {
          struct Observation: Decodable { let power: String }
          let result: Observation = try await api.request("/api/v1/devices/session/power?ticket=\(ticket)")
          guard !Task.isCancelled, self.invocationVersion == version, self.powerGeneration == generation else { return }
          self.deviceState?.power = result.power; self.powerObserved = true
          if result.power == "on" || result.power == "unmanaged" { self.powerBackoff.succeed(); self.waitingPower = false; return }
          if result.power == "unknown" { self.powerBackoff.fail() } else { self.powerBackoff.succeed() }
        } catch {
          if Task.isCancelled || error is CancellationError { return }
          guard self.invocationVersion == version, self.powerGeneration == generation else { return }
          if (error as? PrismAPIError)?.isSessionExpired == true { self.expire(); return }
          self.deviceState?.power = "unknown"
          self.powerBackoff.fail(retryAfter: (error as? PrismAPIError)?.retryAfter)
        }
        do { try await Task.sleep(nanoseconds: UInt64(min(max(3, self.powerBackoff.remaining()), 3600) * 1_000_000_000)) }
        catch { return }
      }
    }
  }

  /// Runs a player action. Its outcome is shown under the control named by `anchor`; the
  /// page is read again afterwards in the background, so nothing waits on that read.
  private func perform(_ anchor: String, _ action: () async throws -> Void) async {
    guard !deviceBusy, ![.locating, .sending].contains(state) else { return }
    let version = invocationVersion
    visitRevision += 1
    polling?.cancel()
    cancelPowerRead(); powerObserved = false
    deviceBusy = true; errorMessage = nil
    defer {
      if version == invocationVersion {
        deviceBusy = false
        schedulePowerRead()
        if refreshPending && sceneActive {
          refreshPending = false
          Task { [weak self] in await self?.refreshVisit(silent: true) }
        } else { scheduleRefresh() }
      }
    }
    if inlineNoticeAnchor == anchor { inlineNotice = nil }
    do { try await action() }
    catch {
      if version == invocationVersion, let notice = present(error), notice.display == "inline" { showInline(notice, anchor: anchor) }
    }
  }

  func expire() { ticket = nil; state = .expired; activeCardId = nil; polling?.cancel(); cancelPowerRead(); closeLiveState(); errorMessage = nil }
  func pricingDate(_ date: String) async throws -> PrismShopResponse { try await api.request(shopPath() + "?date=" + date) }

  func bindPlatformIdentity() async {
    let api = self.api
    await perform("binding") {
      let version = invocationVersion
      if binding.flatMap({ prismParsedDate($0.expiresAt) }) ?? .distantPast <= Date() {
        let value: PrismBinding = try await api.request(shopPath("platform-binding"), body: [:])
        guard version == invocationVersion else { return }
        binding = value
      }
      await refreshVisit(silent: true)
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
    // An operation whose answer was lost is sent again under the same id: the server replays
    // its result, so a press is never performed twice. A different request (another
    // temperature, say) starts a new operation.
    let saved = UserDefaults.standard.data(forKey: storageKey).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    var payload: [String: Any]
    if let saved, !key.hasPrefix("device.") || NSDictionary(dictionary: saved.filter { $0.key != "operationId" && $0.key != "location" }).isEqual(to: body) {
      payload = saved
    } else {
      payload = body
      payload["operationId"] = UUID().uuidString
    }
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
      if let error = error as? PrismAPIError, let status = error.status, status < 500, error.code != "OPERATION_PENDING", error.code != "DEVICE_RESULT_UNKNOWN" {
        UserDefaults.standard.removeObject(forKey: storageKey)
      }
      if key.hasPrefix("device."), error is URLError { throw PrismAPIError.api(code: "DEVICE_RESULT_UNKNOWN", message: "网络异常，请重试") }
      throw error
    }
  }

  func device(_ action: String, consent: Bool = false) async {
    guard let ticket else { return }
    let anchor = action == "door.open" ? "door" : action.hasPrefix("power.") ? "power" : action.hasPrefix("mahjong.") ? "mahjong" : action
    await perform(anchor) {
      let data = try await operation("device.\(ticket).\(action)", path: "/api/v1/devices/session/actions", body: ["ticket": ticket, "action": action, "consent": consent], requiresLocation: action == "door.open" ? (visit?.shop.locationEnabled ?? visit?.shop.checkinGeo) == true : (machine?.shop.locationEnabled ?? machine?.shop.machineGeo) != false)
      if action == "door.open" { doorPassword = try JSONDecoder().decode(PrismDoorPassword.self, from: data) }
      else if action == "coin" { deviceState?.coinUsed = true }
      else if action == "power.on" { waitForPower() }
      struct Result: Decodable { let notices: [PrismNotice]? }
      if let note = (try? JSONDecoder().decode(Result.self, from: data))?.notices?.first(where: { $0.display == "inline" }) {
        showInline(note, anchor: anchor)
      }
      refreshPending = true
    }
  }

  /// The power button spins until the machine reports on; if it never does, the player
  /// gets the button back with a word instead of a spinner that never ends.
  private func waitForPower() {
    waitingPower = true
    powerWaitTask?.cancel()
    powerWaitTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 30_000_000_000)
      guard let self, !Task.isCancelled, self.waitingPower else { return }
      self.waitingPower = false
      self.showInline(PrismNotice(code: "POWER_NOT_SEEN", level: "warning", display: "inline", flow: "none",
                                  body: String(localized: "未检测到开机，请重试")), anchor: "power")
    }
  }
  /// Send an air conditioner action. Its result carries the entity's state, which is shown
  /// right away; the refresh that follows reads it again.
  func climate(_ action: String, _ extra: [String: Any] = [:]) async {
    guard let ticket else { return }
    await perform("climate") {
      var body: [String: Any] = ["ticket": ticket, "action": action]
      body.merge(extra) { _, new in new }
      let data = try await operation("device.\(ticket).\(action)", path: "/api/v1/devices/session/actions", body: body, requiresLocation: (machine?.shop.locationEnabled ?? machine?.shop.machineGeo) != false)
      struct Result: Decodable { let climate: PrismClimate? }
      if let climate = (try? JSONDecoder().decode(Result.self, from: data))?.climate { deviceState?.climate = climate }
      refreshPending = true
    }
  }
  /// Entry that also opens the door. Both come back in one response, so the entered view
  /// and the code appear together; the code is only returned when entry succeeded.
  func enterAndOpenDoor() async {
    guard let ticket else { expire(); return }
    let requiresLocation = (visit?.shop.locationEnabled ?? visit?.shop.checkinGeo) == true
    await perform("door") {
      let data = try await operation("entry.door.\(ticket)", path: shopPath("player/session/start"), body: ["ticket": ticket, "consent": true, "openDoor": true], requiresLocation: requiresLocation)
      struct Result: Decodable {
        struct Door: Decodable { let temporaryPassword: String?; let expiresAt: String?; let error: Failure?; let notice: PrismNotice? }
        struct Failure: Decodable { let message: String? }
        let door: Door?
      }
      let door = (try? JSONDecoder().decode(Result.self, from: data))?.door
      deviceState?.gate = "ready"
      if let password = door?.temporaryPassword, let expiresAt = door?.expiresAt {
        doorPassword = PrismDoorPassword(temporaryPassword: password, expiresAt: expiresAt)
      } else if let notice = door?.notice, notice.display == "dialog" {
        dialogNotice = notice
      } else {
        showInline(door?.notice ?? PrismNotice(code: "DOOR_CODE_FAILED", level: "warning", display: "inline", flow: "none",
                                               body: String(localized: "开门密码获取失败，请重试")), anchor: "door")
      }
      await refreshVisit(silent: true)
    }
  }

  func enter() async {
    let requiresLocation = (visit?.shop.locationEnabled ?? visit?.shop.checkinGeo) == true
    // Shop-only mode has no ticket: the server accepts a ticket-free entry when the shop
    // opts in, still requiring consent and (when configured) an on-site fix.
    guard let ticket else {
      guard isShopOnly else { expire(); return }
      await perform("entry") {
        _ = try await operation("entry.remote", path: shopPath("player/remote-entry"), body: ["consent": true], requiresLocation: requiresLocation)
        await refreshVisit(silent: true)
      }
      return
    }
    await perform("entry") {
      _ = try await operation("entry.\(ticket)", path: shopPath("player/session/start"), body: ["ticket": ticket, "consent": true], requiresLocation: requiresLocation)
      await refreshVisit(silent: true)
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
        scheduleRefresh()
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
      let records: PrismHistory = try await api.request(shopPath("player/checkouts/history"))
      guard version == invocationVersion, !Task.isCancelled else { throw CancellationError() }
      history = records.records; historyNextOffset = records.nextOffset
    } else if section == 3 {
      let holdings: PrismAssets = try await api.request(shopPath("player/assets"))
      guard version == invocationVersion, !Task.isCancelled else { throw CancellationError() }
      assets = holdings.holdings
    }
  }

  func previewCheckout() async {
    let api = self.api
    await perform("checkout") {
      let version = invocationVersion
      let value: PrismCheckout = try await api.request(shopPath("player/checkout/preview"), body: [:])
      guard version == invocationVersion else { return }
      checkoutPreview = value
    }
  }
  func loadMoreHistory() async {
    guard let offset = historyNextOffset else { return }
    let version = invocationVersion
    await perform("history") {
      let records: PrismHistory = try await api.request(shopPath("player/checkouts/history?offset=\(offset)"))
      guard version == invocationVersion, !Task.isCancelled else { return }
      let existing = Set(history.map(\.id))
      history.append(contentsOf: records.records.filter { !existing.contains($0.id) })
      historyNextOffset = records.nextOffset
    }
  }
  func loadCheckoutReceipt(_ id: String) async throws -> PrismCheckoutResult {
    let version = invocationVersion
    let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))) ?? ""
    let result: PrismLatestCheckout = try await api.request(shopPath("player/checkouts/\(encoded)"))
    guard version == invocationVersion, !Task.isCancelled else { throw CancellationError() }
    guard let receipt = result.receipt else { throw PrismAPIError.invalidResponse }
    return receipt
  }
  func checkout() async {
    guard !checkoutCelebrating else { return }
    let version = invocationVersion
    await perform("checkout") {
      let data = try await operation("checkout", path: shopPath("player/checkout/confirm"), body: [:], requiresLocation: (visit?.shop.locationEnabled ?? visit?.shop.checkoutGeo) == true)
      // Keep the receipt before refreshing: the active session disappears on refresh, which
      // is exactly what used to drop the player straight back to the admission view.
      guard version == invocationVersion else { return }
      let receipt = try JSONDecoder().decode(PrismCheckoutResult.self, from: data)
      settlement = receipt
      if let shopCode {
        await StoreVisitLiveActivityManager.shared.finishCheckout(receipt: receipt, shopCode: shopCode, api: api)
      }
      guard version == invocationVersion else { return }
      checkoutPreview = nil; notice = String(localized: "结账成功，计费已结束")
      summary = nil
      checkoutCelebrating = true
    }
  }
  /// Called after the shared success animation and sheet dismissal.
  func finishCheckout() async {
    guard checkoutCelebrating, let shopCode else { return }
    checkoutCelebrating = false
    invocationVersion += 1
    closeLiveState()
    polling?.cancel()
    currentInvocation = api.baseURL.appendingPathComponent("t").appendingPathComponent(shopCode)
    isShopOnly = true; machine = nil; ticket = nil; publicId = nil; deviceState = nil; cards = []
    state = .ready
    await refreshVisit()
  }
  /// Whether the code was accepted; a rejection is shown under the code field.
  func redeem(_ code: String) async -> Bool {
    var redeemed = false
    await perform("redeem") {
      _ = try await operation("redeem", path: shopPath("player/redeem"), body: ["code": code], requiresLocation: false)
      redeemed = true
      notice = String(localized: "兑换成功")
      await refreshVisit(silent: true)
    }
    return redeemed
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
