import SwiftUI

struct MachineLoginView: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @State private var showingLogoutConfirmation = false
  @State private var showingError = false

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if model.state == .expired {
          VStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark").font(.system(size: 42)).foregroundStyle(.secondary)
            Text("本次会话已失效").font(.title2.weight(.bold))
            Text("请重新碰一下 NFC 或重新扫描二维码。").foregroundStyle(.secondary)
          }
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity)
          .padding(.top, 120)
        } else if let machine = model.machine {
          VStack(alignment: .leading, spacing: 0) {
            if let path = machine.shop.heroUrl,
               let url = URL(string: path, relativeTo: URL(string: "https://link.neri.moe")) {
              AsyncImage(url: url.absoluteURL) { phase in
                if case .success(let image) = phase {
                  Color.clear.aspectRatio(1.5, contentMode: .fit)
                    .overlay { image.resizable().scaledToFill() }
                    .clipped()
                    .overlay(alignment: .bottom) { Divider() }
                    .accessibilityHidden(true)
                }
              }
            }
            VStack(alignment: .leading, spacing: 8) {
              Text(machine.shop.name)
                .font(.title.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
              Text(machine.name).font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .background(Color(.secondarySystemGroupedBackground))
          .clipShape(RoundedRectangle(cornerRadius: 32))
        } else if model.state != .failed {
          RoundedRectangle(cornerRadius: 32)
            .fill(Color.primary.opacity(0.04)).frame(height: 180)
            .accessibilityLabel("正在加载机台信息")
        }

        VStack(spacing: 10) {
          if [.ready, .loadingCards, .locating, .sending, .success].contains(model.state) {
            HStack {
              Text("选择卡片").font(.largeTitle.weight(.bold))
              Spacer()
              if #available(iOS 26.0, *) {
                logoutButton.buttonStyle(.glass).buttonBorderShape(.circle)
              } else {
                logoutButton.buttonStyle(.bordered).clipShape(Circle())
              }
            }
          } else if model.state == .completed {
            Text(title).font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
            Text("可以关闭此页面").foregroundStyle(.secondary)
          }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 52).padding(.bottom, 30)

        switch model.state {
        case .unauthenticated:
          VStack(spacing: 14) {
            Button { Task { await model.authenticateWithMunet() } } label: {
              actionLabel(model.authenticating == "munet" ? "正在连接 MuNET…" : "使用 MuNET 登录",
                          busy: model.authenticating == "munet")
            }
            .buttonStyle(ClipActionStyle(primary: true))
            Button { Task { await model.authenticateWithPasskey() } } label: {
              actionLabel(model.authenticating == "passkey" ? "正在验证 Passkey…" : "使用 Passkey 登录",
                          busy: model.authenticating == "passkey")
            }
            .buttonStyle(ClipActionStyle())
          }
          .disabled(model.authenticating != nil)
        case .ready, .locating, .sending, .success:
          cardsView
        case .loadingCards:
          if model.errorMessage != nil {
            Button("重新加载卡片") { Task { await model.reloadCards() } }
              .buttonStyle(ClipActionStyle())
          } else {
            VStack(spacing: 1) {
              ForEach(0..<3) { _ in Color.primary.opacity(0.04).frame(height: 84) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .accessibilityLabel("正在加载卡片")
          }
        case .failed:
          if let shop = model.shopCode, let machine = model.publicId {
            Button("重试") { Task { await model.start(shopCode: shop, publicId: machine) } }
              .buttonStyle(ClipActionStyle())
          }
        case .idle, .loadingMachine:
          ProgressView().accessibilityLabel("正在加载")
        case .completed, .expired:
          EmptyView()
        }
      }
      .frame(maxWidth: 480)
      .padding(.horizontal, 20).padding(.bottom, 28)
      // The provider notification overlays the safe area; reserve stable clearance.
      .padding(.top, 88)
      .frame(maxWidth: .infinity)
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
    .confirmationDialog("退出账号？", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
      Button("退出", role: .destructive) { Task { await model.logout() } }
      Button("取消", role: .cancel) {}
    }
    .alert("ArcadeLink", isPresented: $showingError) {
      Button("知道了") { model.clearError() }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .onChange(of: model.errorMessage) { value in
      showingError = value != nil
    }
  }

  private var title: String {
    switch model.state {
    case .idle, .loadingMachine: return "正在加载…"
    case .unauthenticated: return "登录 ArcadeLink"
    case .completed: return "本次登录已完成"
    case .failed: return "无法进入机台会话"
    default: return "选择卡片"
    }
  }

  private var logoutButton: some View {
    Button { showingLogoutConfirmation = true } label: {
      Image(systemName: "rectangle.portrait.and.arrow.right")
        .font(.title3)
        .frame(minWidth: 30, minHeight: 30)
    }
    .accessibilityLabel("退出账号")
  }

  private func actionLabel(_ title: String, busy: Bool) -> some View {
    HStack(spacing: 10) {
      if busy { ProgressView().tint(.primary) }
      Text(title)
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
                  Text(active ? rowDetail(card) : "尾号 \(card.accessCode.suffix(4))")
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
    case .locating: return "确认位置…"
    case .sending: return "正在登录…"
    case .success: return "已登录"
    default: return "尾号 \(card.accessCode.suffix(4))"
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
