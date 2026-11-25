import SwiftUI

struct ClipInputBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let input: PrismPageInput
  let context: ClipPageContext
  /// What the field shows. It has its own copy because a `TextField` keeps showing what was typed
  /// when its binding refuses part of it, so the limit has to be written back into the field.
  @State private var text = ""

  private var current: String { context.page.stringValue(for: input.id, in: context.values) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let label = input.label {
        Text(verbatim: label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
      }
      TextField(input.placeholder ?? "", text: $text)
        .keyboardType(input.inputType == "number" ? .decimalPad : .default)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(prismCardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .disabled(model.pageBusy || input.enabled == false)
        .onChange(of: text) {
          if let limit = input.maxLength, limit > 0, text.count > limit { text = String(text.prefix(limit)) }
          else if text != current { context.setValue(input.id, .string(text)) }
        }
        // The page can set the value too: its first read, or a field coming back.
        .onChange(of: current, initial: true) { if text != current { text = current } }
      if let helper = input.helperText {
        Text(verbatim: helper).font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct ClipSelectBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let select: PrismPageSelect
  let context: ClipPageContext

  private var selected: String { context.page.stringValue(for: select.id, in: context.values) }
  private func isDisabled(_ option: PrismPageSelect.Option) -> Bool {
    model.pageBusy || select.enabled == false || option.disabled == true
  }

  var body: some View {
    if !select.options.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        if let label = select.label {
          Text(verbatim: label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
        if select.style == "segmented" { segments } else { list }
      }
    }
  }

  private var segments: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(select.options.count, 4)), spacing: 4) {
      ForEach(select.options) { option in
        let on = option.value == selected
        choice(option, on: on) {
          Text(verbatim: option.label)
            .font(.subheadline).fontWeight(on ? .semibold : .regular)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 42)
            .foregroundStyle(on ? Color.blue : Color.primary.opacity(0.75))
            .background(on ? Color(uiColor: .secondarySystemGroupedBackground) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(on ? 0.1 : 0), radius: 3, y: 1)
        }
      }
    }
    .padding(4)
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private var list: some View {
    VStack(spacing: 0) {
      ForEach(Array(select.options.enumerated()), id: \.element.id) { index, option in
        if index > 0 { Divider().padding(.leading, 18) }
        let on = option.value == selected
        choice(option, on: on) {
          HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: option.label).font(.body.weight(.medium)).foregroundStyle(.primary)
              if let detail = option.detail {
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary)
              }
            }
            Spacer(minLength: 0)
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
              .font(.title3)
              .foregroundStyle(on ? Color.blue : Color.secondary.opacity(0.45))
          }
          .padding(.horizontal, 18).padding(.vertical, 14)
          .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
          .background(on ? Color.blue.opacity(0.06) : .clear)
          .contentShape(Rectangle())
        }
      }
    }
    .background(prismCardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  private func choice<Label: View>(_ option: PrismPageSelect.Option, on: Bool, @ViewBuilder label: () -> Label) -> some View {
    Button { context.setValue(select.id, .string(option.value)) } label: { label() }
      .buttonStyle(.plain)
      .disabled(isDisabled(option))
      .opacity(isDisabled(option) ? 0.45 : 1)
      .accessibilityAddTraits(on ? .isSelected : [])
  }
}

struct ClipToggleBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let toggle: PrismPageToggle
  let context: ClipPageContext

  var body: some View {
    let binding = Binding<Bool>(
      get: { context.page.boolValue(for: toggle.id, in: context.values) },
      set: { context.setValue(toggle.id, .bool($0)) }
    )
    Toggle(isOn: binding) {
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: toggle.label).font(.body)
        if let description = toggle.description {
          Text(verbatim: description).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .disabled(model.pageBusy || toggle.enabled == false)
  }
}

struct ClipConsentBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let id: String
  let text: String
  let context: ClipPageContext

  var body: some View {
    let ticked = context.page.boolValue(for: id, in: context.values)
    Button { context.setValue(id, .bool(!ticked)) } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: ticked ? "checkmark.square.fill" : "square").foregroundStyle(ticked ? Color.blue : .secondary)
        Text(verbatim: text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
      }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }.buttonStyle(.plain).accessibilityValue(ticked ? "✓" : "—").disabled(model.pageBusy)
  }
}
