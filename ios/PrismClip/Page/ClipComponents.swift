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
  let message: String?
  let symbol: String
  /// Red for a refusal (disabled, cannot be used); the system's grey otherwise.
  var tint: Color? = nil
  /// A smaller, quieter title, for an empty sheet rather than a whole page's state.
  var quiet = false

  init(title: LocalizedStringKey, message: String, symbol: String) {
    self.titleView = Text(title)
    self.message = message
    self.symbol = symbol
  }

  init(titleText: Text, message: String?, symbol: String, tint: Color? = nil, quiet: Bool = false) {
    self.titleView = titleText
    self.message = message
    self.symbol = symbol
    self.tint = tint
    self.quiet = quiet
  }

  var body: some View {
    if #available(iOS 17.0, *) {
      ContentUnavailableView {
        Label {
          titleView.font(quiet ? .headline : .title2).foregroundStyle(quiet ? .secondary : .primary)
        } icon: {
          Image(systemName: symbol).foregroundStyle(tint ?? .secondary)
        }
      } description: {
        if let message { Text(verbatim: message) }
      }
        .fixedSize(horizontal: false, vertical: true)
    } else {
      VStack(spacing: 12) {
        Image(systemName: symbol).font(.largeTitle).foregroundStyle(tint ?? .secondary)
        titleView.font(quiet ? .headline : .title2)
        if let message { Text(verbatim: message).foregroundStyle(.secondary) }
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
  case "success": return "checkmark.circle.fill"
  case "info": return "info.circle.fill"
  default: return "exclamationmark.circle.fill"
  }
}

/// The colour of a notice's words. Success takes the app's accent blue; news reads as
/// plain text, so it never looks like a disabled control.
func noticeColor(_ level: String) -> Color {
  switch level {
  case "success": return .blue
  case "info": return .primary
  default: return .red
  }
}

/// The colour of a notice's icon and tint: blue for news, red for an error.
func noticeTint(_ level: String) -> Color { noticeIsError(level) ? .red : .blue }

/// An action's outcome, shown where the player acted instead of in an alert: one tinted
/// strip with the nature's icon, the same under a button, in a sheet and above a footer button.
struct InlineNotice: View {
  let notice: PrismNotice
  /// Over scrolling content (a footer button): lifted off the page with a shadow.
  var lifted = false
  var body: some View {
    let tint = noticeTint(notice.level)
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: noticeSymbol(notice.level)).foregroundStyle(tint)
      Text(notice.body).foregroundStyle(noticeColor(notice.level))
    }
    .font(.subheadline.weight(.semibold))
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 11)
    .background {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(Color(.secondarySystemGroupedBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.09)))
        .shadow(color: .black.opacity(lifted ? 0.08 : 0), radius: 5, y: 2)
    }
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.2)))
    .transition(.opacity.combined(with: .move(edge: .top)))
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
