import SwiftUI

struct MachineLoginView: View {
  var allowsDismiss = false
  /// Set when this is the App Clip root: the top of the screen belongs to the system provider
  /// notice, so the controls stay floating above the pushed-down content. The main app presents
  /// this as a page sheet instead, where both controls belong in a navigation toolbar.
  var presentsAppClipNotice = false
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var model: MachineLoginViewModel
  @State private var showingError = false
  @State private var section: Int?

  var body: some View {
    Group {
      if presentsAppClipNotice {
        page
          .overlay(alignment: .topLeading) { floatingDismissButton }
          .overlay(alignment: .topTrailing) { floatingAccountMenu }
      } else {
        NavigationStack {
          page
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .topBarLeading) { toolbarDismissButton }
              ToolbarItem(placement: .topBarTrailing) { toolbarAccountMenu }
            }
        }
      }
    }
    .sheet(isPresented: Binding(get: { section != nil }, set: { if !$0 { section = nil } })) {
      if let section {
        if #available(iOS 16.0, *) { ClipAccountSheet(section: section).environmentObject(model).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        else { ClipAccountSheet(section: section).environmentObject(model) }
      }
    }
    .alert("PRiSM", isPresented: $showingError) {
      Button("知道了") { model.clearError() }

    } message: {
      Text(model.errorMessage ?? "")
    }
    .onChange(of: model.errorMessage) { value in
      showingError = value != nil && section == nil
    }
  }

  private var page: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 28) {
          switch model.state {
          case .idle, .loadingMachine, .loadingShop:
            ClipLoadingPage()
          case .failed(let message):
            ClipFailurePage(message: message, retry: retrySession)
          case .expired:
            ClipExpiredPage()
          case .completed: ClipExpiredPage()
          case .unauthenticated, .loadingCards, .cardsFailed, .ready, .locating, .sending, .success:
            ClipSessionPage()
          }
        }
        .frame(maxWidth: 480)
        .frame(minHeight: max(0, geometry.size.height - 168), alignment: .top)
        .padding(.horizontal, 20).padding(.bottom, 28)
        // In the App Clip the content has to clear the provider notice; in a sheet the toolbar
        // already reserves that space.
        .padding(.top, presentsAppClipNotice ? 140 : 12)
        .frame(maxWidth: .infinity)
      }
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
  }

  @ViewBuilder private var floatingDismissButton: some View {
    if allowsDismiss {
      Group {
        if #available(iOS 26.0, *) {
          Button { dismiss() } label: { Image(systemName: "xmark") }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        } else {
          Button { dismiss() } label: { Image(systemName: "xmark") }
            .buttonStyle(.bordered)
        }
      }
      .tint(.primary)
      .padding(.top, 8).padding(.leading, 20)
    }
  }

  @ViewBuilder private var floatingAccountMenu: some View {
    if let user = model.user {
      Group {
        if #available(iOS 26.0, *) { accountMenu(user).buttonStyle(.glass).buttonBorderShape(.capsule) }
        else { accountMenu(user).buttonStyle(.bordered).buttonBorderShape(.capsule) }
      }
      .disabled(model.deviceBusy || [.locating, .sending].contains(model.state)).padding(.top, 8).padding(.trailing, 20)
    }
  }

  /// Toolbar items rely on the system appearance, so no glass or bordered style is applied here.
  @ViewBuilder private var toolbarDismissButton: some View {
    if allowsDismiss {
      if #available(iOS 26.0, *) {
        Button(role: .close) { dismiss() }
      } else {
        Button { dismiss() } label: { Image(systemName: "xmark") }
          .accessibilityLabel("关闭")
      }
    }
  }

  @ViewBuilder private var toolbarAccountMenu: some View {
    if let user = model.user {
      accountMenu(user).disabled(model.deviceBusy || [.locating, .sending].contains(model.state))
    }
  }

  private func accountMenu(_ user: PrismUser) -> some View {
    Menu {
      if model.visit?.shop.billingEnabled == true {
        // On a shop link the bill already occupies the page, so the menu omits it there;
        // redeem, history and wallet keep their entries on both surfaces.
        let sections = model.isShopOnly ? [1, 2, 3] : [0, 1, 2, 3]
        let labels: [LocalizedStringKey] = ["账单", "兑换", "记录", "钱包"]
        ForEach(sections, id: \.self) { index in
          Button(labels[index]) { section = index }
        }
      }
      Button("退出登录") { Task { await model.logout() } }
    } label: {
      HStack(spacing: 8) {
        if model.summary?.activeSession != nil {
          Circle().fill(.green).frame(width: 6, height: 6)
          Text("计费中").font(.caption).foregroundStyle(.secondary)
        }
        Text(user.displayName.isEmpty ? user.id : user.displayName).lineLimit(1)
        Image(systemName: "chevron.down").font(.caption)
      }.font(.subheadline).padding(.horizontal, 8).padding(.vertical, 6)
    }.tint(.primary)
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
      if let retry {
        Button(action: retry) { Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12) }
          .clipActionStyle(primary: true)
      }
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

