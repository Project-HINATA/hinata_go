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
    // A problem raised inside the sheet was shown there; it must not pop up once the sheet is gone.
    .sheet(isPresented: Binding(get: { section != nil }, set: { if !$0 { section = nil; model.dismissNotice(retrying: false) } })) {
      if let section {
        if #available(iOS 16.0, *) { ClipAccountSheet(section: section).environmentObject(model).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        else { ClipAccountSheet(section: section).environmentObject(model) }
      }
    }
    .overlay { if model.checkoutCelebrating && section == nil { ClipCheckoutSuccess() } }
    .task(id: model.checkoutCelebrating) {
      guard model.checkoutCelebrating else { return }
      do { try await Task.sleep(nanoseconds: 1_700_000_000) } catch { return }
      section = nil
      await model.finishCheckout()
    }
    .alert("PRiSM", isPresented: $showingError) {
      Button("知道了") { model.clearError() }

    } message: {
      Text(model.errorMessage ?? "")
    }
    .onAppear { Task { await model.setSceneActive(true) } }
    .onDisappear { Task { await model.setSceneActive(false) } }
    .onChange(of: model.errorMessage) { value in
      showingError = value != nil && section == nil
    }
    .modifier(NoticeAlert(model: model, hidden: section != nil))
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
          case .unauthenticated, .loadingCards, .cardsFailed, .ready, .locating, .sending:
            // The card is the content width: the page's own 20-point margins, capped like the
            // stack above. Deriving it here means the cover knows its width on the first
            // layout pass, so it never renders at a provisional size.
            ClipSessionPage(cardWidth: max(0, min(geometry.size.width - 40, 480)))
          }
        }
        .frame(maxWidth: 480)
        .frame(minHeight: max(0, geometry.size.height - 168), alignment: .top)
        .padding(.horizontal, 20)
        // The checkout control is an overlay, so leave enough scrollable tail behind it
        // without reserving an opaque safe-area strip.
        .padding(.bottom, model.isShopOnly && model.state == .ready && model.settlement == nil && model.checkoutPreview != nil ? 120 : 28)
        // In the App Clip the content has to clear the provider notice; in a sheet the toolbar
        // already reserves that space.
        .padding(.top, presentsAppClipNotice ? 140 : 12)
        .frame(maxWidth: .infinity)
      }
    }
    .overlay(alignment: .bottom) {
      if model.isShopOnly, model.state == .ready, model.settlement == nil, model.checkoutPreview != nil {
        ClipCheckoutButton()
          .padding(.horizontal, 24)
          .padding(.bottom, 12)
          .frame(maxWidth: 520)
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
      .disabled(model.deviceBusy || [.loadingCards, .locating, .sending].contains(model.state)).padding(.top, 8).padding(.trailing, 20)
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
      accountMenu(user).disabled(model.deviceBusy || [.loadingCards, .locating, .sending].contains(model.state))
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
    guard let shop = model.shopCode else { return nil }
    return { Task { await model.start(shopCode: shop, publicId: model.publicId) } }
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
  /// Width the shop card will occupy, known before the first layout pass.
  let cardWidth: CGFloat

  var body: some View {
    VStack(spacing: 52) {
      if model.machine != nil || model.visit != nil {
        let name = model.machine?.shop.name ?? model.visit?.shop.name ?? "PRiSM"
        let heroUrl = model.machine?.shop.heroUrl ?? model.visit?.shop.heroUrl
        // While the machine's power is being asked for, the header says so; the page is usable meanwhile.
        let subtitle = model.machine.map { model.checkingPower ? "\($0.name) · \(String(localized: "正在获取电源状态"))" : $0.name }
          ?? model.shopBillingState
        ClipShopHero(name: name, subtitle: subtitle,
                     heroUrl: heroUrl, origin: model.api.baseURL, width: cardWidth)
          .id(model.api.baseURL.absoluteString + (heroUrl ?? ""))
      }
      if model.isShopOnly, !model.shopHasActiveSession, let settlement = model.settlement {
        ClipSettlementPage(settlement: settlement)
      } else {
        sessionBody
      }
    }
  }

  private var sessionBody: some View {
    VStack(spacing: 28) {
      if model.suggestPasskey {
        ClipPasskeySetup()
      } else {
        if model.isShopOnly {
          if [.ready, .locating, .sending].contains(model.state) { ClipShopControls() }
        } else if model.showDeviceControls, [.ready, .locating, .sending].contains(model.state) {
          ClipDeviceControls()
        }
        if !model.isShopOnly, model.canUseCards, [.ready, .locating, .sending].contains(model.state) {
          ZStack(alignment: .trailing) {
            Text(model.cardCapture == nil ? "选择卡片" : "添加卡片").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            if model.machine?.cardCapture == true, model.cardCapture == nil {
              Button { Task { await model.startCardCapture() } } label: {
                Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
              }
              .accessibilityLabel("添加卡片")
              .disabled(model.deviceBusy || model.state != .ready)
            }
          }.padding(.bottom, 2)
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
        case .ready, .locating, .sending:
          if !model.isShopOnly, model.canUseCards {
            if let capture = model.cardCapture { ClipCardCapture(capture: capture, machineName: model.machine?.name ?? "") }
            else { cardsView.disabled(model.deviceBusy) }
          }
          // Stays in place while a card is being sent, so the page does not jump.
          if model.cardCapture == nil, model.deviceState?.gate == "ready", model.deviceState?.power != "off", model.machine?.has("coin") == true, model.machine?.coinAfterSwipe != true {
            // The press answers on the button itself (已投币, 请稍后再投币…) for a moment.
            let coinNote = model.inlineNoticeAnchor == "coin" ? model.inlineNotice : nil
            Button { Task { await model.device("coin") } } label: {
              HStack(spacing: 10) {
                if model.deviceBusy { ProgressView() }
                else { Image(systemName: coinNote.map { noticeSymbol($0.level) } ?? "centsign.circle") }
                if let coinNote { Text(coinNote.body) } else { Text("投币") }
              }
              .foregroundStyle(coinNote.map { noticeColor($0.level) } ?? Color.primary)
              .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.clipActionStyle().disabled(model.deviceBusy || model.state != .ready)
          }
          // A machine without its own controls shows other actions' outcomes here; the coin's is on its button.
          if !model.showDeviceControls { AnchoredNotice(AnchoredNotice.page.subtracting(["coin"])) }
          if model.showNoDeviceActions {
            Text("这里没有可操作的设备").font(.subheadline).foregroundStyle(.secondary)
              .frame(maxWidth: .infinity).multilineTextAlignment(.center)
          }
        case .loadingCards:
          ProgressView().accessibilityLabel(model.isShopOnly ? "正在加载" : "正在加载卡片")
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
            // A swipe's outcome stays on the row the player tapped; nothing else waits for it.
            let feedback = model.cardFeedback?.cardId == card.id ? model.cardFeedback : nil
            Button { Task { await model.login(card: card) } } label: {
              HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(card.label).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                  if let feedback {
                    feedbackText(feedback).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
                  } else {
                    Text(active ? rowDetail(card) : cardEnding(card))
                      .font(.body).foregroundStyle(.secondary)
                  }
                }
                Spacer(minLength: 0)
                if let feedback {
                  Image(systemName: noticeSymbol(feedback.level))
                    .font(.title2).foregroundStyle(noticeColor(feedback.level))
                } else if active && [.locating, .sending].contains(model.state) {
                  ProgressView()
                } else {
                  Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.tertiary)
                }
              }
              .padding(.horizontal, 24).padding(.vertical, 16)
              .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
              .animation(.easeOut(duration: 0.2), value: feedback)
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
    default: return cardEnding(card)
    }
  }

  private func feedbackText(_ feedback: CardFeedback) -> Text {
    feedback.parts.enumerated().reduce(Text(verbatim: "")) { text, item in
      let part = Text(item.element.text).foregroundStyle(noticeColor(item.element.level))
      return item.offset == 0 ? part : text + Text(verbatim: " · ").foregroundStyle(.secondary) + part
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
  /// Width the card occupies, passed in from the page so the cover is sized on the first pass.
  let width: CGFloat
  private var placeholderHeight: CGFloat { width / 1.5 }

  private var url: URL? {
    heroUrl.flatMap { URL(string: $0, relativeTo: origin)?.absoluteURL }
  }

  /// Decoded covers, kept across view identities. `URLCache` only holds the bytes, and decoding
  /// is still asynchronous, so without this the cover fell back to its placeholder whenever the
  /// page was rebuilt — which read as the image shrinking and then growing back.
  private static let decodedCovers = NSCache<NSURL, UIImage>()

  /// The cover to draw: the freshly decoded one, or a previously decoded one for the same URL.
  private var cover: UIImage? {
    guard let url else { return nil }
    return image ?? Self.decodedCovers.object(forKey: url as NSURL)
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
    // The cover is sized from the width the card actually has and the image's own aspect ratio.
    // It must not be allowed to fit against the vertical proposal: the page sets a minHeight
    // from the scroll view's height, so while the layout settles `scaledToFit` re-fitted the
    // image to the smaller of the two proposals, shrinking it and centring it.
    VStack(alignment: .leading, spacing: 0) {
      if let cover {
        Image(uiImage: cover)
          .resizable()
          .frame(width: width, height: width / max(cover.size.width / cover.size.height, 0.01))
          .accessibilityHidden(true)
      } else if url != nil {
        Rectangle()
          .fill(Color.primary.opacity(0.04))
          .frame(width: width, height: placeholderHeight)
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
    // The card owns its width rather than taking it from its widest child. Without this the
    // cover's fixed frame set the width while the bill was absent, and the wider bill changed
    // it on arrival — which resized the cover exactly as the bill appeared.
    .frame(width: width)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 32))
    .overlay {
      RoundedRectangle(cornerRadius: 32).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
    }
    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 8)
    .task(id: url) {
      guard let url else { return }
      // Already decoded: this URL's cover is on screen, so there is nothing to reload. Clearing
      // it here instead is what blanked the image for a frame on every rebuild.
      if let cached = Self.decodedCovers.object(forKey: url as NSURL) {
        image = cached
        return
      }
      image = nil
      do {
        let (data, response) = try await Self.session.data(from: url)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = UIImage(data: data) else {
          Self.session.configuration.urlCache?.removeCachedResponse(for: URLRequest(url: url))
          return
        }
        Self.decodedCovers.setObject(decoded, forKey: url as NSURL)
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
        if model.shopHasActiveSession, let preview = model.checkoutPreview {
          ClipBillContent(preview: preview).padding(.horizontal, 4)
        } else if model.needsPlatformBinding {
          ClipPlatformBinding()
        } else if model.errorMessage != nil {
          Button { Task { model.clearError(); await model.refreshVisit() } } label: {
            Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12)
          }.clipActionStyle()
        } else if !model.playerStateLoaded {
          ProgressView().frame(maxWidth: .infinity).accessibilityLabel("正在加载")
        } else if shop.shop.billingEnabled {
          Text("请碰一下 NFC 或扫描机台上的二维码入场")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
      } else if model.errorMessage != nil {
        Button { Task { model.clearError(); await model.refreshVisit() } } label: {
          Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12)
        }.clipActionStyle()
      } else { ProgressView().accessibilityLabel("正在加载") }
    }.disabled(model.deviceBusy || [.loadingCards, .locating, .sending].contains(model.state))
  }
}

/// A settled bill uses exactly the same totals and timeline as the live preview.
private struct ClipSettlementPage: View {
  let settlement: PrismCheckoutResult
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 12) {
        Image(systemName: "checkmark.circle").foregroundStyle(.green).font(.largeTitle)
        VStack(alignment: .leading, spacing: 4) {
          Text("结账成功").font(.title2.weight(.semibold))
          Text(prismDate(settlement.playerSettlement.settledAt)).font(.caption).foregroundStyle(.secondary)
        }
      }
      ClipBillContent(preview: settlement.bill, balanceAfter: settlement.wallet?.balanceAfter)
    }
  }
}

