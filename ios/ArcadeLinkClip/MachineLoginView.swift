import SwiftUI

struct MachineLoginView: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @State private var showingError = false

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        Group {
          switch model.state {
          case .idle, .loadingMachine:
            ClipLoadingPage()
          case .failed(let message):
            ClipFailurePage(message: message, retry: retrySession)
          case .expired:
            ClipExpiredPage()
          case .completed:
            ClipCompletedPage()
          case .unauthenticated, .loadingCards, .cardsFailed, .ready, .locating, .sending, .success:
            ClipSessionPage()
          }
        }
        .frame(maxWidth: 480)
        .frame(minHeight: max(0, geometry.size.height - 116), alignment: .top)
        .padding(.horizontal, 20).padding(.bottom, 28)
        // The provider notification overlays the safe area; reserve stable clearance.
        .padding(.top, 88)
        .frame(maxWidth: .infinity)
      }
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .alert("ArcadeLink", isPresented: $showingError) {
      Button("知道了") { model.clearError() }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .onChange(of: model.errorMessage) { value in
      showingError = value != nil
    }
  }

  private var retrySession: (() -> Void)? {
    guard let shop = model.shopCode, let machine = model.publicId else { return nil }
    return { Task { await model.start(shopCode: shop, publicId: machine) } }
  }
}