private struct ClipSessionPage: View {
  @EnvironmentObject private var model: MachineLoginViewModel

  var body: some View {
    // The receipt takes over the page on both link types, so a settled bill cannot flash back
    // to the admission view before the player has read the result.
    if let settlement = model.settlement {
      VStack(spacing: 28) {
        if let machine = model.machine {
          ClipShopHero(name: machine.shop.name, subtitle: machine.name, heroUrl: machine.shop.heroUrl, origin: model.api.baseURL).id(machine.shop.heroUrl)
        } else if let visit = model.visit {
          ClipShopHero(name: visit.shop.name ?? "PRiSM", subtitle: model.shopBillingState, heroUrl: visit.shop.heroUrl, origin: model.api.baseURL).id(visit.shop.heroUrl)
        }
        ClipSettlementPage(settlement: settlement)
      }
      .frame(maxWidth: 480)
    } else {
      sessionBody
    }
  }

  private var sessionBody: some View {
    VStack(spacing: 52) {
      if let machine = model.machine {
        ClipShopHero(name: machine.shop.name, subtitle: machine.name, heroUrl: machine.shop.heroUrl, origin: model.api.baseURL).id(machine.shop.heroUrl)

      } else if model.isShopOnly, let visit = model.visit {
        // The shop link shows the same card as a device link; the line that carries the
        // machine name there carries the billing state here.
        ClipShopHero(name: visit.shop.name ?? "PRiSM", subtitle: model.shopBillingState, heroUrl: visit.shop.heroUrl, origin: model.api.baseURL).id(visit.shop.heroUrl)
      }

      VStack(spacing: 28) {
        if model.isShopOnly {
          if [.ready, .locating, .sending, .success].contains(model.state) { ClipShopControls() }
        } else if model.showDeviceControls, [.ready, .locating, .sending, .success].contains(model.state) {
          ClipDeviceControls()
        }
        if !model.isShopOnly, model.canUseCards, [.ready, .locating, .sending, .success].contains(model.state) {
          Text("选择卡片").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.bottom, 2)
        }

        switch model.state {
        case .unauthenticated:
          VStack(spacing: 14) {
            Button { Task { await model.authenticateWithMunet() } } label: {
              actionLabel(model.authenticating == "munet" ? "正在连接 MuNET…" : "使用 MuNET 登录",
                          icon: Image("MuNETLogo").renderingMode(.original),
                          busy: model.authenticating == "munet")
            }
            .clipActionStyle(primary: true)
            Button { Task { await model.authenticateWithPasskey() } } label: {
              actionLabel(model.authenticating == "passkey" ? "正在验证 Passkey…" : "使用 Passkey 登录",
                          icon: Image(systemName: "touchid"),
                          busy: model.authenticating == "passkey")
            }
            .clipActionStyle()
          }
          .disabled(model.authenticating != nil)
        case .ready, .locating, .sending, .success:
          if !model.isShopOnly, model.canUseCards { cardsView.disabled(model.deviceBusy) }
          if model.state == .ready, model.deviceState?.gate == "ready", model.deviceState?.power != "off", model.machine?.has("coin") == true, model.machine?.coinAfterSwipe != true {
            Button { Task { await model.device("coin") } } label: {
              HStack(spacing: 10) { if model.deviceBusy { ProgressView() } else { Image(systemName: "centsign.circle") }; Text("投币") }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.clipActionStyle().disabled(model.deviceBusy)
          }
        case .loadingCards:
          ProgressView().accessibilityLabel("正在加载卡片")
        case .cardsFailed(let message):
          VStack(spacing: 20) {
            ClipStatusMessage(title: "无法加载卡片", message: message, symbol: "exclamationmark.triangle")
            Button { Task { await model.reloadCards() } } label: {
              Text("重新加载卡片").frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .clipActionStyle(primary: true)
          }
        case .idle, .loadingMachine, .loadingShop, .failed, .completed, .expired:
          EmptyView()
        }
      }
    }
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
    }.frame(maxWidth: .infinity).padding(.vertical, 12)
  }

