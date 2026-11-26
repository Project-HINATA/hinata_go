import SwiftUI

extension PrismPageBinding {
  /// The shop link has no page from the platform, so it brings its own wording.
  static var shopLink: PrismPageBinding {
    PrismPageBinding(id: "binding", title: String(localized: "绑定身份"), expiresLabel: String(localized: "有效期至"),
                     copyLabel: String(localized: "复制"), copiedLabel: String(localized: "已复制"), retryLabel: String(localized: "重试"))
  }
}

struct ClipPlatformBinding: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let labels: PrismPageBinding
  @State private var copied = false
  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text(verbatim: labels.title)
        .font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
      VStack(alignment: .leading, spacing: 18) {
        if let binding = model.binding {
          ForEach(Array(binding.lines.enumerated()), id: \.offset) { _, line in
            if line.command {
              HStack(spacing: 12) {
                Text(verbatim: line.text).font(.system(size: 21, design: .monospaced)).textSelection(.enabled)
                Spacer(minLength: 0)
                Button(copied ? labels.copiedLabel : labels.copyLabel) {
                  UIPasteboard.general.string = line.text
                  copied = true
                  Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = false }
                }.buttonStyle(.bordered)
              }
            } else {
              Text(verbatim: line.text).font(.subheadline)
            }
          }
          Text(verbatim: labels.expiresLabel + " " + prismDisplayClock(binding.expiresAt, seconds: true))
            .font(.caption).foregroundStyle(.secondary)
        }
        if model.errorMessage != nil {
          Button(labels.retryLabel) {
            Task { await model.bindPlatformIdentity() }
          }.disabled(model.deviceBusy)
        } else if model.binding == nil { ProgressView() }
      }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(prismCardFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
  }
}