private struct ClipHistoryRow: View {
  let record: PrismHistory.Record
  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 7) {
        Text(prismDate(record.startedAt ?? record.settledAt)).font(.subheadline.weight(.medium))
        if record.startedAt != nil {
          Text("→ " + prismDate(record.endedAt ?? record.settledAt)).font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 12)
      Text(record.total.formatted(.number.precision(.fractionLength(2)))).font(.title3.weight(.semibold)).monospacedDigit().fixedSize()
      Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
    }.padding(.vertical, 12).contentShape(Rectangle())
    .overlay(alignment: .bottom) { Divider().frame(height: 1) }
  }
}

private struct ClipHistoryDetail: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let record: PrismHistory.Record
  @State private var receipt: PrismCheckoutResult?
  @State private var error: String?
  @State private var attempt = 0
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        if let receipt {
          ClipSettlementPage(settlement: receipt)
        } else if let error {
          Text(error).foregroundStyle(.red)
          Button("重试") { attempt += 1 }
        } else { ProgressView().frame(maxWidth: .infinity).accessibilityLabel("正在加载") }
      }.padding(24).frame(maxWidth: 528).frame(maxWidth: .infinity)
    }
    .navigationTitle("账单详情").navigationBarTitleDisplayMode(.inline)
    .task(id: attempt) {
      error = nil
      do { receipt = try await model.loadCheckoutReceipt(record.id) }
      catch {
        guard !Task.isCancelled, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        self.error = error is URLError ? String(localized: "网络连接失败，请检查网络后重试") : error.localizedDescription
      }
    }
  }
}