  private var cardsView: some View {
    VStack(spacing: 0) {
      if model.cards.isEmpty {
        Text("还没有可用卡片，请先在 Prism 添加卡片")
          .foregroundStyle(.secondary).multilineTextAlignment(.center)
        Link(destination: model.api.baseURL.appendingPathComponent("cards")) {
          Text("添加卡片").frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .clipActionStyle().padding(.top, 16)
        Button { Task { await model.reloadCards() } } label: {
          Text("重新加载卡片").frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .clipActionStyle().padding(.top, 24)
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
  let name: String
  /// The line under the shop name: the machine name for a device link, the billing state
  /// for the shop link.
  let subtitle: String
  var heroUrl: String? = nil
  var origin: URL = PrismAPI.defaultOrigin
  @State private var image: UIImage?

  private var url: URL? {
    heroUrl.flatMap { URL(string: $0, relativeTo: origin)?.absoluteURL }
  }

  // A separate public-image cache; authentication and machine sessions stay untouched.
  static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(memoryCapacity: 4 * 1024 * 1024,
                                      diskCapacity: 64 * 1024 * 1024,
                                      diskPath: "prism-heroes")
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    return URLSession(configuration: configuration)
  }()

  var body: some View {
    // One decoded image supplies both the cover and the soft color underneath. The cover box
    // is reserved before the bytes arrive, so the card does not start short and pop to full
    // height once the image decodes.
    VStack(alignment: .leading, spacing: 0) {
      if url != nil {
        Color.clear.aspectRatio(1.5, contentMode: .fit)
          .overlay {
            if let image {
              Image(uiImage: image).resizable().scaledToFill()
            } else {
              Rectangle().fill(Color.primary.opacity(0.04))
            }
          }
          .clipped()
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 8) {
        Text(name)
          .font(.title.weight(.bold))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityAddTraits(.isHeader)
        Text(subtitle).font(.title3.weight(.medium)).foregroundStyle(.secondary)
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
    .overlay {
      RoundedRectangle(cornerRadius: 32).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)
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
      ContentUnavailableView {
        Label { Text(title).font(.title2) } icon: { Image(systemName: symbol) }
      } description: { Text(message) }
        .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(spacing: 12) {
        Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
        Text(title).font(.title2)
        Text(message).foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
    }
  }
}

/// Action buttons render as Liquid Glass on iOS 26+ (prominent for the main action,
/// regular glass for secondary ones) and keep the flat pill on earlier systems.
private struct ClipActionModifier: ViewModifier {
  var primary = false

  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if primary {
        content.font(.headline).buttonStyle(.glassProminent).tint(.blue).buttonBorderShape(.capsule)
      } else {
        content.font(.headline).buttonStyle(.glass).buttonBorderShape(.capsule)
      }
    } else {
      content.buttonStyle(ClipActionStyle(primary: primary))
    }
  }
}

/// Fallback used below iOS 26, where glass button styles are unavailable.
private struct ClipActionStyle: ButtonStyle {
  var primary = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(primary ? Color.white : Color.primary)
      .padding(.horizontal, 24)
      .frame(maxWidth: .infinity, minHeight: 58)
      .background(primary ? Color.blue : Color.primary.opacity(0.065), in: Capsule())
      .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.7 : 1)
  }
}

private extension View {
  func clipActionStyle(primary: Bool = false) -> some View {
    modifier(ClipActionModifier(primary: primary))
  }
}

/// What replaces the device controls on a shop link. Admission is not offered here: entry
/// proves physical presence, and only a scanned machine ticket does that, so a player who has
/// not checked in is pointed at the machine QR instead.
private struct ClipShopControls: View {
  @EnvironmentObject private var model: MachineLoginViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let shop = model.visit {
        if model.shopHasActiveSession {
          // The page already applies a 20pt horizontal margin, so the bill only adds the
          // remainder of the sheet's 24pt inset and the two surfaces line up.
          ClipAccountContent(section: 0, horizontalPadding: 4)
        } else if shop.membership == nil {
          // The shop player row is created by the Bot, so this page can only explain it.
          VStack(alignment: .leading, spacing: 12) {
            Text("绑定 QQ").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            Text("本店的玩家档案与 QQ 绑定，请在店铺机器人中完成验证后再回到这里。")
              .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            if !shop.shop.botContact.isEmpty {
              Text(String(localized: "店铺联系方式") + " " + shop.shop.botContact)
                .font(.subheadline).textSelection(.enabled)
            }
          }.frame(maxWidth: .infinity, alignment: .leading)
        } else if shop.shop.billingEnabled {
          Text("请碰一下 NFC 或扫描机台上的二维码入场")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
      } else if model.errorMessage != nil {
        Button { Task { model.clearError(); await model.refreshVisit() } } label: {
          Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12)
        }.clipActionStyle()
      } else { ProgressView().accessibilityLabel("正在加载") }
    }.disabled(model.deviceBusy || [.locating, .sending].contains(model.state))
  }
}

