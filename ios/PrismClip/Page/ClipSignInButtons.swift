import SwiftUI

/// The ways to sign in, as the page lists them. A provider this build does not know is left out.
struct ClipSignInButtons: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let methods: [PrismPageSignIn.Method]

  /// For the shop link, and a scanned page that could not be read, which bring no list of their own.
  static var standard: [PrismPageSignIn.Method] {
    [
      .init(id: "munet", provider: "munet", label: String(localized: "使用 MuNET 登录"), busyLabel: String(localized: "正在连接 MuNET…"), style: "primary"),
      .init(id: "passkey", provider: "passkey", label: String(localized: "使用 Passkey 登录"), busyLabel: String(localized: "正在验证 Passkey…")),
    ]
  }

  var body: some View {
    VStack(spacing: 14) {
      ForEach(methods) { method in
        switch method.provider {
        case "munet":
          button(method, icon: Image("MuNETLogo").renderingMode(.original)) { await model.authenticateWithMunet() }
        case "passkey":
          button(method, icon: Image(systemName: "touchid")) { await model.authenticateWithPasskey() }
        default:
          EmptyView()
        }
      }
    }
    .disabled(model.authenticating != nil)
  }

  private func button(_ method: PrismPageSignIn.Method, icon: Image, run: @escaping () async -> Void) -> some View {
    let busy = model.authenticating == method.provider
    return Button { Task { await run() } } label: {
      actionLabel(Text(verbatim: busy ? method.busyLabel : method.label), icon: icon, busy: busy)
    }
    .clipActionStyle(primary: method.style == "primary")
  }

  private func actionLabel(_ title: Text, icon: Image, busy: Bool) -> some View {
    HStack(spacing: 10) {
      Group {
        if busy { ProgressView().tint(.primary) }
        else { icon.resizable().scaledToFit() }
      }
      .frame(width: 24, height: 24)
      .accessibilityHidden(true)
      title.multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 12)
  }
}
