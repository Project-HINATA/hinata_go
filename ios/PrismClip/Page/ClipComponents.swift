import SwiftUI

// Pieces shared by the scanned page's blocks and the screens around it.

struct ClipLabelTint: ViewModifier {
  let color: Color?
  @ViewBuilder func body(content: Content) -> some View {
    if let color { content.foregroundStyle(color) } else { content }
  }
}

struct ClipStatusMessage: View {
  let titleView: Text
  let message: String
  let symbol: String

  init(title: LocalizedStringKey, message: String, symbol: String) {
    self.titleView = Text(title)
    self.message = message
    self.symbol = symbol
  }

  init(titleText: Text, message: String, symbol: String) {
    self.titleView = titleText
    self.message = message
    self.symbol = symbol
  }

  var body: some View {
    if #available(iOS 17.0, *) {
      ContentUnavailableView {
        Label { titleView.font(.title2) } icon: { Image(systemName: symbol) }
      } description: { Text(message) }
        .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(spacing: 12) {
        Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
        titleView.font(.title2)
        Text(message).foregroundStyle(.secondary)
      }
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
    }
  }
}

/// Action buttons render as Liquid Glass on iOS 26+ (prominent for the main action,
/// regular glass for secondary ones) and keep the flat pill on earlier systems.
struct ClipActionModifier: ViewModifier {
  var primary = false
  var destructive = false

  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if primary {
        content.font(.headline).buttonStyle(.glassProminent).tint(.blue).buttonBorderShape(.capsule)
      } else if destructive {
        content.font(.headline).buttonStyle(.glass).tint(.red).buttonBorderShape(.capsule)
      } else {
        content.font(.headline).buttonStyle(.glass).buttonBorderShape(.capsule)
      }
    } else {
      content.buttonStyle(ClipActionStyle(primary: primary, destructive: destructive))
    }
  }
}

/// Fallback used below iOS 26, where glass button styles are unavailable.
struct ClipActionStyle: ButtonStyle {
  var primary = false
  var destructive = false
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    let disabledPrimary = primary && !enabled
    let foreground: Color = disabledPrimary
      ? Color.primary.opacity(0.35)
      : (primary ? .white : (destructive ? .red : .primary))
    let background: Color = disabledPrimary
      ? Color.primary.opacity(0.08)
      : (primary ? .blue : (destructive ? Color.red.opacity(0.12) : Color.primary.opacity(0.065)))
    configuration.label
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(foreground)
      .padding(.horizontal, 24)
      .frame(maxWidth: .infinity, minHeight: 58)
      .background(background, in: Capsule())
      .opacity(!enabled && !primary ? 0.5 : configuration.isPressed ? 0.7 : 1)
  }
}

extension View {
  func clipActionStyle(primary: Bool = false, destructive: Bool = false) -> some View {
    modifier(ClipActionModifier(primary: primary, destructive: destructive))
  }
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
struct AnchoredNotice: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let anchors: Set<String>
  init(_ anchors: Set<String>) { self.anchors = anchors }
  /// Every control on the page itself; the account sheet shows its own.
  static let page: Set<String> = ["entry", "binding"]
  var body: some View {
    if let note = model.inlineNotice, anchors.contains(model.inlineNoticeAnchor) { InlineNotice(notice: note) }
  }
}