/// The checkout receipt. Rendering it here is what stops a settled bill from falling straight
/// back to the admission view before the player can read the result.
private struct ClipSettlementPage: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let settlement: PrismCheckoutResult

  private func amount(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 10) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
        Text("结账成功").font(.title2.weight(.semibold))
      }
      VStack(alignment: .leading, spacing: 4) {
        Text("本次消费").font(.subheadline).foregroundStyle(.secondary)
        Text(amount(settlement.playerSettlement.total))
          .font(.largeTitle.bold()).monospacedDigit()
      }
      if !settlement.chargeItems.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(settlement.chargeItems) { item in
            PrismLabeledRow(item.label, value: amount(item.amount))
          }
        }
      }
      if !settlement.adjustments.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(settlement.adjustments) { item in
            PrismLabeledRow(item.label, value: amount(item.amount))
          }
        }
      }
      if let wallet = settlement.wallet {
        PrismLabeledRow(String(localized: "结账后余额"), value: amount(wallet.balanceAfter))
      }
      Text("计费已结束，离店前无需再做其他操作。")
        .font(.subheadline).foregroundStyle(.secondary)
      Button { model.clearSettlement() } label: {
        Text("完成").frame(maxWidth: .infinity).padding(.vertical, 12)
      }.clipActionStyle(primary: true)
    }
    .frame(maxWidth: 480, alignment: .leading)
    .padding(20)
    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
  }
}

