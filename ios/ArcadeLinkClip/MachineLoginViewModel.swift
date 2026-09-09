import Foundation
import Combine

@MainActor
final class MachineLoginViewModel: ObservableObject {
  enum State: Equatable {
    case idle
    case loadingMachine
    case unauthenticated
    case loadingCards
    case completed
    case expired
    case ready
    case locating
    case sending
    case success
    case failed
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

  init(api: ArcadeLinkAPI = .shared) {
    self.api = api
  }

  var webFallbackURL: URL? {
    guard let ticket else { return nil }
    return api.webFallbackURL(ticket: ticket)
  }

  func handleInvocation(_ url: URL) async {
    guard let invocation = InvocationParser.invocation(from: url) else {
      state = .failed
      errorMessage = "无效的机台地址"
      return
    }
    await start(shopCode: invocation.shopCode, publicId: invocation.machinePublicId)
  }

  func start(shopCode: String, publicId: String) async {
    self.shopCode = shopCode
    self.publicId = publicId
    state = .loadingMachine
    machine = nil
    cards = []
    activeCardId = nil
    ticket = nil
    errorMessage = nil
    do {
      let session = try await api.startMachineSession(shopCode: shopCode, publicId: publicId)
      ticket = session.ticket
      machine = session.machine
      let me = try await api.me()
      guard me.user != nil else {
        state = .unauthenticated
        return
      }
      try await loadCards()
    } catch {
      fail(error)
    }
  }

  func authenticateWithPasskey() async {
    guard state == .unauthenticated, authenticating == nil else { return }
    authenticating = "passkey"
    errorMessage = nil
    defer { authenticating = nil }
    do {
      let options = try await api.passkeyOptions()
      let assertion = try await passkey.authenticate(options: options)
      try await api.loginWithPasskey(assertion)
      try await loadCards()
    } catch {
      errorMessage = friendlyMessage(error)
      if state != .loadingCards { state = .unauthenticated }
    }
  }

  func authenticateWithMunet() async {
    guard state == .unauthenticated, authenticating == nil else { return }
    authenticating = "munet"
    errorMessage = nil
    defer { authenticating = nil }
    do {
      let code = try await munet.authenticate()
      try await api.exchangeAppClipAuth(code: code)
      try await loadCards()
    } catch {
      errorMessage = friendlyMessage(error)
      if state != .loadingCards { state = .unauthenticated }
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
    } catch { errorMessage = "退出账号失败，请重试" }
  }

  func reloadCards() async {
    errorMessage = nil
    do { try await loadCards() }
    catch { errorMessage = friendlyMessage(error) }
  }

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
      if errorMessage == "本次会话已失效" { state = .expired } else { state = .ready }
      activeCardId = nil
      errorMessage = friendlyMessage(error)
    }
  }

  private func loadCards() async throws {
    state = .loadingCards
    let response = try await api.cards()
    cards = response.cards.filter { $0.disabledAt == nil }
    state = .ready
  }

  private func fail(_ error: Error) {
    state = .failed
    errorMessage = friendlyMessage(error)
  }
  private func friendlyMessage(_ error: Error) -> String {
    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    if message.contains("定位权限") { return "需要定位权限才能确认你在店内" }
    if message.contains("机台") || message.contains("502") || message.contains("404") {
      return "这台机台暂时不可用，请稍后重试"
    }
    if message.contains("请求失败") { return "连接失败，请稍后重试" }
    return message
  }
}
