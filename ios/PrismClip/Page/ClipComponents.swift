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
  case "success": return "checkmark.circle"
  case "info": return "info.circle"
  case "error": return "xmark.circle"
  default: return "exclamationmark.circle"
  }
}

/// Feedback uses accent blue for success, secondary text for information and red for errors.
func noticeColor(_ level: String) -> Color {
  switch level {
  case "success": return .blue
  case "info": return .secondary
  default: return .red
  }
}

/// The colour of a notice's icon and tint: blue for news, red for an error.
func noticeTint(_ level: String) -> Color { noticeIsError(level) ? .red : .blue }

/// Persistent conditions and input feedback stay beside the relevant control.
struct InlineNotice: View {
  let notice: PrismNotice
  var body: some View {
    Label(notice.body, systemImage: noticeSymbol(notice.level))
      .font(.subheadline)
      .foregroundStyle(noticeIsError(notice.level) ? Color.red : Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.updatesFrequently)
  }
}

/// A transient result floats at the top of the currently presented screen.
struct ClipToast: View {
  let notice: PrismNotice?
  let dismiss: () -> Void
  @GestureState private var drag = CGSize.zero

  var body: some View {
    if let notice, notice.presentation == "toast" {
      Label(notice.body, systemImage: noticeSymbol(notice.level))
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .fixedSize(horizontal: false, vertical: true)
        .offset(x: drag.width, y: drag.height)
        .gesture(
          DragGesture(minimumDistance: 10)
            .updating($drag) { value, state, _ in
              state = CGSize(width: value.translation.width, height: min(0, value.translation.height))
            }
            .onEnded { value in
              let horizontal = abs(value.translation.width) > 60 || abs(value.predictedEndTranslation.width) > 140
              let upward = value.translation.height < -40 || value.predictedEndTranslation.height < -100
              if horizontal || upward {
                withAnimation(.easeOut(duration: 0.2)) { dismiss() }
              }
            }
        )
        .frame(maxWidth: 440)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("page-toast")
        .accessibilityAction(.escape) { dismiss() }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
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
    if let note = model.inlineNotice, note.presentation != "toast", anchors.contains(model.inlineNoticeAnchor) { InlineNotice(notice: note) }
  }
}