private struct ClipDeviceControls: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @State private var consent = false
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let device = model.deviceState, let shop = model.visit {
        if device.gate == "qq" {
          VStack(alignment: .leading, spacing: 24) {
            Text("绑定 QQ").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 18) {
              Text("在 QQ 群中发送").font(.subheadline)
              if let binding = model.binding {
                Text("prism.bind \(binding.code)").font(.system(size: 21, design: .monospaced)).textSelection(.enabled)
                Text(String(localized: "有效期至") + " " + prismTime(binding.expiresAt)).font(.caption).foregroundStyle(.secondary)
              } else if model.errorMessage != nil { Button("重试") { Task { await model.bindQQ() } } }
              else { ProgressView() }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
          }
        } else {
          if device.gate == "entry" {
            VStack(alignment: .leading, spacing: 24) {
              Text("确认入场").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
              ClipEntryPricing(shop: shop)
              Button { consent.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                  Image(systemName: consent ? "checkmark.square.fill" : "square").foregroundStyle(consent ? Color.blue : .secondary)
                  Text("确认开始计费，离店前请结账。关闭页面不会停止计费。").font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              }.buttonStyle(.plain).accessibilityValue(consent ? "✓" : "—")
              if model.machine?.has("door") != true {
                Button { Task { await model.enter() } } label: {
                  HStack { if model.deviceBusy { ProgressView() }; Text("确认入场") }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.clipActionStyle(primary: true).disabled(!consent)
              }
            }
          }
          if model.machine?.has("door") == true {
            if let password = model.doorPassword {
              VStack(spacing: 16) {
                Text("开门密码").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
                Text(password.temporaryPassword).font(.system(size: 36, design: .monospaced)).tracking(4).textSelection(.enabled)
                Text(String(localized: "有效期至") + " " + prismTime(password.expiresAt)).font(.caption).foregroundStyle(.secondary)
                Text("在门锁上输入密码后按 #").font(.subheadline).foregroundStyle(.secondary)
              }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            Button { Task { await model.device("door.open", consent: consent) } } label: {
              HStack(spacing: 10) { if model.deviceBusy { ProgressView() } else { Image(systemName: "door.left.hand.open") }; Text(model.doorPassword != nil ? "重新获取密码" : device.gate == "entry" ? "入场并获取开门密码" : "获取开门密码") }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.clipActionStyle(primary: true).disabled(device.gate == "entry" && !consent)
          }
          if device.gate == "ready", device.power != "off", let table = device.mahjong {
            let mine = table.seats.contains { $0.mine }
            VStack(spacing: 16) {
              HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                  Text("麻将桌").font(.title3.weight(.semibold))
                  Text(table.seats.contains { $0.playing } ? "麻将计费中" : "等待玩家")
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                  Text("\(table.seats.count)").font(.title2.weight(.semibold))
                  Text("/ \(table.capacity)").font(.body).foregroundStyle(.secondary)
                }.monospacedDigit()
              }
              LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(0..<table.capacity, id: \.self) { index in
                  let seat = index < table.seats.count ? table.seats[index] : nil
                  VStack(alignment: .leading, spacing: 6) {
                    if let seat { Text(seat.name).font(.body.weight(.medium)) }
                    else { Text("空位").font(.body).foregroundStyle(.tertiary) }
                    if seat?.mine == true { Text("你").font(.caption).foregroundStyle(.secondary) }
                  }
                  .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                  .padding(16)
                  .background(seat == nil ? Color.clear : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
                  .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(seat?.mine == true ? 0.3 : seat == nil ? 0.08 : 0), lineWidth: seat?.mine == true ? 1.5 : 1))
                }
              }
              if !mine && table.seats.count >= table.capacity {
                Text("已满桌").font(.subheadline).foregroundStyle(.secondary)
              } else {
                Button { Task { await model.device(mine ? "mahjong.leave" : "mahjong.join") } } label: {
                  HStack { if model.deviceBusy { ProgressView() }; Text(mine ? "下桌" : "上桌") }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.clipActionStyle(primary: !mine)
              }
            }.frame(maxWidth: .infinity)

          }
          if device.gate == "ready", device.power == "off" {
            VStack(spacing: 28) {
              Text("设备尚未开机").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
              Button { Task { await model.device("power.on") } } label: {
                HStack(spacing: 10) { if model.deviceBusy || model.waitingPower { ProgressView() } else { Image(systemName: "power") }; Text("开机") }
                  .frame(maxWidth: .infinity).padding(.vertical, 12)
              }.clipActionStyle(primary: true).disabled(model.waitingPower)
            }.frame(maxWidth: .infinity)
          }
        }
      } else if model.errorMessage != nil {
        Button { Task { model.clearError(); await model.refreshVisit() } } label: {
          Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12)
        }.clipActionStyle()
      } else { ProgressView().accessibilityLabel("正在加载") }
    }.disabled(model.deviceBusy || [.locating, .sending].contains(model.state))
  }
}