private struct ClipCheckoutSuccess: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var circle: CGFloat = 0
  @State private var check: CGFloat = 0
  var body: some View {
    VStack(spacing: 24) {
      ZStack {
        Circle().trim(from: 0, to: circle).stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
        ClipCheckmark().trim(from: 0, to: check).stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
      }.foregroundStyle(.green).frame(width: 96, height: 96).accessibilityHidden(true)
      Text("结账成功").font(.title2.weight(.semibold))
      Text("计费已结束，离店前无需再做其他操作。").font(.subheadline).foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center).padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .accessibilityElement(children: .combine)
    .task {
      if reduceMotion { circle = 1; check = 1; return }
      withAnimation(.easeOut(duration: 0.45)) { circle = 1 }
      do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
      withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { check = 1 }
    }
  }
}
private struct ClipCheckmark: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.width * 0.27, y: rect.height * 0.51))
      path.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.68))
      path.addLine(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.34))
    }
  }
}

private struct ClipPasskeySetup: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  var body: some View {
    VStack(spacing: 24) {
      Text("建议添加 Passkey").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
      Text("下次可用指纹或面容快速登录。此步骤可跳过，不影响继续游玩。")
        .font(.subheadline).foregroundStyle(.secondary)
      Button { Task { await model.addSuggestedPasskey() } } label: {
        HStack(spacing: 10) {
          if model.addingPasskey { ProgressView() } else { Image(systemName: "touchid") }
          Text(model.addingPasskey ? String(localized: "正在添加 Passkey…") : String(localized: "添加 Passkey"))
        }.frame(maxWidth: .infinity).padding(.vertical, 12)
      }.clipActionStyle(primary: true).disabled(model.addingPasskey || model.user == nil)
      Button { model.skipPasskeySetup() } label: {
        Text("跳过，继续游玩").frame(maxWidth: .infinity).padding(.vertical, 12)
      }.clipActionStyle().disabled(model.addingPasskey)
    }
  }
}

