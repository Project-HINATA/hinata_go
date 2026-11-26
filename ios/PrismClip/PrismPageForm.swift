import Foundation

/// What the player fills in on a page (both body `blocks` and `footer`) and what a button sends back.
/// The same rules as the web's (`allPageBlocks(page)`).
extension PrismPage {
  var fieldIds: Set<String> {
    var ids = Set<String>()
    for block in allBlocks() {
      switch block {
      case .input(let input): ids.insert(input.id)
      case .select(let select): ids.insert(select.id)
      case .toggle(let toggle): ids.insert(toggle.id)
      case .consent(let id, _): ids.insert(id)
      default: break
      }
    }
    return ids
  }

  func reconciledValues(from existing: [String: PrismPageValue]) -> [String: PrismPageValue] {
    var next: [String: PrismPageValue] = [:]
    for block in allBlocks() {
      switch block {
      case .input(let input):
        guard next[input.id] == nil else { continue }
        if case .string(let s) = existing[input.id] { next[input.id] = .string(s) }
        else { next[input.id] = .string(input.defaultValue ?? "") }
      case .select(let select):
        guard next[select.id] == nil else { continue }
        if case .string(let s) = existing[select.id] { next[select.id] = .string(s) }
        else { next[select.id] = .string(select.defaultValue ?? "") }
      case .toggle(let toggle):
        guard next[toggle.id] == nil else { continue }
        if case .bool(let b) = existing[toggle.id] { next[toggle.id] = .bool(b) }
        else { next[toggle.id] = .bool(toggle.defaultValue ?? false) }
      case .consent(let id, _):
        guard next[id] == nil else { continue }
        if case .bool(let b) = existing[id] { next[id] = .bool(b) }
        else { next[id] = .bool(false) }
      default:
        break
      }
    }
    return next
  }

  func stringValue(for id: String, in values: [String: PrismPageValue]) -> String {
    if case .string(let s) = values[id] { return s }
    return ""
  }

  func boolValue(for id: String, in values: [String: PrismPageValue]) -> Bool {
    if case .bool(let b) = values[id] { return b }
    return false
  }

  func canSubmit(_ button: PrismPageButton, values: [String: PrismPageValue]) -> Bool {
    guard button.enabled else { return false }
    if let requires = button.requires {
      guard case .bool(true) = values[requires] else { return false }
    }
    guard let collect = button.collect, !collect.isEmpty else { return true }
    let byId = Dictionary(allBlocks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for id in collect {
      guard let block = byId[id] else { continue }
      switch block {
      case .consent(let cid, _):
        guard case .bool(true) = values[cid] else { return false }
      case .toggle(let toggle):
        if toggle.required == true {
          guard case .bool(true) = values[toggle.id] else { return false }
        }
      case .input(let input):
        if input.required == true {
          guard case .string(let text) = values[input.id],
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
      case .select(let select):
        if select.required == true {
          guard case .string(let selected) = values[select.id],
                let option = select.options.first(where: { $0.value == selected }),
                option.disabled != true else { return false }
        }
      default:
        break
      }
    }
    return true
  }

  func collectedPayload(for button: PrismPageButton, values: [String: PrismPageValue]) -> [String: Any] {
    var out: [String: Any] = [:]
    guard let collect = button.collect, !collect.isEmpty else { return out }
    let byId = Dictionary(allBlocks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for id in collect {
      guard let block = byId[id] else { continue }
      switch block {
      case .input(let input):
        let key = input.name.flatMap { $0.isEmpty ? nil : $0 } ?? input.id
        if case .string(let s) = values[input.id] { out[key] = s }
        else { out[key] = input.defaultValue ?? "" }
      case .select(let select):
        let key = select.name.flatMap { $0.isEmpty ? nil : $0 } ?? select.id
        if case .string(let s) = values[select.id] { out[key] = s }
        else { out[key] = select.defaultValue ?? "" }
      case .toggle(let toggle):
        let key = toggle.name.flatMap { $0.isEmpty ? nil : $0 } ?? toggle.id
        if case .bool(let b) = values[toggle.id] { out[key] = b }
        else { out[key] = toggle.defaultValue ?? false }
      case .consent(let cid, _):
        if case .bool(let b) = values[cid] { out[cid] = b }
        else { out[cid] = false }
      default:
        break
      }
    }
    return out
  }

  static func resolveImageURL(_ raw: String, origin: URL) -> URL? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("//"),
          let resolved = URL(string: trimmed, relativeTo: origin)?.absoluteURL,
          let scheme = resolved.scheme?.lowercased() else { return nil }
    if scheme == "https" { return resolved }
    if scheme == "http" {
      let sameScheme = origin.scheme?.lowercased() == "http"
      let sameHost = resolved.host?.lowercased() == origin.host?.lowercased()
      let samePort = (resolved.port ?? 80) == (origin.port ?? 80)
      if sameScheme && sameHost && samePort { return resolved }
    }
    return nil
  }
}