private struct ClipEntryPricing: View {
  let shop: PrismShopResponse
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(shop.entryPricing) { plan in
        Text(plan.name).font(.subheadline.bold())
        if let amount = plan.provider.amount { Text(String(localized: "每次入场") + " · " + amount.formatted()).font(.subheadline) }
        if let rules = plan.provider.rules {
          Text("时段重叠时，按下方从上到下的顺序采用规则。").font(.caption).foregroundStyle(.secondary)
          ForEach(rules.filter { $0.status != "archived" }) { rule in
            ClipPricingRow(rule: rule)
            Divider()
          }
        }
      }
      if shop.entryPricing.contains(where: { $0.kind != "charge.fixed" }) {
        Text("按时段分别计费，不足一个单位向上取整，宽限内不计下一单位。封顶按规则时段累计，跨午夜的同一时段连续累计。").font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

private struct ClipPricingRow: View {
  let rule: PrismShopResponse.Pricing.Rule
  private var period: String {
    guard let time = rule.timeRange else { return String(localized: "连续时段") }
    if time.start == time.end { return String(localized: "全天") }
    return time.start + "–" + (time.start > time.end ? String(localized: "次日") : "") + time.end
  }
  private var rateText: String {
    if let rate = rule.pricing { return "\(rate.unitPrice.formatted()) / \(rate.unitMinutes.formatted()) " + String(localized: "分钟") }
    return String(localized: "合计封顶") + " " + (rule.priceCap?.formatted() ?? "—")
  }
  private var weekdays: String {
    let formatter = DateFormatter()
    return (rule.weekdays ?? []).filter { (0...6).contains($0) }.map { formatter.shortWeekdaySymbols[$0] }.joined(separator: " · ")
  }
  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Text(period).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
      VStack(alignment: .leading, spacing: 6) {
        Text(rule.label).font(.subheadline.bold())
        if !weekdays.isEmpty { Text(weekdays).font(.caption).foregroundStyle(.secondary) }
        if let dates = rule.specificDates, !dates.isEmpty { Text(dates.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
        if let dates = rule.displayDateTimeRange { Text(dates.start + " – " + dates.end).font(.caption).foregroundStyle(.secondary) }
        Text(rateText).font(.subheadline)
        if let pricing = rule.pricing {
          if pricing.priceCap < 9007199254740991 { Text(String(localized: "时段封顶") + " " + pricing.priceCap.formatted()).font(.caption).foregroundStyle(.secondary) }
          if pricing.roundGraceMinutes > 0 { Text(String(localized: "每计费单位宽限") + " " + pricing.roundGraceMinutes.formatted() + " " + String(localized: "分钟")).font(.caption).foregroundStyle(.secondary) }
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }.padding(.vertical, 8)
  }
}

private struct ClipAccountSheet: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @Environment(\.dismiss) private var dismiss
  let section: Int
  private var title: LocalizedStringKey { ["账单", "兑换", "记录", "钱包"][section] }
  @ViewBuilder private var closeButton: some View {
    if #available(iOS 26.0, *) {
      Button(role: .close) { dismiss() }
    } else {
      Button { dismiss() } label: { Image(systemName: "xmark") }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(.primary)
        .accessibilityLabel("关闭")
    }
  }
  var body: some View {
    if #available(iOS 26.0, *) {
      NavigationStack { content }
        .presentationCornerRadius(nil)
    } else if #available(iOS 16.0, *) {
      NavigationStack { content }
    } else {
      NavigationView { content }.navigationViewStyle(.stack)
    }
  }
  private var content: some View {
    ClipAccountContent(section: section)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          closeButton
        }
      }
  }
}

