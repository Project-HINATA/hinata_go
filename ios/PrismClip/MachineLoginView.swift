import SwiftUI

struct MachineLoginView: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @State private var showingError = false
  @State private var section: Int?

  var body: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 28) {
          switch model.state {
          case .idle, .loadingMachine:
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
        // Keep device content below the App Clip provider notice; the menu stays at the top.
        .padding(.top, 140)
        .frame(maxWidth: .infinity)
      }
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .overlay(alignment: .topTrailing) {
      if let user = model.user {
        Group {
          if #available(iOS 26.0, *) { accountMenu(user).buttonStyle(.glass).buttonBorderShape(.capsule) }
          else { accountMenu(user).buttonStyle(.bordered).buttonBorderShape(.capsule) }
        }
        .disabled(model.deviceBusy || [.locating, .sending].contains(model.state)).padding(.top, 8).padding(.trailing, 20)
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

  private func accountMenu(_ user: PrismUser) -> some View {
    Menu {
      if model.visit?.shop.billingEnabled == true {
        Button("账单") { section = 0 }; Button("兑换") { section = 1 }; Button("记录") { section = 2 }; Button("钱包") { section = 3 }
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

private struct ClipSessionPage: View {
  @EnvironmentObject private var model: MachineLoginViewModel

  var body: some View {
    VStack(spacing: 52) {
      if let machine = model.machine {
        ClipShopHero(shop: machine.shop, machineName: machine.name, origin: model.api.baseURL).id(machine.shop.heroUrl)

      }

      VStack(spacing: 28) {
        if model.showDeviceControls, [.ready, .locating, .sending, .success].contains(model.state) { ClipDeviceControls() }
        if model.canUseCards && [.ready, .locating, .sending, .success].contains(model.state) {
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
          if model.canUseCards { cardsView.disabled(model.deviceBusy) }
          if model.state == .ready, model.deviceState?.gate == "ready", model.deviceState?.power != "off", model.machine?.has("coin") == true, model.machine?.coinAfterSwipe != true {
            Button { Task { await model.device("coin") } } label: {
              HStack(spacing: 10) { if model.deviceBusy { ProgressView() } else { Image(systemName: "centsign.circle") }; Text("投币") }
            }.buttonStyle(ClipActionStyle()).disabled(model.deviceBusy)
          }
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
    }.frame(maxWidth: .infinity)
  }

  private var cardsView: some View {
    VStack(spacing: 0) {
      if model.cards.isEmpty {
        Text("还没有可用卡片，请先在 Prism 添加卡片")
          .foregroundStyle(.secondary).multilineTextAlignment(.center)
        Link("添加卡片", destination: model.api.baseURL.appendingPathComponent("cards"))
          .buttonStyle(ClipActionStyle()).padding(.top, 16)
        Button("重新加载卡片") { Task { await model.reloadCards() } }
          .buttonStyle(ClipActionStyle()).padding(.top, 24)
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
  var origin: URL = PrismAPI.defaultOrigin
  @State private var image: UIImage?

  private var url: URL? {
    shop.heroUrl.flatMap { URL(string: $0, relativeTo: origin)?.absoluteURL }
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

private struct ClipActionStyle: ButtonStyle {
  var primary = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(primary ? Color.white : Color.primary)
      .padding(.horizontal, 24).padding(.vertical, 14)
      .frame(maxWidth: .infinity, minHeight: 58)
      .background(primary ? Color.blue : Color.primary.opacity(0.065), in: Capsule())
      .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.7 : 1)
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
                Button { Task { await model.enter() } } label: { HStack { if model.deviceBusy { ProgressView() }; Text("确认入场") } }.buttonStyle(ClipActionStyle(primary: true)).disabled(!consent)
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
            }.buttonStyle(ClipActionStyle(primary: true)).disabled(device.gate == "entry" && !consent)
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
                  HStack { if model.deviceBusy { ProgressView() }; Text(mine ? "下桌" : "上桌") }
                }.buttonStyle(ClipActionStyle(primary: !mine))
              }
            }.frame(maxWidth: .infinity)

          }
          if device.gate == "ready", device.power == "off" {
            VStack(spacing: 28) {
              Text("设备尚未开机").font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
              Button { Task { await model.device("power.on") } } label: {
                HStack(spacing: 10) { if model.deviceBusy || model.waitingPower { ProgressView() } else { Image(systemName: "power") }; Text("开机") }
              }.buttonStyle(ClipActionStyle(primary: true)).disabled(model.waitingPower)
            }.frame(maxWidth: .infinity)
          }
        }
      } else if model.errorMessage != nil {
        Button("重试") { Task { model.clearError(); await model.refreshVisit() } }.buttonStyle(ClipActionStyle())
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
  @State private var redeemCode = ""
  @State private var done = false
  @State private var loadError: String?
  @State private var attempt = 0
  private var title: LocalizedStringKey { ["账单", "兑换", "记录", "钱包"][section] }
  @ViewBuilder private var closeButton: some View {
    if #available(iOS 26.0, *) {
      Button(role: .close) { dismiss() } label: { Image(systemName: "xmark") }
        .tint(.primary).accessibilityLabel("关闭")
    } else {
      Button { dismiss() } label: { Image(systemName: "xmark") }.tint(.primary).accessibilityLabel("关闭")
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
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
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
            if let session = model.summary?.activeSession { Text(prismDate(session.startedAt) + " – " + String(localized: "现在")).font(.caption).foregroundStyle(.secondary) }
            ForEach(preview.chargeItems) { item in PrismLabeledRow(item.label, value: item.amount.formatted(.number.precision(.fractionLength(2)))) }
            ForEach(preview.adjustments) { item in PrismLabeledRow(item.label, value: item.amount.formatted(.number.precision(.fractionLength(2)))) }
            PrismLabeledRow(String(localized: "合计"), value: preview.settlementPreview.total.formatted(.number.precision(.fractionLength(2)))).font(.title3.bold())
          } else if !model.deviceBusy && model.errorMessage == nil && loadError == nil { Text("暂无待结账单") }
        } else if section == 1 {
          if done { Text("兑换成功") } else {
            TextField("兑换码", text: $redeemCode).textInputAutocapitalization(.never).autocorrectionDisabled().padding(18).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.15)))
            Button { Task { await model.redeem(redeemCode.trimmingCharacters(in: .whitespacesAndNewlines)); done = model.errorMessage == nil } } label: { HStack { if model.deviceBusy { ProgressView() }; Text("兑换") } }.buttonStyle(ClipActionStyle(primary: true)).disabled(redeemCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
      }.disabled(model.deviceBusy).padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if section == 0, !done, model.checkoutPreview != nil {
        Button { Task { await model.checkout(); done = model.errorMessage == nil } } label: {
          HStack { if model.deviceBusy { ProgressView() }; Text("结账") }
        }
        .buttonStyle(ClipActionStyle(primary: true)).disabled(model.deviceBusy)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
        .frame(maxWidth: 480).frame(maxWidth: .infinity)
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        closeButton
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
private func prismParsedDate(_ value: String) -> Date? {
  let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}
private struct PrismLabeledRow: View {
  let title: String; let value: String
  init(_ title: String, value: String) { self.title = title; self.value = value }
  var body: some View { HStack(alignment: .firstTextBaseline) { Text(title); Spacer(); Text(value) }.padding(.vertical, 12) }
}