private struct ClipPlatformBinding: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @State private var copied = false
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("绑定平台身份").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
      VStack(alignment: .leading, spacing: 18) {
        if let binding = model.binding {
          let lines = prismBindingPromptLines(binding.botContact, code: binding.code) ?? [
            PrismBindingPromptLine(text: String(localized: "向店铺 Bot 发送"), command: false),
            PrismBindingPromptLine(text: "bind \(binding.code)", command: true),
          ]
          ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            if line.command {
              HStack(spacing: 12) {
                Text(verbatim: line.text).font(.system(size: 21, design: .monospaced)).textSelection(.enabled)
                Spacer(minLength: 0)
                Button(copied ? "已复制" : "复制") {
                  UIPasteboard.general.string = line.text
                  copied = true
                  Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = false }
                }.buttonStyle(.bordered)
              }
            } else {
              Text(verbatim: line.text).font(.subheadline)
            }
          }
          Text(String(localized: "有效期至") + " " + prismTime(binding.expiresAt)).font(.caption).foregroundStyle(.secondary)
        }
        if model.errorMessage != nil {
          Button("重试") { Task { await model.bindPlatformIdentity() } }.disabled(model.deviceBusy)
        } else if model.binding == nil { ProgressView() }
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
  }
}

private struct ClipDeviceControls: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @State private var consent = false
  /// Why this resource cannot bill now; confirming is not offered then.
  private var billingError: PrismResourceBilling.Failure? { model.deviceState?.billing?.error }
  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let device = model.deviceState, let shop = model.visit {
        if device.gate == "binding" {
          ClipPlatformBinding()
        } else {
          if device.gate == "entry" {
            VStack(alignment: .leading, spacing: 24) {
              Text(billingError == nil ? "计费规则" : "暂时无法使用").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
              if let billingError {
                Text(billingError.message).font(.subheadline).foregroundStyle(.red)
              } else if let rules = device.billing?.rules {
                ClipResourcePricing(rules: rules, changes: device.billing?.preview)
              } else {
                if let preview = device.billing?.preview { ClipBillingChanges(preview: preview) }
                ClipEntryPricing(shop: shop)
              }
              Button { consent.toggle() } label: {
                HStack(alignment: .top, spacing: 12) {
                  Image(systemName: consent ? "checkmark.square.fill" : "square").foregroundStyle(consent ? Color.blue : .secondary)
                  Text("确认开始计费，离店前请结账。关闭页面不会停止计费。").font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
              }.buttonStyle(.plain).accessibilityValue(consent ? "✓" : "—")
              if model.machine?.has("door") != true {
                Button { Task { await model.enter() } } label: {
                  HStack { if model.deviceBusy { ProgressView() }; Text("确认") }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }.clipActionStyle(primary: true).disabled(!consent || billingError != nil)
                AnchoredNotice(["entry"])
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
            Button {
              Task {
                if device.gate == "entry" { await model.enterAndOpenDoor() }
                else { await model.device("door.open", consent: consent) }
              }
            } label: {
              HStack(spacing: 10) { if model.deviceBusy { ProgressView() } else { Image(systemName: "door.left.hand.open") }; Text(model.doorPassword != nil ? "重新获取密码" : device.gate == "entry" ? "入场并获取开门密码" : "获取开门密码") }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            }.clipActionStyle(primary: true).disabled(device.gate == "entry" && (!consent || billingError != nil))
            AnchoredNotice(["door"])
          }
          if device.gate == "ready", model.machine?.has("climate") == true {
            ClipClimateCard(state: device.climate)
            AnchoredNotice(["climate"])
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
                  .background(seat == nil ? Color.clear : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
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
              AnchoredNotice(["mahjong"])
            }.frame(maxWidth: .infinity)

          }
          if device.gate == "ready", device.power == "off" {
            VStack(spacing: 28) {
              Text("设备尚未开机").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
              Button { Task { await model.device("power.on") } } label: {
                HStack(spacing: 10) { if model.deviceBusy || model.waitingPower { ProgressView() } else { Image(systemName: "power") }; Text("开机") }
                  .frame(maxWidth: .infinity).padding(.vertical, 12)
              }.clipActionStyle(primary: true).disabled(model.waitingPower)
              AnchoredNotice(["power"])
            }.frame(maxWidth: .infinity)
          }
          AnchoredNotice(["binding"])
        }
      } else if model.errorMessage != nil {
        Button { Task { model.clearError(); await model.refreshVisit() } } label: {
          Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12)
        }.clipActionStyle()
      } else { ProgressView().accessibilityLabel("正在加载") }
    }.disabled(model.deviceBusy || [.loadingCards, .locating, .sending].contains(model.state))
  }
}