/// The account sections' body. Shared by the toolbar sheet and the shop page so the bill has
/// one implementation; the shop page embeds section 0 without the sheet's navigation chrome.
private struct ClipAccountContent: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let section: Int
  /// The toolbar sheet supplies its own inset. The shop page already carries the page's
  /// horizontal margin, so it passes the remainder and both land on the same edge.
  var horizontalPadding: CGFloat = 24
  @State private var redeemCode = ""
  @State private var done = false
  @State private var loadError: String?
  @State private var attempt = 0
  @ViewBuilder private func billTotals(_ timeline: PrismBillTimeline) -> some View {
    ForEach(Array(timeline.totals.enumerated()), id: \.offset) { _, item in
      (Text(item.name + " ").foregroundColor(.secondary) + Text(item.amount.formatted(.number.precision(.fractionLength(2)))).foregroundColor(item.amount < 0 ? .green : .secondary)).font(.caption)
    }
  }
  private var checkoutButton: some View {
    Button { Task { await model.checkout(); done = model.errorMessage == nil } } label: {
      HStack { if model.deviceBusy { ProgressView() }; Text("结账") }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    .clipActionStyle(primary: true)
    .disabled(model.deviceBusy)
  }
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
      VStack(alignment: .leading, spacing: 20) {
      if section == 0, !done, let preview = model.checkoutPreview {
        VStack(alignment: .leading, spacing: 4) {
          Text("合计").font(.subheadline).foregroundStyle(.secondary)
          Text(preview.settlementPreview.total.formatted(.number.precision(.fractionLength(2))))
            .font(.largeTitle.bold()).monospacedDigit()
          if let timeline = preview.timeline {
            if #available(iOS 16.0, *) {
              ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { billTotals(timeline) }
                VStack(alignment: .leading, spacing: 4) { billTotals(timeline) }
              }.padding(.top, 6)
            } else { VStack(alignment: .leading, spacing: 4) { billTotals(timeline) }.padding(.top, 6) }
          }
        }.frame(maxWidth: 480, alignment: .leading).padding(.bottom, 4)
      }

        if let error = loadError ?? model.errorMessage {
          VStack(alignment: .leading, spacing: 8) {
            Text(error).font(.subheadline).foregroundStyle(.red)
            Button("重试") { attempt += 1 }
          }
        }
        if model.deviceBusy && model.checkoutPreview == nil { ProgressView().frame(maxWidth: .infinity) }
        if section == 0 {
          if done { Text("已结账") }
          else if let preview = model.checkoutPreview {
            if let timeline = preview.timeline { ClipBillTimeline(timeline: timeline) }
            else {
              ForEach(preview.chargeItems) { item in PrismLabeledRow(item.label, value: item.amount.formatted(.number.precision(.fractionLength(2)))) }
              ForEach(preview.adjustments) { item in PrismLabeledRow(item.label, value: item.amount.formatted(.number.precision(.fractionLength(2)))) }
            }
          } else if !model.deviceBusy && model.errorMessage == nil && loadError == nil { Text("暂无待结账单") }
        } else if section == 1 {
          if done { Text("兑换成功") } else {
            TextField("兑换码", text: $redeemCode).textInputAutocapitalization(.never).autocorrectionDisabled().padding(18).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.15)))
            Button { Task { await model.redeem(redeemCode.trimmingCharacters(in: .whitespacesAndNewlines)); done = model.errorMessage == nil } } label: {
              HStack { if model.deviceBusy { ProgressView() }; Text("兑换") }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }.clipActionStyle(primary: true).disabled(redeemCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        } else if section == 2 {
          if model.history.isEmpty && !model.deviceBusy && loadError == nil { Text("暂无记录") }
          ForEach(model.history) { item in
            VStack(alignment: .leading, spacing: 6) {
              PrismLabeledRow(prismDate(item.startedAt), value: item.total?.formatted(.number.precision(.fractionLength(2))) ?? "—")
              Text(item.endedAt.map(prismDate) ?? String(localized: "计费中")).font(.caption).foregroundStyle(.secondary)
            }
          }
        } else {
          if model.assets.isEmpty && !model.deviceBusy && loadError == nil { Text("暂无资产") }
          ForEach(model.assets) { item in PrismLabeledRow(item.assetName ?? item.assetCode, value: item.quantity.formatted()) }
        }
      }.disabled(model.deviceBusy).padding(.vertical, 24).padding(.horizontal, horizontalPadding).padding(.bottom, section == 0 && !done ? 100 : 0).frame(maxWidth: 480).frame(maxWidth: .infinity)
      }
      .overlay(alignment: .bottom) {
        if section == 0, !done, model.checkoutPreview != nil {
          checkoutButton.padding(.horizontal, horizontalPadding)
            .frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
      }
    }
    .task(id: attempt) {
      loadError = nil
      do { try await model.loadAccountSection(section) }
      catch {
        guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        loadError = error is URLError ? String(localized: "网络连接失败，请检查网络后重试") : error.localizedDescription
      }
    }
  }
}
private func prismDate(_ value: String) -> String { prismParsedDate(value)?.formatted(date: .numeric, time: .shortened) ?? value }
private func prismTime(_ value: String) -> String { prismParsedDate(value)?.formatted(date: .omitted, time: .standard) ?? value }
private struct PrismLabeledRow: View {
  let title: String; let value: String
  init(_ title: String, value: String) { self.title = title; self.value = value }
  var body: some View { HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(value) }.padding(.vertical, 12) }
}

