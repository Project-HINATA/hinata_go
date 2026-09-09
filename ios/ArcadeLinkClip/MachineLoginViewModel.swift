import Foundation
import Combine

@MainActor
final class MachineLoginViewModel: ObservableObject {
  enum State: Equatable {
    case idle
    case loadingMachine
    case unauthenticated
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
    state = .loadingMachine
    errorMessage = nil
    do {
      let options = try await api.passkeyOptions()
      let assertion = try await passkey.authenticate(options: options)
      try await api.loginWithPasskey(assertion)
      try await loadCards()
    } catch {
      fail(error)
    }
  }

  func authenticateWithMunet() async {
    state = .loadingMachine
    errorMessage = nil
    do {
      let code = try await munet.authenticate()
      try await api.exchangeAppClipAuth(code: code)
      try await loadCards()
    } catch {
      fail(error)
    }
  }

  func login(card: ArcadeCard) async {
    guard let ticket else {
      fail(ArcadeLinkAPIError.server("本次会话已失效"))
      return
    }
    state = .locating
    errorMessage = nil
    do {
      let position = try await location.currentLocation()
      state = .sending
      try await api.loginMachine(MachineLoginRequest(
        cardId: card.id,
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        ticket: ticket,
      ))
      state = .success
    } catch {
      fail(error)
    }
  }

  private func loadCards() async throws {
    let response = try await api.cards()
    cards = response.cards.filter { $0.disabledAt == nil }
    state = .ready
  }

  private func fail(_ error: Error) {
    state = .failed
    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
  }
}
