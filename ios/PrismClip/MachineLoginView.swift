import SwiftUI

struct MachineLoginView: View {
  var allowsDismiss = false
  /// Set when this is the App Clip root: the top of the screen belongs to the system provider
  /// notice, so the controls stay floating above the pushed-down content. The main app presents
  /// this as a page sheet instead, where both controls belong in a navigation toolbar.
  var presentsAppClipNotice = false
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var model: MachineLoginViewModel
  @StateObject private var pageForm = ClipPageFormState()
  @State private var activeTab: PrismPageAccountTab?

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
    .overlay(alignment: .top) {
      if activeTab == nil {
        ClipToast(notice: model.inlineNotice?.presentation == "toast" ? model.inlineNotice : model.errorMessage.map {
          PrismNotice(code: "CLIENT", level: "error", display: "inline", presentation: "toast", flow: "none", body: $0)
        }) {
          model.dismissToast()
        }
          .padding(.top, 8)
          .animation(.easeInOut(duration: 0.2), value: model.inlineNotice)
      }
    }
    // A problem raised inside the sheet was shown there; it must not pop up once the sheet is gone.
    .sheet(item: $activeTab, onDismiss: {
      if activeTab == nil {
        model.closeAccountSheet()
        model.dismissNotice(retrying: false)
      }
    }) { tab in
      if #available(iOS 16.0, *) { ClipAccountSheet(tab: tab).environmentObject(model).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
      else { ClipAccountSheet(tab: tab).environmentObject(model) }
    }
    .overlay { if model.checkoutCelebrating && activeTab == nil { ClipCheckoutSuccess(celebration: model.celebration) } }
    .task(id: model.checkoutCelebrating) {
      guard model.checkoutCelebrating else { return }
      do { try await Task.sleep(nanoseconds: 1_700_000_000) } catch { return }
      activeTab = nil
      model.finishCheckoutInBackground()
    }
    .task(id: model.errorMessage) {
      guard model.errorMessage != nil else { return }
      do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
      model.clearError()
    }
    .onAppear { Task { await model.setSceneActive(true) } }
    .onDisappear { Task { await model.setSceneActive(false) } }
    .onChange(of: model.user?.id) {
      if model.user == nil { activeTab = nil }
    }
    .onChange(of: model.shopCode) {
      activeTab = nil
    }
    .modifier(NoticeAlert(model: model, hidden: activeTab != nil))
  }

  private var hasMainFooter: Bool {
    !model.checkoutCelebrating
      && !model.suggestPasskey
      && !model.cardsLoadFailed
      && [.ready, .locating, .sending].contains(model.state)
      && !(model.page?.footer ?? []).isEmpty
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
            ClipSessionPage(cardWidth: max(0, min(geometry.size.width - 40, 480)), form: pageForm)
          }
        }
        .frame(maxWidth: 480)
        .frame(minHeight: max(0, geometry.size.height - 168), alignment: .top)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        // In the App Clip the content has to clear the provider notice; in a sheet the toolbar
        // already reserves that space.
        .padding(.top, presentsAppClipNotice ? 140 : 12)
        .frame(maxWidth: .infinity)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if hasMainFooter, let page = model.page {
        ClipPageFooter(page: page, form: pageForm)
          .padding(.horizontal, 24)
          .padding(.bottom, 12)
          .frame(maxWidth: 520)
          .frame(maxWidth: .infinity)
          .padding(.top, 12)
          .background(Color(.systemGroupedBackground))
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
    let menu = model.page?.accountMenu
    let badge = menu != nil ? menu?.billingBadge : (model.summary?.activeSession != nil ? String(localized: "计费中") : nil)
    let tabs: [PrismPageAccountTab] = menu?.tabs ?? (
      model.visit?.shop.billingEnabled == true
        ? (model.isShopOnly
            ? [.init(id: "redeem", label: String(localized: "兑换")), .init(id: "history", label: String(localized: "记录")), .init(id: "wallet", label: String(localized: "钱包"))]
            : [.init(id: "bill", label: String(localized: "账单")), .init(id: "redeem", label: String(localized: "兑换")), .init(id: "history", label: String(localized: "记录")), .init(id: "wallet", label: String(localized: "钱包"))])
        : []
    )
    let logoutLabel = menu?.logoutLabel ?? String(localized: "退出登录")
    return Menu {
      ForEach(tabs) { tab in
        Button(tab.label) { activeTab = tab }
      }
      Button(logoutLabel) { Task { await model.logout() } }
    } label: {
      HStack(spacing: 8) {
        if let badge {
          Circle().fill(.green).frame(width: 6, height: 6)
          Text(verbatim: badge).font(.caption).foregroundStyle(.secondary)
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
  @ObservedObject var form: ClipPageFormState

  var body: some View {
    VStack(spacing: 52) {
      if model.machine != nil || model.visit != nil || model.page != nil || model.lastShopHero != nil {
        let name = model.page?.shop ?? model.machine?.shop.name ?? model.lastShopHero?.name ?? model.visit?.shop.name ?? "PRiSM"
        let heroUrl = model.page?.heroUrl ?? model.machine?.shop.heroUrl ?? model.lastShopHero?.heroUrl ?? model.visit?.shop.heroUrl
        let subtitle = model.isShopOnly
          ? (model.page?.resource ?? model.shopBillingState)
          : (model.machine?.name ?? model.page?.resource ?? "")
        ClipShopHero(name: name, subtitle: subtitle,
                     heroUrl: heroUrl, origin: model.api.baseURL, width: cardWidth)
          .id(model.api.baseURL.absoluteString + (heroUrl ?? ""))
      }
      sessionBody
    }
  }

  private var sessionBody: some View {
    VStack(spacing: 28) {
      if model.suggestPasskey {
        ClipPasskeySetup()
      } else {
        if model.slowNetwork { ClipSlowNetwork() }
        if [.ready, .locating, .sending].contains(model.state)
          || (model.state == .unauthenticated && model.page != nil) {
          pageBlocks
        }

        switch model.state {
        case .unauthenticated:
          if model.page == nil {
            ClipSignInButtons(methods: ClipSignInButtons.standard)
          }
        case .ready, .locating, .sending:
          EmptyView()
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
      ClipPage(page: page, form: form)
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

private struct ClipCheckoutSuccess: View {
  let celebration: PrismPageCelebration?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var circle: CGFloat = 0
  @State private var check: CGFloat = 0
  var body: some View {
    VStack(spacing: 24) {
      ZStack {
        Circle().trim(from: 0, to: circle).stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
        ClipCheckmark().trim(from: 0, to: check).stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
      }.foregroundStyle(.green).frame(width: 96, height: 96).accessibilityHidden(true)
      Text(verbatim: celebration?.title ?? String(localized: "结账成功")).font(.title2.weight(.semibold))
      Text(verbatim: celebration?.subtitle ?? String(localized: "计费已结束，离店前无需再做其他操作。")).font(.subheadline).foregroundStyle(.secondary)
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
  let tab: PrismPageAccountTab
  @StateObject private var sheetForm = ClipPageFormState()
  /// Kept across the dismissal transition so the celebration stays solid while the sheet slides down.
  @State private var frozenCelebration: PrismPageCelebration? = nil

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
    .environment(\.prismInSheet, true)
  }

  private var sheetTitle: String {
    if let title = model.sheetPage?.title, !title.isEmpty { return title }
    return tab.label
  }

  private var content: some View {
    ClipAccountContent(tab: tab, form: sheetForm)
      .overlay {
        if model.checkoutCelebrating || frozenCelebration != nil {
          ClipCheckoutSuccess(celebration: model.celebration ?? frozenCelebration)
        }
      }
      .onChange(of: model.checkoutCelebrating, initial: true) {
        if model.checkoutCelebrating {
          frozenCelebration = model.celebration ?? PrismPageCelebration(
            title: String(localized: "结账成功"),
            subtitle: String(localized: "计费已结束，离店前无需再做其他操作。"),
            effect: "checkout"
          )
        }
      }
      .onChange(of: model.sheetStack.isEmpty) { wasEmpty, isEmpty in
        if !wasEmpty && isEmpty && !model.checkoutCelebrating && frozenCelebration == nil {
          dismiss()
        }
      }
      .interactiveDismissDisabled(model.sheetBusy || model.deviceBusy || model.checkoutCelebrating)
      .navigationTitle(sheetTitle)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if model.sheetStack.count > 1 {
          let backLabel = model.sheetPage?.backLabel.flatMap { $0.isEmpty ? nil : $0 }
          ToolbarItem(placement: .topBarLeading) {
            Button {
              Task { await model.popSheetTarget() }
            } label: {
              if let backLabel {
                HStack(spacing: 4) {
                  Image(systemName: "chevron.left")
                  Text(verbatim: backLabel)
                }
              } else {
                Image(systemName: "chevron.left")
              }
            }
            .accessibilityLabel(backLabel ?? String(localized: "返回"))
            .disabled(model.sheetBusy || model.checkoutCelebrating)
          }
        }
        ToolbarItem(placement: .topBarTrailing) {
          closeButton.disabled(model.sheetBusy || model.deviceBusy || model.checkoutCelebrating)
        }
      }
  }
}

private struct ClipAccountContent: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let tab: PrismPageAccountTab
  @ObservedObject var form: ClipPageFormState
  private let horizontalPadding: CGFloat = 24

  private var hasFooter: Bool {
    !model.checkoutCelebrating && !(model.sheetPage?.footer ?? []).isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollViewReader { scroller in
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          if !hasFooter, let error = model.sheetError {
            VStack(alignment: .leading, spacing: 8) {
              Text(verbatim: error).font(.subheadline).foregroundStyle(.red)
              if model.sheetPage == nil {
                Button("重试") { Task { await model.reloadAccountSheet() } }
              }
            }
          }
          if model.sheetLoading && model.sheetPage == nil {
            ProgressView().frame(maxWidth: .infinity).accessibilityLabel("正在加载")
          }
          if let sheetPage = model.sheetPage {
            ClipPage(page: sheetPage, form: form, sheetMode: true)
          }
        }
        .disabled(model.sheetBusy)
        .padding(.vertical, 28)
        .padding(.horizontal, horizontalPadding)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
      }
      // Back from a record: the list as it was left, scrolled to that record.
      .onChange(of: model.sheetReturnAnchor) { _, anchor in
        guard let anchor else { return }
        DispatchQueue.main.async { scroller.scrollTo(anchor, anchor: .center) }
      }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if hasFooter, let sheetPage = model.sheetPage {
          VStack(spacing: 12) {
            if let error = model.sheetError {
              Text(verbatim: error)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .task(id: error) {
                  do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                  model.clearSheetError()
                }
            }
            ClipPageFooter(page: sheetPage, form: form, sheetMode: true)
          }
          .padding(.horizontal, horizontalPadding)
          .padding(.bottom, 12)
          .frame(maxWidth: 480)
          .frame(maxWidth: .infinity)
          .padding(.top, 12)
          .background(Color(.systemGroupedBackground))
        }
      }
    }
    .overlay(alignment: .top) {
      ClipToast(notice: model.sheetInlineNotice) {
        model.dismissToast(sheet: true)
      }
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.2), value: model.sheetInlineNotice)
    }
    .modifier(NoticeAlert(model: model, hidden: false))
    .task(id: tab.id) {
      await model.openAccountSheet(view: tab.id)
    }
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