/// The player's air conditioner, matching the Web device page. Off, it is one button; on,
/// the target temperature is the centre with round − and + either side, and mode and fan
/// speed are segmented rows underneath. The card takes the running mode's colour.
///
/// A choice is shown at once and gives way to what Home Assistant reports, or falls back
/// after a few seconds if it never does. Quick − / + presses are sent as one temperature, so
/// an on-site location fix is not taken for every step.
private struct ClipClimateCard: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let state: PrismClimate?
  @State private var draftMode: String?
  @State private var draftFan: String?
  @State private var draftTemperature: Double?
  @State private var sendTemperature: Task<Void, Never>?
  @State private var expireDraft: Task<Void, Never>?

  private static let modeNames: [String: LocalizedStringKey] = [
    "off": "已关闭", "cool": "制冷", "heat": "制热", "dry": "除湿", "fan_only": "送风", "auto": "自动", "heat_cool": "自动冷暖",
  ]
  private static let modeSymbols: [String: String] = [
    "cool": "snowflake", "heat": "sun.max", "dry": "drop", "fan_only": "fan",
    "auto": "arrow.triangle.2.circlepath", "heat_cool": "arrow.triangle.2.circlepath",
  ]
  private static let fanNames: [String: LocalizedStringKey] = [
    "auto": "自动", "silent": "静音", "quiet": "静音", "low": "低风", "medium": "中风", "middle": "中风",
    "high": "高风", "strong": "强劲", "turbo": "强劲",
  ]
  private func modeName(_ mode: String) -> Text { Self.modeNames[mode].map { Text($0) } ?? Text(verbatim: mode) }
  private func fanName(_ mode: String) -> Text { Self.fanNames[mode.lowercased()].map { Text($0) } ?? Text(verbatim: mode) }

  private var mode: String { draftMode ?? state?.mode ?? "off" }
  private var fanMode: String? { draftFan ?? state?.fanMode }
  private var temperature: Double? { draftTemperature ?? state?.temperature }
  private var isOn: Bool { state?.isOn == true }
  private var busy: Bool { model.deviceBusy || [.locating, .sending].contains(model.state) }

  private var accent: Color {
    guard isOn else { return .secondary }
    switch mode {
    case "heat": return Color(red: 0.91, green: 0.44, blue: 0.16)
    case "dry": return Color(red: 0.10, green: 0.60, blue: 0.54)
    case "fan_only": return Color(red: 0.37, green: 0.45, blue: 0.53)
    case "auto", "heat_cool": return Color(red: 0.48, green: 0.35, blue: 0.84)
    default: return .blue
    }
  }

  private func degrees(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("空调").font(.title3.weight(.semibold))
          status.font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if isOn {
          Button { send("climate.off") } label: {
            Label("关空调", systemImage: "power").font(.subheadline.weight(.semibold))
              .padding(.horizontal, 14).padding(.vertical, 9)
              .background(Color.primary.opacity(0.07), in: Capsule())
          }.buttonStyle(.plain)
        }
      }
      if state == nil {
        HStack(spacing: 10) { powerButton(on: true); powerButton(on: false) }
      } else if !isOn {
        powerButton(on: true)
      } else {
        if let temperature { temperatureRow(temperature) }
        if let state, !state.choosableModes.isEmpty {
          segments(title: "模式", options: state.choosableModes, selected: mode, tall: true) { option in
            if let symbol = Self.modeSymbols[option] { Image(systemName: symbol).font(.system(size: 18)) }
            modeName(option)
          } choose: { option in
            draftMode = option; hold(); send("climate.set_mode", ["mode": option])
          }
        }
        if let fans = state?.fanModes, !fans.isEmpty {
          segments(title: "风速", options: fans, selected: fanMode ?? "", tall: false) { option in
            fanName(option)
          } choose: { option in
            draftFan = option; hold(); send("climate.set_fan_mode", ["fanMode": option])
          }
        }
      }
    }
    .padding(20)
    .background(accent.opacity(isOn ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(accent.opacity(isOn ? 0.18 : 0.08)))
    .animation(.easeInOut(duration: 0.25), value: mode)
    .onChange(of: state) {
      if draftMode == state?.mode { draftMode = nil }
      if draftFan == state?.fanMode { draftFan = nil }
      if draftTemperature == state?.temperature { draftTemperature = nil }
    }
    .onDisappear { sendTemperature?.cancel(); expireDraft?.cancel() }
  }

  private var status: Text {
    guard let state else { return Text("空调状态未知") }
    let room = state.currentTemperature.map { Text(" · ") + Text("室温 \(degrees($0))°") } ?? Text(verbatim: "")
    return (isOn ? modeName(mode) : Text("已关闭")) + room
  }

  private func powerButton(on: Bool) -> some View {
    Button { send(on ? "climate.on" : "climate.off") } label: {
      HStack(spacing: 10) {
        if busy { ProgressView() } else { Image(systemName: "power") }
        Text(on ? "开空调" : "关空调")
      }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }.clipActionStyle(primary: on)
  }

  private func temperatureRow(_ value: Double) -> some View {
    HStack(spacing: 12) {
      round("minus", label: "调低温度", disabled: value <= (state?.minTemperature ?? 16)) { nudge(-1) }
      Spacer(minLength: 0)
      VStack(spacing: 2) {
        HStack(alignment: .top, spacing: 2) {
          Text(verbatim: degrees(value)).font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText(value: value))
          Text(verbatim: "°").font(.system(size: 30, weight: .light, design: .rounded)).padding(.top, 6)
        }.foregroundStyle(accent)
        Text("设定温度").font(.footnote).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      round("plus", label: "调高温度", disabled: value >= (state?.maxTemperature ?? 30)) { nudge(1) }
    }
    .animation(.snappy, value: value)
  }

  private func round(_ symbol: String, label: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.title2.weight(.medium)).foregroundStyle(accent)
        .frame(width: 56, height: 56)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
    .buttonStyle(.plain)
    .opacity(disabled ? 0.35 : 1)
    .disabled(disabled)
    .accessibilityLabel(label)
  }

  private func segments<Content: View>(
    title: LocalizedStringKey, options: [String], selected: String, tall: Bool,
    @ViewBuilder label: @escaping (String) -> Content, choose: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
      // Up to six options share one row; a longer list wraps instead of crushing labels.
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(options.count, 6)), spacing: 4) {
        ForEach(options, id: \.self) { option in
          let on = option == selected
          Button { if !on { choose(option) } } label: {
            VStack(spacing: 4) { label(option) }
              .font(tall ? .footnote : .subheadline).fontWeight(on ? .semibold : .regular)
              .lineLimit(1).minimumScaleFactor(0.8)
              .frame(maxWidth: .infinity, minHeight: tall ? 56 : 42)
              .foregroundStyle(on ? accent : Color.primary.opacity(0.7))
              .background(on ? Color(uiColor: .secondarySystemGroupedBackground) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
              .shadow(color: .black.opacity(on ? 0.1 : 0), radius: 3, y: 1)
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(on ? .isSelected : [])
        }
      }
      .padding(4)
      .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .accessibilityElement(children: .contain)
      .accessibilityLabel(title)
    }
  }

  private func send(_ action: String, _ extra: [String: Any] = [:]) {
    Task { await model.climate(action, extra) }
  }

  /// Keep a choice on screen while Home Assistant catches up, but not forever.
  private func hold() {
    expireDraft?.cancel()
    expireDraft = Task {
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      draftMode = nil; draftFan = nil; draftTemperature = nil
    }
  }

  private func nudge(_ direction: Int) {
    guard let state, let current = temperature else { return }
    let next = state.nudged(current, by: direction)
    guard next != current else { return }
    draftTemperature = next
    hold()
    sendTemperature?.cancel()
    sendTemperature = Task {
      // Presses are gathered: each one starts the wait again, so stepping through several
      // degrees sends one request instead of one per press.
      try? await Task.sleep(for: .milliseconds(1000))
      // A press made while another action runs waits for it rather than being dropped.
      while !Task.isCancelled && busy { try? await Task.sleep(for: .milliseconds(200)) }
      guard !Task.isCancelled, let wanted = draftTemperature else { return }
      hold()
      await model.climate("climate.set_temperature", ["temperature": wanted])
    }
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
            ClipPricingRow(rule: rule, sourceZone: plan.provider.timeZone ?? "UTC", displayZone: shop.shop.timeZone, referenceDate: shop.pricingSchedule?.localDate ?? String(ISO8601DateFormatter().string(from: Date()).prefix(10)), segments: shop.pricingSchedule?.groups.first(where: { $0.id == plan.id })?.segments.filter { $0.ruleId == rule.id && $0.isClosed != true } ?? [])
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

/// What confirming starts, ends and keeps, for a server that has no rules to show; a plan kept
/// running keeps its timer.
private struct ClipBillingChanges: View {
  let preview: PrismResourceBilling.Preview
  var body: some View {
    let rows: [(LocalizedStringKey, [PrismResourceBilling.Change])] = [("新增方案", preview.started), ("结束方案", preview.stopped), ("保留方案", preview.kept)]
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        if !row.1.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(row.0).foregroundStyle(.secondary)
            Text(row.1.map(\.planName).joined(separator: "、")).fontWeight(.medium)
          }
        }
      }
    }.font(.subheadline)
  }
}

