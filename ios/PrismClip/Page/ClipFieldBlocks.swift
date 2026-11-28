import PhotosUI
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
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.done)
        .onSubmit { submitOnReturn() }
        .padding(.horizontal, 16).padding(.vertical, 15)
        .background(prismCardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(context.busy || input.enabled == false)
        .onChange(of: text) {
          if let limit = input.maxLength, limit > 0, text.count > limit { text = String(text.prefix(limit)) }
          else if text != current { context.setValue(input.id, .string(text)) }
        }
        // The page can set the value too: its first read, or a field coming back.
        .onChange(of: current, initial: true) { if text != current { text = current } }
      if context.inlineNoticeAnchor == input.id, let notice = context.inlineNotice { InlineNotice(notice: notice) }
      if let helper = input.helperText {
        Text(verbatim: helper).font(.caption).foregroundStyle(.secondary)
      }
    }
  }

  private func submitOnReturn() {
    let matching = context.page.allBlocks().compactMap { block -> PrismPageButton? in
      guard case .button(let button) = block,
            button.collect?.contains(input.id) == true else { return nil }
      return button
    }
    guard matching.count == 1, let button = matching.first else { return }
    guard !context.busy && context.page.canSubmit(button, values: context.values) else { return }
    if button.confirm != nil {
      context.confirm(button)
    } else {
      context.press(button, context.page.collectedPayload(for: button, values: context.values))
    }
  }
}

struct ClipSelectBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let select: PrismPageSelect
  let context: ClipPageContext

  private var selected: String { context.page.stringValue(for: select.id, in: context.values) }
  private func isDisabled(_ option: PrismPageSelect.Option) -> Bool {
    context.busy || select.enabled == false || option.disabled == true
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
    ClipSegmentedControl(
      segments: select.options.map {
        ClipSegment(id: $0.value, label: $0.label, enabled: $0.disabled != true)
      },
      selected: selected,
      enabled: !context.busy && select.enabled != false
    ) { context.setValue(select.id, .string($0)) }
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
    .disabled(context.busy || toggle.enabled == false)
  }
}

struct ClipConsentBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let id: String
  let text: String
  let context: ClipPageContext

  var body: some View {
    let ticked = context.page.boolValue(for: id, in: context.values)
    VStack(alignment: .leading, spacing: 8) {
    Button { context.setValue(id, .bool(!ticked)) } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: ticked ? "checkmark.square.fill" : "square").foregroundStyle(ticked ? Color.blue : .secondary)
        Text(verbatim: text).font(.subheadline).foregroundStyle(.primary).multilineTextAlignment(.leading)
      }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }.buttonStyle(.plain).accessibilityValue(ticked ? "✓" : "—").disabled(context.busy)
    if context.inlineNoticeAnchor == id, let notice = context.inlineNotice { InlineNotice(notice: notice) }
    }
  }
}

/// The preset picture field, backed by the system photo picker, which needs no photo library access.
struct ClipUploadBlock: View {
  let upload: PrismPageUpload
  let context: ClipPageContext
  @State private var selection: PhotosPickerItem?
  @State private var reading = false
  @State private var problem: String?
  @State private var preview: UIImage?
  @State private var enlarged = false

