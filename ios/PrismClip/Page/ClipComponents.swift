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

/// One choice of a segmented control.
struct ClipSegment: Identifiable, Equatable {
  let id: String
  let label: String
  /// Drawn over the label.
  var symbol: String? = nil
  var enabled = true
}

/// Every segmented control in the App Clip. A few text choices are the system's own control, which
/// from iOS 26 is Liquid Glass: the selection slides and a finger can drag it. What that control cannot
/// draw, a symbol over a label or more choices than its equal widths hold, is drawn here to behave the
/// same: one glass pill that slides between them.
struct ClipSegmentedControl: View {
  let segments: [ClipSegment]
  /// The segment shown as picked; none when it matches no segment.
  let selected: String
  /// Colours the picked segment's label.
  var accent: Color? = nil
  var enabled = true
  /// More choices than this no longer share the width, and scroll.
  var fits = 4
  let choose: (String) -> Void

  var body: some View {
    if segments.count <= fits && !segments.contains(where: { $0.symbol != nil }) {
      ClipSystemSegments(segments: segments, selected: selected, accent: accent, enabled: enabled, choose: choose)
    } else {
      ClipSlidingSegments(
        segments: segments, selected: selected, accent: accent ?? .primary, enabled: enabled,
        scrolls: segments.count > fits, choose: choose)
    }
  }
}

/// `UISegmentedControl` rather than a segmented `Picker`, which cannot disable one of its choices.
private struct ClipSystemSegments: UIViewRepresentable {
  let segments: [ClipSegment]
  let selected: String
  let accent: Color?
  let enabled: Bool
  let choose: (String) -> Void

  @MainActor final class Coordinator: NSObject {
    var segments: [ClipSegment] = []
    var choose: (String) -> Void = { _ in }

    @objc func changed(_ control: UISegmentedControl) {
      guard segments.indices.contains(control.selectedSegmentIndex) else { return }
      choose(segments[control.selectedSegmentIndex].id)
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeUIView(context: Context) -> UISegmentedControl {
    let control = UISegmentedControl()
    control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
    control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return control
  }

  func updateUIView(_ control: UISegmentedControl, context: Context) {
    let coordinator = context.coordinator
    coordinator.choose = choose
    let relabelled = coordinator.segments.map(\.id) != segments.map(\.id)
      || coordinator.segments.map(\.label) != segments.map(\.label)
    coordinator.segments = segments
    if relabelled {
      control.removeAllSegments()
      for (index, segment) in segments.enumerated() { control.insertSegment(withTitle: segment.label, at: index, animated: false) }
    }
    for (index, segment) in segments.enumerated() { control.setEnabled(segment.enabled, forSegmentAt: index) }
    control.isEnabled = enabled && context.environment.isEnabled
    let size = UIFont.preferredFont(forTextStyle: .subheadline).pointSize
    control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: size)], for: .normal)
    var picked: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: .semibold)]
    if let accent { picked[.foregroundColor] = UIColor(accent) }
    control.setTitleTextAttributes(picked, for: .selected)
    let index = segments.firstIndex { $0.id == selected } ?? UISegmentedControl.noSegment
    guard control.selectedSegmentIndex != index else { return }
    // A change that did not come from a touch, such as a refused tab going back, slides as well.
    if relabelled || control.window == nil {
      control.selectedSegmentIndex = index
    } else {
      UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
        control.selectedSegmentIndex = index
        control.layoutIfNeeded()
      }
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
    CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width, height: 40)
  }
}

private struct ClipSlidingSegments: View {
  let segments: [ClipSegment]
  let selected: String
  let accent: Color
  let enabled: Bool
  let scrolls: Bool
  let choose: (String) -> Void
  @Environment(\.isEnabled) private var environmentEnabled
  @Namespace private var pill
  /// Where a finger dragging across the segments is, before it lifts.
  @State private var dragged: String?
  @State private var width: CGFloat = 0

  private var shown: String { dragged ?? selected }
  private var tall: Bool { segments.contains { $0.symbol != nil } }

  var body: some View {
    Group {
      if scrolls {
        ScrollViewReader { reader in
          // The room around the row is inside the scroll view, or it cuts the pill's glass at the edges.
          ScrollView(.horizontal, showsIndicators: false) { row.padding(3) }
            .onChange(of: selected, initial: true) { withAnimation(.snappy) { reader.scrollTo(selected, anchor: .center) } }
        }
      } else {
        row
          .background(GeometryReader { geometry in
            Color.clear.onChange(of: geometry.size.width, initial: true) { width = geometry.size.width }
          })
          .simultaneousGesture(drag)
          .padding(3)
      }
    }
    .background(Color.primary.opacity(0.06), in: shape(radius: tall ? 22 : 23))
    .clipShape(shape(radius: tall ? 22 : 23))
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: shown)
    .sensoryFeedback(.selection, trigger: shown)
  }

  private var row: some View {
    HStack(spacing: 2) {
      ForEach(segments) { segment in
        let on = segment.id == shown
        let off = !enabled || !environmentEnabled || !segment.enabled
        Button {
          if segment.id != selected { choose(segment.id) }
        } label: {
          VStack(spacing: 4) {
            if let symbol = segment.symbol { Image(systemName: symbol).font(.system(size: 18)) }
            Text(verbatim: segment.label)
          }
          .font(tall ? .footnote : .subheadline).fontWeight(on ? .semibold : .regular)
          .lineLimit(1).minimumScaleFactor(0.8)
          .padding(.horizontal, scrolls ? 16 : 2)
          .frame(maxWidth: scrolls ? nil : .infinity, minHeight: tall ? 56 : 34)
          .foregroundStyle(on ? accent : Color.primary.opacity(0.75))
          // Only says where the pill belongs; the pill itself is behind the whole row.
          .background(Color.clear.matchedGeometryEffect(id: segment.id, in: pill))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(off)
        .opacity(segment.enabled ? 1 : 0.4)
        .id(segment.id)
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    // One pill under every label, so that on its way it never paints over the ones it passes.
    .background {
      if segments.contains(where: { $0.id == shown }) {
        glass.matchedGeometryEffect(id: shown, in: pill, isSource: false)
      }
    }
  }

  private var drag: some Gesture {
    DragGesture(minimumDistance: 8)
      .onChanged { value in
        // A mostly vertical movement is the sheet being scrolled.
        guard enabled, environmentEnabled, width > 0,
              dragged != nil || abs(value.translation.width) > abs(value.translation.height) else { return }
        let index = min(segments.count - 1, max(0, Int(value.location.x / (width / CGFloat(segments.count)))))
        if segments[index].enabled { dragged = segments[index].id }
      }
      .onEnded { _ in
        if let dragged, dragged != selected { choose(dragged) }
        dragged = nil
      }
  }

  private func shape(radius: CGFloat) -> RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

  @ViewBuilder private var glass: some View {
    if #available(iOS 26.0, *) {
      Color.clear.glassEffect(
        .regular.tint(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.85)).interactive(),
        in: shape(radius: tall ? 19 : 20))
    } else {
      shape(radius: tall ? 19 : 20).fill(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
    }
  }
}
