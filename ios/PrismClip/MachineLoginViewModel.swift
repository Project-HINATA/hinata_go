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
  /// The page as the platform generated it: the only thing that says what a scanned resource shows.
  @Published private(set) var page: PrismPage?
  /// A door code from the last action, until it expires.
  @Published private(set) var pageCode: PrismPageCode?
  /// The button whose action is running.
  @Published private(set) var pressing: String?
  /// An attempt got no answer and another is under way.
  @Published private(set) var slowNetwork = false
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
  /// A swipe's outcome, shown on its card row for a few seconds without holding the page.
  @Published private(set) var cardFeedback: CardFeedback?
  /// Adding a card at this cabinet's reader: the page opens a short window and waits for the
  /// reader to report the card. A newer attempt or a cancel makes an older one stop waiting.
  enum CardCapture: Equatable { case starting, waiting, done(level: String, message: String) }
  @Published private(set) var cardCapture: CardCapture?
  private var captureRun = 0
  /// The window open on the reader, so giving up can close it: left open, it adds the next card to this player.
  private var openCapture: (id: String, ticket: String)?
  /// While waiting for the reader: asks what became of the card.
  private var askCapture: (() -> Void)?
  var capturing: Bool { cardCapture == .starting || cardCapture == .waiting }
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
  /// Tells the page when to read itself. Replaced in the background when it stops answering its heartbeat.
  private var pageSocket: URLSessionWebSocketTask?
  private var socketHeartbeat: Task<Void, Never>?
  private var socketRetry: Task<Void, Never>?
  private var socketOpenedOnce = false
  private var socketAnswered = false
  private var pongAwaited = false
  private var socketFailures = 0
  private var socketConnectingAt = Date.distantPast
  private var pageReadAt = Date.distantPast
  /// Operation ids of what got no answer, so pressing again cannot do it twice.
  private var unansweredActions: [String: String] = [:]
  @Published private(set) var deviceBusy = false
  @Published private(set) var notice: String?
  /// The latest settled bill, retained until a new admission supersedes it.
  @Published private(set) var settlement: PrismCheckoutResult?
  @Published private(set) var checkoutCelebrating = false
  private var userId = ""
  private var polling: Task<Void, Never>?
  private var readBackoff = PrismReadBackoff()
  private var metadataReadAt = Date.distantPast
  private var refreshRunning = false
  private var refreshPending = false
  private var refreshError: String?
  private var sceneActive = true
  private var visitRevision = 0
  /// True when this session came from a bare `/t/{shopCode}` link: the device-free shop
  /// surface (bill, redeem, history, wallet) with no machine behind it.
  @Published private(set) var isShopOnly = false
  var needsPlatformBinding: Bool {
    isShopOnly
      ? user != nil && visit?.requiresPlatformBinding(hasActiveSession: shopHasActiveSession) == true
      : page?.needsBinding == true
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
    PrismPageReport.shared.onRetry = { [weak self] in self?.slowNetwork = true }
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
    polling?.cancel()
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
    readBackoff.succeed(); metadataReadAt = .distantPast; pageReadAt = .distantPast; socketFailures = 0; socketOpenedOnce = false
    unansweredActions = [:]; slowNetwork = false
    if let publicId { PrismPageReport.shared.start(publicId: publicId) }
    await api.invalidateReads()
    guard version == invocationVersion else { return }
    assets = []; history = []; historyNextOffset = nil
    visit = nil; page = nil; pageCode = nil; pressing = nil; summary = nil; binding = nil; checkoutPreview = nil; billLoaded = false; notice = nil; settlement = nil; checkoutCelebrating = false; user = nil; waitingPower = false
    powerWaitTask?.cancel(); inlineNotice = nil; cardFeedbackTask?.cancel(); cardFeedback = nil
    captureRun += 1; cardCapture = nil
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
        // Nothing to operate and nothing to confirm needs no account; the page says so.
        if machine?.idle == true, let ticket {
          let idle: PrismPage? = try? await api.request("/api/v1/devices/session/page?ticket=\(ticket)")
          guard version == invocationVersion else { return }
          page = idle
          state = .ready
          PrismPageReport.shared.opened()
        } else { state = .unauthenticated }
        return
      }
      userId = me.user!.id
      StoreVisitLiveActivityManager.shared.startPushToStartTracking(api: api)
      await reloadCards(initialIdentity: me.user)
    } catch {
      guard version == invocationVersion else { return }
      PrismPageReport.shared.openFailed()
      slowNetwork = false
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
      playerStateLoaded = false; settlement = nil; checkoutCelebrating = false; binding = nil; pageCode = nil
      assets = []; history = []; historyNextOffset = nil; page = nil; notice = nil
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
    guard state == .ready, !deviceBusy, let block = page?.cards, block.enabled else { return }
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
      let position: LocationSample? = block.needsLocation ? try await location.currentLocation() : nil
      guard version == invocationVersion, self.ticket == ticket else { return }
      state = .sending
      let answer = try await pageAction(block.action, payload: ["cardId": card.id], location: position, ticket: ticket)
      guard version == invocationVersion, self.ticket == ticket else { return }
      // The card row carries the outcome; only a problem that needs the player interrupts.
      let parts = answer.notices.filter { $0.display == "inline" }.map { CardFeedback.Part(level: $0.level, text: $0.body) }
      state = .ready
      if !parts.isEmpty { showCardFeedback(CardFeedback(cardId: card.id, parts: parts)) }
      if let dialog = answer.notices.first(where: { $0.display == "dialog" }) { dialogNotice = dialog }
      // A refused swipe may mean the card is gone.
      if !answer.ok, let response = try? await api.cards(), version == invocationVersion {
        cards = response.cards.filter { $0.disabledAt == nil }
      }
      if refreshPending {
        refreshPending = false
        await refreshVisit(silent: true)
      }
    } catch {
      guard version == invocationVersion, self.ticket == ticket else { return }
      if let notice = present(error, retry: { [weak self] in await self?.login(card: card) }), notice.display == "inline" {
        state = .ready
        showCardFeedback(CardFeedback(cardId: card.id, parts: [CardFeedback.Part(level: notice.level, text: notice.body)]))
        return
      }
      if state != .expired { state = .ready }
      activeCardId = nil
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
      state = .unauthenticated; user = nil; userId = ""; cards = []; page = nil; closeLiveState()
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
      // Nobody may be here now, and a card put down could be anyone's.
      if cardCapture == .waiting {
        dismissCardCapture()
        cardCapture = .done(level: "error", message: String(localized: "离开页面后已取消添加，请重新添加"))
      }
      polling?.cancel()
      polling = nil
      closeLiveState()
      await PrismPageReport.shared.flush(api: api)
    } else if case .failed = state, currentInvocation != nil {
      // A link that failed to open, often on a network not yet back, is opened again on return.
      await reloadCurrentOrigin()
    } else if ![.loadingMachine, .loadingShop, .loadingCards].contains(state) {
      StoreVisitLiveActivityManager.shared.recoverExistingActivities(api: self.api)
      if deviceBusy { refreshPending = true; scheduleRefresh() }
      else { await refreshVisit(silent: true) }
    }
  }

  private func scheduleRefresh() {
    // A scanned page reads itself when told it changed, and once a minute while open in case a push was
    // lost. Binding completion ends a shop link's binding polling; ordinary bill pages do not poll.
    let needsRead = ticket != nil
      || (isShopOnly && needsPlatformBinding)
      || (isShopOnly && !playerStateLoaded)
      || readBackoff.failures > 0
    guard sceneActive, !checkoutCelebrating, needsRead,
          ![.unauthenticated, .expired, .completed].contains(state) else { return }
    polling?.cancel()
    let delay = ticket != nil && readBackoff.failures == 0 ? 60 : max(3, readBackoff.remaining())
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
      // A scanned page's own read says when the rest is worth reading again.
      var fullRead = !dynamicOnly || visit == nil || (ticket == nil && Date().timeIntervalSince(metadataReadAt) >= 30)
      if dynamicOnly && isShopOnly && needsPlatformBinding {
        struct Status: Decodable { struct Binding: Decodable { let playerId: String }; let bindings: [Binding] }
        let status: Status = try await api.request(shopPath("platform-binding"))
        if !status.bindings.isEmpty { fullRead = true; await api.invalidateReads() }
      }
      if let ticket {
        do {
          let value: PrismPage = try await api.request("/api/v1/devices/session/page?ticket=\(ticket)")
          // A read that was under way when the page was restarted belongs to the old ticket and must
          // not publish a page for the new one; one an action answered meanwhile is older than its page.
          guard version == invocationVersion, revision == visitRevision, self.ticket == ticket else { return }
          if let page, value.movedBilling(from: page) {
            fullRead = true
            await api.invalidateReads()
            guard version == invocationVersion, revision == visitRevision else { return }
          }
          pageReadAt = Date()
          slowNetwork = false
          if value.asksToSignIn {
            state = .unauthenticated; user = nil; userId = ""; cards = []; page = nil; closeLiveState()
            return
          }
          show(value)
          PrismPageReport.shared.opened()
          openPageSocket()
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
          billLoaded = false; binding = nil; pageCode = nil; settlement = nil; summary = nil
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
        binding = nil; pageCode = nil; page = nil; closeLiveState()
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
        currentPreview = try await api.checkoutPreview(shopPath: shopPath())
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
        slowNetwork = false
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        if page == nil, ticket != nil { PrismPageReport.shared.openFailed() }
        readBackoff.fail(retryAfter: (error as? PrismAPIError)?.retryAfter)
        if silent, error is URLError || (error as? PrismAPIError)?.isTransientReadFailure == true { return }
        if (error as? PrismAPIError)?.code == "AUTHENTICATION_REQUIRED" {
          state = .unauthenticated; user = nil; userId = ""; cards = []; page = nil; closeLiveState()
          summary = nil; binding = nil; checkoutPreview = nil; settlement = nil; assets = []; history = []
          playerStateLoaded = false; billLoaded = false; await api.invalidateReads()
        }
        refreshError = friendlyMessage(error)
        errorMessage = refreshError
      }
    }
  }

  private func show(_ next: PrismPage) {
    page = next
    if !next.offersPowerOn, waitingPower { waitingPower = false; powerWaitTask?.cancel() }
  }

  /// Keeps the channel that says when to read the page. Nothing here reads anything about the device.
  private func openPageSocket() {
    guard pageSocket == nil, sceneActive, let ticket, let socket = try? api.pageSocket(ticket: ticket) else { return }
    socketRetry?.cancel(); socketRetry = nil
    pageSocket = socket
    socketAnswered = false
    socketConnectingAt = Date()
    socket.resume()
    receivePageSocket(socket, version: invocationVersion)
    socketHeartbeat?.cancel()
    socketHeartbeat = Task { [weak self] in
      // The first ping is queued until the connection opens, and its answer says that it has.
      var wait: UInt64 = 15_000_000_000
      while !Task.isCancelled {
        guard let self, self.pageSocket === socket else { return }
        self.pongAwaited = true
        do { try await socket.send(.string("ping")) } catch { self.socketFailed(socket); return }
        do { try await Task.sleep(nanoseconds: wait) } catch { return }
        guard self.pageSocket === socket else { return }
        if self.pongAwaited { self.socketFailed(socket); return }
        wait = 10_000_000_000
        do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
      }
    }
  }

  func closeLiveState() {
    socketHeartbeat?.cancel(); socketHeartbeat = nil
    socketRetry?.cancel(); socketRetry = nil
    pageSocket?.cancel(with: .normalClosure, reason: nil)
    pageSocket = nil
  }

  private func receivePageSocket(_ socket: URLSessionWebSocketTask, version: Int) {
    socket.receive { [weak self] result in
      Task { @MainActor [weak self] in
        guard let self, self.pageSocket === socket, self.invocationVersion == version else { return }
        guard case .success(let message) = result, case .string(let text) = message else {
          self.socketFailed(socket)
          return
        }
        self.pongAwaited = false
        if !self.socketAnswered {
          self.socketAnswered = true
          self.socketFailures = 0
          PrismPageReport.shared.socketOpened(since: self.socketConnectingAt)
          // What changed while there was no connection was not told; a read just made needs no repeat.
          let first = !self.socketOpenedOnce
          self.socketOpenedOnce = true
          if !first || Date().timeIntervalSince(self.pageReadAt) > 3 { self.readPage() }
          if !first { self.askCapture?() }
        }
        if text.contains("event.pageChanged") { self.readPage() }
        if text.contains("event.cardRead") { self.askCapture?() }
        self.receivePageSocket(socket, version: version)
      }
    }
  }

  private func socketFailed(_ socket: URLSessionWebSocketTask) {
    guard pageSocket === socket else { return }
    pageSocket = nil
    socketHeartbeat?.cancel(); socketHeartbeat = nil
    socket.cancel(with: .goingAway, reason: nil)
    if socketAnswered { PrismPageReport.shared.socketDropped() }
    let waits: [UInt64] = [1, 3, 5, 10, 20, 30, 60]
    let wait = waits[min(socketFailures, waits.count - 1)]
    socketFailures += 1
    socketRetry = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: wait * 1_000_000_000) } catch { return }
      self?.openPageSocket()
    }
  }

  private func readPage() {
    if deviceBusy { refreshPending = true; return }
    Task { [weak self] in await self?.refreshVisit(silent: true, dynamicOnly: true) }
  }

  /// Does what the page offered: the same operation id each try, so it happens once however often
  /// the answer is lost, and the page it answers with is shown. A refusal is an answer, with `ok` false.
  private func pageAction(_ action: String, payload: [String: Any], location position: LocationSample?, ticket: String) async throws -> PrismActionAnswer {
    let key = action + ":" + payload.keys.sorted().map { "\($0)=\(payload[$0] ?? "")" }.joined(separator: "&")
    let operationId = unansweredActions[key] ?? UUID().uuidString
    unansweredActions[key] = operationId
    var body: [String: Any] = ["ticket": ticket, "operationId": operationId, "action": action, "payload": payload]
    if let position { body["location"] = ["lat": position.latitude, "lng": position.longitude, "accuracy": position.accuracy] }
    let version = invocationVersion
    defer { slowNetwork = false }
    var attempt = 1
    while true {
      do {
        let answer: PrismActionAnswer = try await api.request("/api/v1/devices/session/action", body: body)
        guard version == invocationVersion else { throw CancellationError() }
        if !answer.notices.contains(where: { $0.code == "OPERATION_PENDING" }) {
          unansweredActions[key] = nil
          pageReadAt = Date()
          // The bill and the Live Activity follow what this changed.
          if let page, answer.page.movedBilling(from: page) { refreshPending = true }
          show(answer.page)
          return answer
        }
      } catch let error as URLError where error.code != .cancelled {
        guard attempt < 5 else { throw PrismAPIError.api(code: "DEVICE_RESULT_UNKNOWN", message: "网络异常，请重试") }
      } catch {
        if error is PrismAPIError { unansweredActions[key] = nil }
        if (error as? PrismAPIError)?.isSessionExpired == true { expire() }
        throw error
      }
      if attempt >= 5 { throw PrismAPIError.api(code: "DEVICE_RESULT_UNKNOWN", message: "网络异常，请重试") }
      attempt += 1
      slowNetwork = true
      try await Task.sleep(nanoseconds: 1_500_000_000)
    }
  }

  /// Runs a player action. Its outcome is shown under the control named by `anchor`; the
  /// page is read again afterwards in the background, so nothing waits on that read.
  private func perform(_ anchor: String, _ action: () async throws -> Void) async {
    guard !deviceBusy, ![.locating, .sending].contains(state) else { return }
    let version = invocationVersion
    visitRevision += 1
    polling?.cancel()
    deviceBusy = true; errorMessage = nil
    defer {
      if version == invocationVersion {
        deviceBusy = false
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

  func expire() { ticket = nil; state = .expired; activeCardId = nil; captureRun += 1; cardCapture = nil; polling?.cancel(); closeLiveState(); errorMessage = nil }

  func startCardCapture() async {
    guard let ticket, !deviceBusy, !capturing, ![.locating, .sending].contains(state) else { return }
    captureRun += 1
    let run = captureRun, version = invocationVersion, api = self.api
    let current = { [weak self] in self?.captureRun == run && self?.invocationVersion == version }
    cardCapture = .starting
    do {
      let position: LocationSample? = page?.cards?.needsLocation == true ? try await location.currentLocation() : nil
      guard current() else { return }
      let started = try await api.startCardCapture(ticket: ticket, location: position.map { ["lat": $0.latitude, "lng": $0.longitude, "accuracy": $0.accuracy] })
      guard current() else {
        Task { try? await api.cancelCardCapture(captureId: started.captureId, ticket: ticket) }
        return
      }
      openCapture = (started.captureId, ticket)
      defer { if current() { openCapture = nil } }
      cardCapture = .waiting
      let deadline = (prismParsedDate(started.expiresAt) ?? Date()).addingTimeInterval(2)
      guard let status = try await captureOutcome(captureId: started.captureId, ticket: ticket, until: deadline, current: current),
            current() else { return }
      let added = ["added", "bound", "exists"].contains(status)
      let message: String
      if added { message = String(localized: "已添加卡片") }
      else if status == "taken" { message = String(localized: "这张卡已绑定到本店的其他玩家") }
      else if status == "unsupported" { message = String(localized: "不支持这种卡片") }
      else { message = String(localized: "没有读到卡片") }
      cardCapture = .done(level: added ? "success" : "error", message: message)
      if added {
        let response = try await api.cards()
        guard current() else { return }
        cards = response.cards.filter { $0.disabledAt == nil }
      }
    } catch {
      guard current(), !(error is CancellationError) else { return }
      if (error as? PrismAPIError)?.isSessionExpired == true { expire(); return }
      cardCapture = .done(level: "error", message: friendlyMessage(error))
    }
  }

  /// What became of the card, asked when told the reader has one, after a lost connection comes back,
  /// and once at the end of the window. Nil when a newer attempt or a cancel took over.
  private func captureOutcome(captureId: String, ticket: String, until deadline: Date, current: @escaping () -> Bool) async throws -> String? {
    var tell: AsyncStream<Void>.Continuation!
    let asks = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { tell = $0 }
    let told = tell!
    let timer = Task {
      try? await Task.sleep(nanoseconds: UInt64(max(0, deadline.timeIntervalSinceNow) * 1_000_000_000))
      told.yield()
    }
    askCapture = { told.yield() }
    defer { timer.cancel(); told.finish(); askCapture = nil }
    // The card may have been read before this answer got here.
    told.yield()
    for await _ in asks {
      guard current() else { return nil }
      let ended = Date() >= deadline
      do {
        let status = try await api.cardCaptureResult(captureId: captureId, ticket: ticket).status
        if status != "waiting" { return status }
        if ended { return "expired" }
      } catch {
        // An earlier ask can fail on a bad network; the next one says the same.
        if ended || (error as? PrismAPIError)?.isSessionExpired == true { throw error }
      }
    }
    return nil
  }

  /// Stops waiting for the reader, or puts away the outcome.
  func dismissCardCapture() {
    captureRun += 1; cardCapture = nil; askCapture?()
    guard let open = openCapture else { return }
    openCapture = nil
    let api = self.api
    // If this fails, the window closes by itself within seconds.
    Task { try? await api.cancelCardCapture(captureId: open.id, ticket: open.ticket) }
  }
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

  /// A button the page offered. Its outcome shows under it, or on it if the page says so.
  func press(_ button: PrismPageButton) async {
    guard let ticket else { expire(); return }
    await perform(button.id) {
      pressing = button.id
      defer { pressing = nil }
      var payload = (button.payload ?? [:]).mapValues(\.json)
      if button.requires != nil { payload["consent"] = true }
      let position: LocationSample? = button.needsLocation ? try await location.currentLocation() : nil
      let answer = try await pageAction(button.action, payload: payload, location: position, ticket: ticket)
      if let code = answer.code { showCode(code) }
      showNotices(answer.notices, anchor: button.id)
      // Still off, the page waits for the machine to say on; the hub tells it when that happens.
      if button.action == "power.on", answer.ok, answer.page.offersPowerOn { waitForPower() }
    }
  }

  private func showNotices(_ notices: [PrismNotice], anchor: String) {
    for notice in notices {
      if notice.display == "inline" { showInline(notice, anchor: anchor) }
      else if notice.display == "dialog" { dialogNotice = notice }
    }
  }

  private func showCode(_ code: PrismPageCode) {
    pageCode = code
    guard let expires = prismParsedDate(code.expiresAt) else { return }
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(max(0, expires.timeIntervalSinceNow) * 1_000_000_000))
      if self?.pageCode?.value == code.value { self?.pageCode = nil }
    }
  }

  /// The power button spins until the machine reports on; if it never does, the player
  /// gets the button back with a word instead of a spinner that never ends.
  private func waitForPower() {
    waitingPower = true
    powerWaitTask?.cancel()
    powerWaitTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 15_000_000_000)
      guard let self, !Task.isCancelled, self.waitingPower else { return }
      self.waitingPower = false
      self.showInline(PrismNotice(code: "POWER_NOT_SEEN", level: "warning", display: "inline", flow: "none",
                                  body: String(localized: "未检测到开机，请重试")), anchor: "power")
    }
  }
  /// Send an air conditioner action. The controls keep the choice until the page agrees with it.
  func climate(_ action: String, _ extra: [String: Any] = [:]) async {
    guard let ticket else { return }
    await perform("climate") {
      let position: LocationSample? = page?.climateNeedsLocation == true ? try await location.currentLocation() : nil
      let answer = try await pageAction(action, payload: extra, location: position, ticket: ticket)
      showNotices(answer.notices, anchor: "climate")
    }
  }

  func enter() async {
    let requiresLocation = (visit?.shop.locationEnabled ?? visit?.shop.checkinGeo) == true
    // Only a shop link enters this way, with no ticket: the server accepts a ticket-free entry when the
    // shop opts in, still requiring consent and (when configured) an on-site fix. A scanned page's
    // confirmation is one of its buttons.
    guard isShopOnly else { return }
    await perform("entry") {
      _ = try await operation("entry.remote", path: shopPath("player/remote-entry"), body: ["consent": true], requiresLocation: requiresLocation)
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
      let preview: PrismCheckout? = current.activeSession == nil ? nil : try await api.checkoutPreview(shopPath: shopPath())
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
      let value = try await api.checkoutPreview(shopPath: shopPath())
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
    isShopOnly = true; machine = nil; ticket = nil; publicId = nil; page = nil; pageCode = nil; cards = []
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