/// Adding a card at the cabinet's reader: waiting for the card, then what came of it.
private struct ClipCardCapture: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let capture: MachineLoginViewModel.CardCapture
  let machineName: String
  var body: some View {
    VStack(spacing: 16) {
      switch capture {
      case .starting, .waiting:
        ProgressView().controlSize(.large)
        Text(capture == .starting ? String(localized: "正在连接机台…") : String(format: String(localized: "请把卡片放在「%@」的读卡器上"), machineName))
          .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button { model.dismissCardCapture() } label: { Text("取消").frame(maxWidth: .infinity).padding(.vertical, 12) }.clipActionStyle()
      case .done(let level, let message):
        Image(systemName: noticeSymbol(level)).font(.largeTitle).foregroundStyle(noticeColor(level))
        Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button { model.dismissCardCapture() } label: { Text("完成").frame(maxWidth: .infinity).padding(.vertical, 12) }.clipActionStyle()
      }
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
    .accessibilityElement(children: .contain)
  }
}

private struct ClipPricingRow: View {
  let rule: PrismShopResponse.Pricing.Rule
  let sourceZone: String
  let displayZone: String
  let referenceDate: String
  let segments: [PrismPricingSchedule.Segment]
  private var projected: PrismRuleClock? {
    guard let range = rule.timeRange else { return nil }
    return prismRuleClock(start: range.start, end: range.end, sourceZone: sourceZone, displayZone: displayZone, referenceDate: referenceDate)
  }
  private var period: String {
    if !segments.isEmpty {
      return segments.map { segment in
        // Day previews already carry store-local labels and exact UTC-offset instants.
        segment.startLabel + "–" + segment.endLabel
      }.joined(separator: " / ")
    }
    guard let time = rule.timeRange else { return String(localized: "连续时段") }
    if time.start == time.end { return String(localized: "全天") }
    guard let projected else { return "—" }
    return projected.start + "–" + (projected.start > projected.end ? String(localized: "次日") : "") + projected.end
  }
  private func prismRuleDateTime(_ value: String) -> String {
    guard let date = prismParsedDate(value) else { return "—" }
    let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: displayZone) ?? TimeZone(secondsFromGMT: 0)
    formatter.dateStyle = .short; formatter.timeStyle = .short
    return formatter.string(from: date)
  }
  private var rateText: String {
    if let rate = rule.pricing { return "\(rate.unitPrice.formatted()) / \(rate.unitMinutes.formatted()) " + String(localized: "分钟") }
    return String(localized: "合计封顶") + " " + (rule.priceCap?.formatted() ?? "—")
  }
  private var weekdays: String {
    let formatter = DateFormatter()
    return (rule.weekdays ?? []).filter { (0...6).contains($0) }.map { formatter.shortWeekdaySymbols[($0 + (projected?.dayShift ?? 0) + 7) % 7] }.joined(separator: " · ")
  }
  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      Text(period).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
      VStack(alignment: .leading, spacing: 6) {
        Text(rule.label).font(.subheadline.bold())
        if !weekdays.isEmpty { Text(weekdays).font(.caption).foregroundStyle(.secondary) }
        if let dates = rule.specificDates, !dates.isEmpty { Text(dates.map { date in
          guard let range = rule.timeRange, let clock = prismRuleClock(start: range.start, end: range.end, sourceZone: sourceZone, displayZone: displayZone, referenceDate: date) else { return date }
          let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: displayZone); formatter.dateFormat = "yyyy-MM-dd"
          return formatter.string(from: clock.startDate)
        }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
        if let dates = rule.dateTimeRange { Text(prismRuleDateTime(dates.start) + " – " + prismRuleDateTime(dates.end)).font(.caption).foregroundStyle(.secondary) }
        Text(rateText).font(.subheadline)
        if let pricing = rule.pricing {
          // A cap of 0 leaves the period uncapped.
          if pricing.priceCap > 0, pricing.priceCap < 9007199254740991 { Text(String(localized: "时段封顶") + " " + pricing.priceCap.formatted()).font(.caption).foregroundStyle(.secondary) }
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
      .environment(\.prismCardFill, Color(.tertiarySystemFill))
      .overlay { if model.checkoutCelebrating { ClipCheckoutSuccess() } }
      .interactiveDismissDisabled(model.deviceBusy || model.checkoutCelebrating)
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          closeButton.disabled(model.deviceBusy || model.checkoutCelebrating)
        }
      }
  }
}