private struct ClipLoadingPage: View {
  var body: some View {
    ProgressView().accessibilityLabel("正在加载")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ClipFailurePage: View {
  let message: String
  let retry: (() -> Void)?

  var body: some View {
    VStack(spacing: 20) {
      ClipStatusMessage(title: "无法进入机台会话", message: message, symbol: "exclamationmark.triangle")
      if let retry { Button("重试", action: retry).buttonStyle(.borderedProminent) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ClipExpiredPage: View {
  var body: some View {
    ClipStatusMessage(title: "本次会话已失效", message: String(localized: "请重新碰一下 NFC 或重新扫描二维码。"), symbol: "clock.badge.exclamationmark")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ClipCompletedPage: View {
  var body: some View {
    ClipStatusMessage(title: "本次登录已完成", message: String(localized: "可以关闭此页面"), symbol: "checkmark.circle")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ClipSessionPage: View {
  @EnvironmentObject private var model: MachineLoginViewModel

  var body: some View {
    VStack(spacing: 30) {
      if let machine = model.machine {
        ClipShopHero(shop: machine.shop, machineName: machine.name).id(machine.shop.heroUrl)
      }

      VStack(spacing: 30) {
        if [.ready, .locating, .sending, .success].contains(model.state) {
          HStack {
            Text("选择卡片").font(.largeTitle.weight(.bold))
            Spacer()
            if #available(iOS 26.0, *) {
              logoutButton.buttonStyle(.glass).buttonBorderShape(.circle)
            } else {
              logoutButton.buttonStyle(.bordered).clipShape(Circle())
            }
          }
        }

        switch model.state {
        case .unauthenticated:
          VStack(spacing: 14) {
            Button { Task { await model.authenticateWithMunet() } } label: {
              actionLabel(model.authenticating == "munet" ? "正在连接 MuNET…" : "使用 MuNET 登录",
                          icon: Image("MuNETLogo").renderingMode(.original),
                          busy: model.authenticating == "munet")
            }
            .buttonStyle(ClipActionStyle(primary: true))
            Button { Task { await model.authenticateWithPasskey() } } label: {
              actionLabel(model.authenticating == "passkey" ? "正在验证 Passkey…" : "使用 Passkey 登录",
                          icon: Image(systemName: "touchid"),
                          busy: model.authenticating == "passkey")
            }
            .buttonStyle(ClipActionStyle())
          }
          .disabled(model.authenticating != nil)
        case .ready, .locating, .sending, .success:
          cardsView
        case .loadingCards:
          ProgressView().accessibilityLabel("正在加载卡片")
        case .cardsFailed(let message):
          VStack(spacing: 20) {
            ClipStatusMessage(title: "无法加载卡片", message: message, symbol: "exclamationmark.triangle")
            Button("重新加载卡片") { Task { await model.reloadCards() } }
              .buttonStyle(.borderedProminent)
          }
        case .idle, .loadingMachine, .failed, .completed, .expired:
          EmptyView()
        }
      }
      .padding(.top, 22)
    }
  }

  private var logoutButton: some View {
    Menu {
      Section("退出账号？") {
        Button("退出", role: .destructive) { Task { await model.logout() } }
      }
    } label: {
      Image(systemName: "rectangle.portrait.and.arrow.right")
        .font(.title3.weight(.semibold))
        .frame(minWidth: 30, minHeight: 30)
    }
    .menuIndicator(.hidden)
    .accessibilityLabel("退出账号")
    .disabled(model.state != .ready)
  }

  private func actionLabel(_ title: LocalizedStringKey, icon: Image, busy: Bool) -> some View {
    HStack(spacing: 10) {
      Group {
        if busy { ProgressView().tint(.primary) }
        else { icon.resizable().scaledToFit() }
      }
      .frame(width: 24, height: 24)
      .accessibilityHidden(true)
      Text(title).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity)
  }

  private var cardsView: some View {
    VStack(spacing: 0) {
      if model.cards.isEmpty {
        Text("还没有可用卡片，请先在 ArcadeLink 添加卡片")
          .foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button("重新加载卡片") { Task { await model.reloadCards() } }
          .buttonStyle(ClipActionStyle()).padding(.top, 20)
      } else {
        VStack(spacing: 0) {
          ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
            if index > 0 { Divider().padding(.leading, 24) }
            let active = model.activeCardId == card.id
            Button { Task { await model.login(card: card) } } label: {
              HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(card.label).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                  Text(active ? rowDetail(card) : cardEnding(card))
                    .font(.body).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if active && model.state == .success {
                  Image(systemName: "checkmark").foregroundStyle(.blue)
                } else if active && [.locating, .sending].contains(model.state) {
                  ProgressView()
                } else {
                  Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.tertiary)
                }
              }
              .padding(.horizontal, 24).padding(.vertical, 16)
              .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.primary)
            .disabled(model.state != .ready)
            .opacity(model.state != .ready && !active ? 0.45 : 1)
          }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 28))
      }
    }
  }

  private func rowDetail(_ card: ArcadeCard) -> String {
    switch model.state {
    case .locating: return String(localized: "确认位置…")
    case .sending: return String(localized: "正在登录…")
    case .success: return String(localized: "已登录")
    default: return cardEnding(card)
    }
  }

  private func cardEnding(_ card: ArcadeCard) -> String {
    String.localizedStringWithFormat(NSLocalizedString("尾号 %@", comment: "Last four card digits"), String(card.accessCode.suffix(4)))
  }
}

struct ClipShopHero: View {
  let shop: Shop
  let machineName: String
  @State private var image: UIImage?

  private var url: URL? {
    shop.heroUrl.flatMap { URL(string: $0, relativeTo: URL(string: "https://link.neri.moe"))?.absoluteURL }
  }

  // A separate public-image cache; authentication and machine sessions stay untouched.
  static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024,
                                      diskCapacity: 64 * 1024 * 1024,
                                      diskPath: "arcadelink-heroes")
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return URLSession(configuration: configuration)
  }()

  var body: some View {
    // One decoded image supplies both the cover and the soft color underneath.
    VStack(alignment: .leading, spacing: 0) {
      if let image {
        Color.clear.aspectRatio(1.5, contentMode: .fit)
          .overlay { Image(uiImage: image).resizable().scaledToFill() }
          .clipped()
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(shop.name)
          .font(.title.weight(.bold))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text(machineName).font(.title3.weight(.medium)).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 24).padding(.vertical, 22)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        if let image {
          GeometryReader { geometry in
            Image(uiImage: image).resizable().scaledToFill()
              .frame(width: geometry.size.width + 128, height: geometry.size.height + 128)
              .clipped()
              .blur(radius: 64)
              .offset(x: -64, y: -64)
              .opacity(0.22)
          }
          .accessibilityHidden(true)
        }
      }
      .clipped()
    }
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 32))
    .task(id: url) {
      image = nil
      guard let url else { return }
      do {
        let (data, response) = try await Self.session.data(from: url)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = UIImage(data: data) else {
          Self.session.configuration.urlCache?.removeCachedResponse(for: URLRequest(url: url))
          return
        }
        image = decoded
      } catch {
        // A missing cover does not prevent machine login; keep it hidden.
      }
    }
  }
}

private struct ClipStatusMessage: View {
  let title: LocalizedStringKey
  let message: String
  let symbol: String

  var body: some View {
    if #available(iOS 17.0, *) {
      ContentUnavailableView(title, systemImage: symbol, description: Text(message))
        .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(spacing: 12) {
        Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
        Text(title).font(.title2.weight(.bold))
        Text(message).foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
    }
  }
}

private struct ClipActionStyle: ButtonStyle {
  var primary = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(primary ? Color.white : Color.primary)
      .padding(.horizontal, 24).padding(.vertical, 16)
      .frame(maxWidth: .infinity, minHeight: 58)
      .background(primary ? Color.blue : Color.primary.opacity(0.065), in: Capsule())
      .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.7 : 1)
  }
}