  private var current: String { context.page.stringValue(for: upload.id, in: context.values) }
  private var off: Bool { context.busy || reading || upload.enabled == false }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let preview, !current.isEmpty {
        chosen(preview)
      } else {
        picker { empty }
      }
      if let problem {
        Label(problem, systemImage: "xmark.circle").font(.subheadline).foregroundStyle(.red)
      }
      if context.inlineNoticeAnchor == upload.id, let notice = context.inlineNotice { InlineNotice(notice: notice) }
    }
    .onChange(of: selection) {
      guard let item = selection else { return }
      selection = nil
      Task { await take(item) }
    }
    // The page can drop the value too: a field leaving and coming back starts empty.
    .onChange(of: current, initial: true) {
      if current.isEmpty { preview = nil }
      else if preview == nil { preview = ClipPicture.image(fromDataURL: current) }
    }
    .fullScreenCover(isPresented: $enlarged) { lightbox }
  }

  private func picker<Content: View>(@ViewBuilder label: () -> Content) -> some View {
    PhotosPicker(selection: $selection, matching: .images, label: label)
      .disabled(off)
  }

  private var empty: some View {
    VStack(spacing: 8) {
      if reading { ProgressView() } else { Image(systemName: "photo.badge.plus").font(.title2) }
      Text(verbatim: upload.label).font(.subheadline.weight(.semibold))
      if let hint = upload.hint { Text(verbatim: hint).font(.caption).foregroundStyle(.secondary) }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 26)
    .overlay(
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
    )
    .contentShape(Rectangle())
  }

  private func chosen(_ picture: UIImage) -> some View {
    VStack(spacing: 10) {
      Button { enlarged = true } label: {
        Image(uiImage: picture).resizable().scaledToFit()
          .frame(maxWidth: .infinity)
          .frame(height: 180)
          .background(prismCardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(verbatim: upload.previewLabel))
      HStack(spacing: 10) {
        Spacer(minLength: 0)
        picker { Label(upload.replaceLabel, systemImage: "arrow.triangle.2.circlepath").font(.subheadline) }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)
        Button(role: .destructive) {
          preview = nil
          problem = nil
          context.setValue(upload.id, .string(""))
        } label: {
          Label(upload.removeLabel, systemImage: "trash").font(.subheadline)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(off)
      }
    }
  }

  private var lightbox: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()
      if let preview {
        Image(uiImage: preview).resizable().scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      Button { enlarged = false } label: {
        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.18), in: Circle())
      }
      .padding(16)
      .accessibilityLabel(Text(verbatim: upload.closeLabel))
    }
  }

  private func take(_ item: PhotosPickerItem) async {
    reading = true
    problem = nil
    defer { reading = false }
    guard let data = try? await item.loadTransferable(type: Data.self) else {
      problem = upload.errors.unreadable
      return
    }
    let limit = upload.maxBytes
    switch await Task.detached(priority: .userInitiated, operation: { ClipPicture.dataURL(data, maxBytes: limit) }).value {
    case .success(let url):
      preview = ClipPicture.image(fromDataURL: url)
      context.setValue(upload.id, .string(url))
    case .failure(let failure):
      preview = nil
      context.setValue(upload.id, .string(""))
      problem = failure == .tooLarge ? upload.errors.tooLarge : upload.errors.unreadable
    }
  }
}

/// Turns a picked photo into an `upload` value: an image data URL no larger than the field takes.
enum ClipPicture {
  enum Failure: Error { case tooLarge, unreadable }

  static func dataURL(_ data: Data, maxBytes: Int) -> Result<String, Failure> {
    if data.count <= maxBytes, let type = mimeType(data) { return .success(encode(data, type: type)) }
    // A HEIC photo, or a screenshot of several megabytes, is re-encoded rather than refused.
    guard let image = UIImage(data: data) else { return .failure(.unreadable) }
    let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    for (edge, quality) in [(2400.0, 0.85), (1800.0, 0.82), (1400.0, 0.78), (1000.0, 0.72)] {
      let ratio = min(1, edge / max(pixels.width, pixels.height))
      let size = CGSize(width: max(1, (pixels.width * ratio).rounded()), height: max(1, (pixels.height * ratio).rounded()))
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      // JPEG has no transparency, which would otherwise come out black.
      format.opaque = true
      let jpeg = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: quality) { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        image.draw(in: CGRect(origin: .zero, size: size))
      }
      if jpeg.count <= maxBytes { return .success(encode(jpeg, type: "image/jpeg")) }
    }
    return .failure(.tooLarge)
  }

  static func image(fromDataURL url: String) -> UIImage? {
    guard let comma = url.firstIndex(of: ","),
          let data = Data(base64Encoded: String(url[url.index(after: comma)...])) else { return nil }
    return UIImage(data: data)
  }

  private static func encode(_ data: Data, type: String) -> String { "data:\(type);base64,\(data.base64EncodedString())" }

  /// The formats the platform takes as they are, told apart by their first bytes.
  private static func mimeType(_ data: Data) -> String? {
    let head = [UInt8](data.prefix(12))
    if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
    if head.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
    if head.count == 12, Array(head[0..<4]) == Array("RIFF".utf8), Array(head[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
    return nil
  }
}