/// Account sheet owns scrolling and loading. Inline shop bills reuse only ClipBillContent.
private struct ClipAccountContent: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let section: Int
  private let horizontalPadding: CGFloat = 24
  @State private var redeemCode = ""
  @State private var done = false
  @State private var loadError: String?
  @State private var attempt = 0
  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        // A section that could not load offers to load again. An action's problem is shown
        // by that action instead: above the checkout button, or under the code field.
        if let error = loadError ?? (section == 0 ? nil : model.errorMessage ?? model.dialogNotice?.body) {
          VStack(alignment: .leading, spacing: 8) {
            Text(error).font(.subheadline).foregroundStyle(.red)
            if loadError != nil { Button("重新加载") { attempt += 1 } }
          }
        }
        if model.deviceBusy && model.checkoutPreview == nil { ProgressView().frame(maxWidth: .infinity) }
        if section == 0 {
          if let preview = model.checkoutPreview {
            ClipBillContent(preview: preview)
            // An empty bill is only claimed once a read has actually returned one: the page is
            // rebuilt during entry, so saying it from `checkoutPreview == nil` alone flashed
            // "暂无待结账单" between two reads.
          } else if !model.deviceBusy && model.billLoaded && model.errorMessage == nil && loadError == nil {
            Text("暂无待结账单")
          }
        } else if section == 1 {
          if done { Text("兑换成功") } else {
            TextField("兑换码", text: $redeemCode).textInputAutocapitalization(.never).autocorrectionDisabled().padding(18).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.15)))
            Button { Task { done = await model.redeem(redeemCode.trimmingCharacters(in: .whitespacesAndNewlines)) } } label: {
              HStack { if model.deviceBusy { ProgressView() }; Text("兑换") }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }.clipActionStyle(primary: true).disabled(redeemCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            AnchoredNotice(["redeem"])
          }
        } else if section == 2 {
          if model.history.isEmpty && !model.deviceBusy && loadError == nil {
            VStack(spacing: 16) { Image(systemName: "doc.text").font(.largeTitle); Text("暂无结账记录") }
              .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 40)
          }
          ForEach(model.history) { item in
            NavigationLink { ClipHistoryDetail(record: item) } label: { ClipHistoryRow(record: item) }.buttonStyle(.plain)
          }
          if model.historyNextOffset != nil { Button("加载更多") { Task { await model.loadMoreHistory() } }.frame(maxWidth: .infinity) }
        } else {
          if model.assets.isEmpty && !model.deviceBusy && loadError == nil { Text("暂无资产") }
          ForEach(model.assets) { item in PrismLabeledRow(item.assetName ?? item.assetCode, value: item.quantity.formatted()) }
        }
      }.disabled(model.deviceBusy).padding(.vertical, 24).padding(.horizontal, horizontalPadding).padding(.bottom, section == 0 && !done ? 100 : 0).frame(maxWidth: 480).frame(maxWidth: .infinity)
      }
      .overlay(alignment: .bottom) {
        if section == 0, !done, model.checkoutPreview != nil {
          ClipCheckoutButton(inSheet: true).padding(.horizontal, horizontalPadding)
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
/// Shared by the machine account sheet and the shop page; no scroll view or load task.
private struct ClipBillContent: View {
  let preview: PrismCheckout
  var balanceAfter: Double? = nil
  @Environment(\.prismCardFill) private var cardFill
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      ClipBillTotal(total: preview.settlementPreview.total, timeline: preview.timeline)
        .frame(maxWidth: 480, alignment: .leading).padding(.bottom, 4)
      if let balanceAfter {
        PrismLabeledRow(String(localized: "结账后余额"), value: balanceAfter.formatted(.number.precision(.fractionLength(2))))
          .font(.subheadline).padding(.horizontal, 16)
          .background(cardFill, in: RoundedRectangle(cornerRadius: 16))
      }
      if let timeline = preview.timeline { ClipBillTimeline(timeline: timeline) }
      else {
        ForEach(preview.chargeItems) { item in PrismLabeledRow(item.label, value: item.amount.formatted(.number.precision(.fractionLength(2)))) }
        ForEach(preview.adjustments) { item in PrismLabeledRow(item.label, value: item.amount.formatted(.number.precision(.fractionLength(2)))) }
      }
    }
  }
}

