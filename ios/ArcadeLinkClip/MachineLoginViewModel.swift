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

  let api: ArcadeLinkAPI
  private let passkey = PasskeyAuthenticationService()
  private let munet = MunetAuthenticationService()
  private let location = LocationService()
  private var invocationVersion = 0

  init(api: ArcadeLinkAPI = .shared) {
    self.api = api
  }

  var webFallbackURL: URL? {
    guard let ticket else { return nil }
    return api.webFallbackURL(ticket: ticket)
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
      guard me.user != nil else {
        state = .unauthenticated
        return
      }
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
    do {
      var request = URLRequest(url: URL(string: "https://link.neri.moe/api/auth/logout")!)
      request.httpMethod = "POST"
      _ = try await URLSession.shared.data(for: request)
      state = .unauthenticated
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
    } catch {
      guard version == invocationVersion else { return }
      let message = friendlyMessage(error)
      state = (error as? ArcadeLinkAPIError)?.isSessionExpired == true ? .expired : .cardsFailed(message)
    }
  }

  func clearError() { errorMessage = nil }

  func login(card: ArcadeCard) async {
    guard state == .ready else { return }
    guard let ticket else {
      state = .expired
      errorMessage = nil
      return
    }
    activeCardId = card.id
    state = .locating
    errorMessage = nil
    do {
      let position = try await location.currentLocation()
      guard self.ticket == ticket else { return }
      state = .sending
      try await api.loginMachine(MachineLoginRequest(
        cardId: card.id,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        ticket: ticket,
      ))
      guard self.ticket == ticket else { return }
      state = .success
      self.ticket = nil
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      if state == .success { state = .completed }
    } catch {
      guard self.ticket == ticket else { return }
      let message = friendlyMessage(error)
      if (error as? ArcadeLinkAPIError)?.isSessionExpired == true { state = .expired } else { state = .ready }
      activeCardId = nil
      errorMessage = state == .expired ? nil : message
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
