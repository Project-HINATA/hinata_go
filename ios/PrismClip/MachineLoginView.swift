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
          case .unauthenticated, .loadingCards, .ready, .locating, .sending:
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
  @EnvironmentObject private var model: MachineLoginViewModel
  var body: some View {
    VStack(spacing: 16) {
      ProgressView().accessibilityLabel("正在加载")
      if model.slowNetwork { ClipSlowNetwork() }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct ClipSlowNetwork: View {
  var body: some View {
    Text("网络较慢，正在重试").font(.subheadline).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity).multilineTextAlignment(.center)
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
        let subtitle = model.machine?.name ?? model.shopBillingState
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
        if model.slowNetwork { ClipSlowNetwork() }
        if model.isShopOnly {
          if [.ready, .locating, .sending].contains(model.state) { ClipShopControls() }
        } else if [.ready, .locating, .sending].contains(model.state)
          || (model.state == .unauthenticated && model.page != nil) {
          pageBlocks
        }

        switch model.state {
        case .unauthenticated:
          if model.isShopOnly || model.page == nil {
            ClipSignInButtons(methods: ClipSignInButtons.standard)
          }
        case .ready, .locating, .sending:
          // Every outcome on a scanned page shows under its own block.
          if model.isShopOnly { AnchoredNotice(AnchoredNotice.page) }
        case .loadingCards:
          ProgressView().accessibilityLabel(model.isShopOnly ? "正在加载" : "正在加载卡片")
        case .idle, .loadingMachine, .loadingShop, .failed, .completed, .expired:
          EmptyView()
        }
      }
    }
  }

  /// What the platform says this page is.
  @ViewBuilder private var pageBlocks: some View {
    if let page = model.page {
      ClipPage(page: page)
    } else if model.errorMessage != nil {
      Button { Task { model.clearError(); await model.refreshVisit() } } label: {
        Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12)
      }.clipActionStyle()
    } else { ProgressView().frame(maxWidth: .infinity).accessibilityLabel("正在加载") }
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
        // The cover's own colours, blurred, under the name: drawn from `cover` so a cover shown
        // from the decoded cache gets its colours at once too, not after the reload task runs.
        if let cover {
          GeometryReader { geometry in
            Image(uiImage: cover).resizable().scaledToFill()
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
    // Always opaque, even where `prismCardFill` would turn translucent in a sheet: the blurred
    // cover under the name is a faint 22% wash, which only shows on a solid card.
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
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

/// What replaces the device controls on a shop link. Admission is not offered here: entry
/// proves physical presence, and only a scanned machine ticket does that, so a player who has
/// not checked in is pointed at the machine QR instead. A shop no longer has a billing switch
/// (each resource group bills or not), so the pointer shows whenever no bill is running.
private struct ClipShopControls: View {
  @EnvironmentObject private var model: MachineLoginViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 28) {
      if let shop = model.visit {
        if model.shopHasActiveSession, let preview = model.checkoutPreview {
          ClipBillContent(preview: preview).padding(.horizontal, 4)
        } else if model.needsPlatformBinding {
          ClipPlatformBinding(labels: .shopLink)
        } else if model.errorMessage != nil {
          Button { Task { model.clearError(); await model.refreshVisit() } } label: {
            Text("重试").frame(maxWidth: .infinity).padding(.vertical, 12)
          }.clipActionStyle()
        } else if !model.playerStateLoaded {
          ProgressView().frame(maxWidth: .infinity).accessibilityLabel("正在加载")
        } else {
          Text("请碰一下 NFC 或扫描机台上的二维码")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(prismCardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
    Group {
      if #available(iOS 26.0, *) {
        NavigationStack { content }
          .presentationCornerRadius(nil)
      } else if #available(iOS 16.0, *) {
        NavigationStack { content }
      } else {
        NavigationView { content }.navigationViewStyle(.stack)
      }
    }
    // Set outside the navigation stack, so pushed pages such as a bill's detail are in it too.
    .environment(\.prismInSheet, true)
  }
  private var content: some View {
    ClipAccountContent(section: section)
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
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      ClipBillTotal(total: preview.settlementPreview.total, timeline: preview.timeline)
        .frame(maxWidth: 480, alignment: .leading).padding(.bottom, 4)
      if let balanceAfter {
        PrismLabeledRow(String(localized: "结账后余额"), value: balanceAfter.formatted(.number.precision(.fractionLength(2))))
          .font(.subheadline).padding(.horizontal, 16)
          .background(prismCardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
private struct PrismLabeledRow: View {
  let title: String; let value: String
  init(_ title: String, value: String) { self.title = title; self.value = value }
  var body: some View { HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(value) }.padding(.vertical, 12) }
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