private struct ClipCheckoutButton: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  var onSuccess: () -> Void = {}
  /// In the account sheet alerts are held back, so the problem is written above the button.
  var inSheet = false
  var body: some View {
    VStack(spacing: 12) {
      if inSheet, let message = model.errorMessage ?? model.dialogNotice?.body {
        Text(message).font(.subheadline.weight(.semibold)).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
          .task(id: message) {
            // Like every other outcome, it goes away after a moment.
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            model.clearError(); model.dismissNotice(retrying: false)
          }
      }
      AnchoredNotice(["checkout"])
      Button {
        Task {
          await model.checkout()
          if model.settlement != nil { onSuccess() }
        }
      } label: {
        HStack { if model.deviceBusy { ProgressView() }; Text("结账") }
          .frame(maxWidth: .infinity).padding(.vertical, 12)
      }
      .clipActionStyle(primary: true)
      .disabled(model.deviceBusy)
    }
  }
}

private func prismDate(_ value: String) -> String { prismDisplayDate(value) }
private func prismTime(_ value: String) -> String { prismDisplayClock(value, seconds: true) }
private struct PrismLabeledRow: View {
  let title: String; let value: String
  init(_ title: String, value: String) { self.title = title; self.value = value }
  var body: some View { HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(value) }.padding(.vertical, 12) }
}

/// The symbol of a notice level, shared by the card row, the coin button and the controls.
func noticeSymbol(_ level: String) -> String {
  switch level {
  case "success": return "checkmark.circle"
  case "error": return "xmark.circle"
  case "info": return "info.circle"
  default: return "exclamationmark.circle"
  }
}

/// The colour of a notice level, shared by the card row and the controls. Success takes the
/// app's accent blue; info stays quiet.
func noticeColor(_ level: String) -> Color {
  switch level {
  case "success": return .blue
  case "warning": return .orange
  case "error": return .red
  default: return .secondary
  }
}

/// A server notice that interrupts: its own title, body and buttons. Hidden while an
/// account sheet is up, which shows the text inline instead.
private struct NoticeAlert: ViewModifier {
  @ObservedObject var model: MachineLoginViewModel
  let hidden: Bool

  func body(content: Content) -> some View {
    content.background {
      Color.clear.alert(
        model.dialogNotice.map { $0.title ?? $0.body } ?? "",
        isPresented: Binding(
          get: { model.dialogNotice != nil && !hidden },
          set: { if !$0 { model.dismissNotice(retrying: false) } }
        ),
        presenting: model.dialogNotice
      ) { notice in
        ForEach(buttons(notice), id: \.self) { action in
          Button(action.label, role: action.kind == "retry" ? nil : .cancel) {
            model.dismissNotice(retrying: action.kind == "retry")
          }
        }
      } message: { notice in
        if notice.title != nil { Text(notice.body) }
      }
    }
  }

  private func buttons(_ notice: PrismNotice) -> [PrismNotice.Action] {
    let shown = notice.actions.filter { $0.kind != "retry" || model.canRetryNotice }
    return shown.isEmpty ? [.init(kind: "dismiss", label: String(localized: "知道了"))] : shown
  }
}

/// An action's expected outcome, shown where the player acted instead of in an alert:
/// a coloured line with its icon, no box around it.
struct InlineNotice: View {
  let notice: PrismNotice
  var body: some View {
    Label {
      Text(notice.body)
    } icon: {
      Image(systemName: noticeSymbol(notice.level))
    }
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(noticeColor(notice.level))
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityAddTraits(.updatesFrequently)
  }
}

/// The current inline notice, when it belongs to one of these controls.
private struct AnchoredNotice: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let anchors: Set<String>
  init(_ anchors: Set<String>) { self.anchors = anchors }
  /// Every control on the page itself; the account sheet shows its own.
  static let page: Set<String> = ["coin", "power", "door", "climate", "mahjong", "entry", "binding"]
  var body: some View {
    if let note = model.inlineNotice, anchors.contains(model.inlineNoticeAnchor) { InlineNotice(notice: note) }
  }
}
