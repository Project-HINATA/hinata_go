import SwiftUI

struct MachineLoginView: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  @Environment(\.openURL) private var openURL

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        header

        switch model.state {
        case .idle, .loadingMachine:
          ProgressView("加载中...")
            .frame(maxWidth: .infinity, alignment: .center)
        case .unauthenticated:
          authenticationView
        case .ready:
          cardsView
        case .locating, .sending:
          ProgressView(model.state == .locating ? "确认位置..." : "正在登录...")
            .frame(maxWidth: .infinity, alignment: .center)
        case .success:
          successView
        case .failed:
          failedView
        }
      }
      .frame(maxWidth: 560, alignment: .leading)
      .padding(24)
      // App Clip attribution is a system overlay, not part of our safe area.
      // Keep a stable clearance rather than moving content when it disappears.
      .padding(.top, 88)
      .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      Color(.systemGroupedBackground).ignoresSafeArea()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("ArcadeLink")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      if let machine = model.machine {
        Text(machine.shop.name)
          .font(.largeTitle.weight(.bold))
          .fixedSize(horizontal: false, vertical: true)
        Label(machine.name, systemImage: "gamecontroller")
          .font(.title3)
          .foregroundStyle(.secondary)
      } else {
        Text("ArcadeLink")
          .font(.title2.weight(.semibold))
      }
    }
  }

  private var authenticationView: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("登录账号后即可登录：")
        .foregroundStyle(.secondary)
      Button {
        Task { await model.authenticateWithPasskey() }
      } label: {
        Label("使用 Passkey 登录", systemImage: "person.badge.key.fill")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(ClipActionStyle())

      Button {
        Task { await model.authenticateWithMunet() }
      } label: {
        Label("使用 MuNET 登录", systemImage: "person.crop.circle.badge.checkmark")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(ClipActionStyle())

      if let url = model.webFallbackURL {
        Button {
          openURL(url)
        } label: {
          Label("使用网页版登录", systemImage: "safari")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private var cardsView: some View {
    VStack(alignment: .leading, spacing: 12) {
      if model.cards.isEmpty {
        Text("还没有添加卡片")
          .foregroundStyle(.secondary)
        Link("先添加一张卡片", destination: URL(string: "https://link.neri.moe/cards")!)
      } else {
        Text("选择卡片")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
        ForEach(model.cards) { card in
          Button {
            Task { await model.login(card: card) }
          } label: {
            HStack(spacing: 14) {
              Image(systemName: "creditcard")
                .font(.title2)
                .foregroundStyle(.secondary)
              VStack(alignment: .leading, spacing: 4) {
                Text(card.label)
                  .font(.headline)
                Text("尾号 \(card.accessCode.suffix(4))")
                  .font(.caption.monospaced())
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text("登录")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(ClipActionStyle())
        }
      }
    }
  }

  private var successView: some View {
    VStack(spacing: 12) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 52))
        .foregroundStyle(.green)
      Text("已登录")
        .font(.title2.weight(.semibold))
      Text("本次会话已结束")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36)
  }

  private var failedView: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("无法进入机台会话", systemImage: "exclamationmark.triangle.fill")
        .font(.headline)
        .foregroundStyle(.orange)
      Text(model.errorMessage ?? "请重新碰一下 NFC 或重新扫描二维码。")
        .foregroundStyle(.secondary)
      if let shopCode = model.shopCode, let publicId = model.publicId {
        Button("重试") { Task { await model.start(shopCode: shopCode, publicId: publicId) } }
          .buttonStyle(ClipActionStyle())
      }
      if let url = model.webFallbackURL {
        Button("使用网页版继续") { openURL(url) }
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

private struct ClipActionStyle: ButtonStyle {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func makeBody(configuration: Configuration) -> some View {
    surface(configuration.label
      .foregroundStyle(.primary)
      .padding(18)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }

  @ViewBuilder
  private func surface<Content: View>(_ content: Content) -> some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
    } else {
      content.background(Color(.secondarySystemGroupedBackground),
                         in: RoundedRectangle(cornerRadius: 20))
    }
  }
}