private func billClock(_ value: String) -> String { prismParsedDate(value)?.formatted(date: .omitted, time: .shortened) ?? value }
private func billEventLabel(_ kind: String) -> String {
  switch kind {
  case "start": return String(localized: "开始计费")
  case "end": return String(localized: "结束计费")
  case "switch": return String(localized: "切换计费规则")
  case "current": return String(localized: "现在")
  default: return ""
  }
}
private struct ClipBillTimeline: View {
  let timeline: PrismBillTimeline
  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(timeline.events.enumerated()), id: \.offset) { index, event in
        ClipBillEvent(event: event, tracks: timeline.tracks, hasNext: index + 1 < timeline.events.count)
      }
    }
  }
}
private struct ClipBillEvent: View {
  let event: PrismBillTimeline.Event
  let tracks: [PrismBillTimeline.Track]
  let hasNext: Bool
  private let colors: [Color] = [.blue, .brown, .purple, .teal, .pink, .orange]
  private var lanes: Int { max(1, (tracks.map(\.lane).max() ?? 0) + 1) }
  private var kinds: Set<String> { Set(event.entries.filter { $0.trackId != nil }.map(\.kind)) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(event.time + (kinds.count == 1 ? " · " + billEventLabel(kinds.first!) : "")).font(.subheadline.bold())
        Spacer(minLength: 8)
        Text(prismParsedDate(event.date + "T12:00:00Z")?.formatted(.dateTime.month().day()) ?? "").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(Array(event.entries.enumerated()), id: \.offset) { _, entry in
        ClipBillEntry(entry: entry, showKind: kinds.count > 1, trackColor: tracks.first(where: { $0.id == entry.trackId }).map { colors[$0.color % colors.count] })
      }
    }
    .padding(.leading, CGFloat(lanes * 14 + 18)).padding(.bottom, 28)
    .background {
      GeometryReader { proxy in
        ForEach(tracks) { track in
          let point = event.entries.contains { $0.trackId == track.id }
          let above = track.endedAt > event.at && track.startedAt <= event.at
          let below = hasNext && track.startedAt < event.at && track.endedAt >= event.at
          let x = CGFloat(track.lane * 14 + 5)
          Path { path in
            if above { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: 11)) }
            if below { path.move(to: CGPoint(x: x, y: 11)); path.addLine(to: CGPoint(x: x, y: proxy.size.height)) }
          }.stroke(colors[track.color % colors.count].opacity(0.7), lineWidth: 3)
          if point { Circle().fill(colors[track.color % colors.count]).frame(width: 9, height: 9).position(x: x, y: 11) }
        }
      }.accessibilityHidden(true)
    }
  }
}
private struct ClipBillEntry: View {
  let entry: PrismBillTimeline.Entry
  let showKind: Bool
  let trackColor: Color?
  private var period: String? {
    guard let start = entry.startedAt, let end = entry.endedAt else { return nil }
    let minutes = Int((prismParsedDate(end)?.timeIntervalSince(prismParsedDate(start) ?? Date()) ?? 0) / 60)
    return (entry.periodLabel ?? (billClock(start) + " – " + billClock(end))) + " · " + minutes.formatted() + " " + String(localized: "分钟")
  }
  private var rate: String? {
    guard let unit = entry.unitMinutes, let price = entry.unitPrice else { return nil }
    return price.formatted() + " / " + unit.formatted() + " " + String(localized: "分钟") + (entry.units.map { " × " + $0.formatted() } ?? "")
  }
  private var cap: String? {
    guard let cap = entry.cap else { return nil }
    let name = entry.trackId == nil ? String(localized: "跨方案封顶") : String(localized: "时段封顶")
    let history = (entry.paidBefore ?? 0) != 0 ? " · " + String(localized: "历史已计入") + " " + entry.paidBefore!.formatted() : ""
    return name + " " + cap.formatted() + history
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline) {
        HStack(spacing: 8) {
          if let trackColor { Circle().fill(trackColor).frame(width: 6, height: 6).accessibilityHidden(true) }
          Text(entry.name).font(.subheadline.weight(.medium))
        }
        Spacer(minLength: 8)
        if let amount = entry.amount {
          Text(amount.formatted(.number.precision(.fractionLength(2)))).font(.subheadline.bold()).monospacedDigit().foregroundStyle(amount < 0 ? Color.green : Color.primary)
        }
      }
      Group {
        if showKind, entry.trackId != nil { Text(billEventLabel(entry.kind)) }
        if let rule = entry.rule { Text(rule + (entry.nextRule.map { " → " + $0 } ?? "")) }
        if let period { Text(period) }
        if let rate { Text(rate) }
        if let cap { Text(cap) }
      }.font(.caption).foregroundStyle(.secondary)
    }.padding(entry.trackId == nil ? 0 : 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(entry.trackId == nil ? Color.clear : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
  }
}
