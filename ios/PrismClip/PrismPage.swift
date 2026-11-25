import Foundation

/// What a scanned page is made of. PRiSM defines it in `packages/page-protocol`; these mirror it.
/// Every word on the page comes with it, so a block misses nothing the App Clip would have to make up.

/// A value the platform wants sent back as it is.
enum PrismPageValue: Decodable, Equatable {
  case string(String), number(Double), bool(Bool), null

  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
    else if let number = try? value.decode(Double.self) { self = .number(number) }
    else if let string = try? value.decode(String.self) { self = .string(string) }
    else { self = .null }
  }

  var json: Any {
    switch self {
    case .string(let value): return value
    case .number(let value): return value
    case .bool(let value): return value
    case .null: return NSNull()
    }
  }
}

struct PrismPageButton: Decodable {
  let id: String
  let label: String
  /// Replaces `label` while a code from this button is showing.
  let againLabel: String?
  let icon: String?
  let style: String?
  let enabled: Bool
  let action: String
  /// The answer shows on the button for a moment instead of under it.
  let answerOnButton: Bool?
  var hideDuringCapture: Bool? = nil
  var wait: Wait? = nil
  var collect: [String]? = nil
  var confirm: Confirm? = nil
  let payload: [String: PrismPageValue]?
  /// The block that must be agreed to first.
  let requires: String?
  let needsLocation: Bool

  struct Wait: Decodable {
    let ms: Int
    let timeoutMessage: String
  }

  struct Confirm: Decodable {
    let title: String
    let body: String
    let confirmLabel: String
    let cancelLabel: String
    var destructive: Bool? = nil
  }
}

/// A field read as nothing, instead of failing its whole block, when this build cannot read it.
@propertyWrapper struct PrismLenient<Value: Decodable>: Decodable {
  var wrappedValue: Value?
  init(from decoder: Decoder) throws { wrappedValue = try? Value(from: decoder) }
}

struct PrismPageSignIn: Decodable {
  let id: String
  let methods: [Method]

  struct Method: Decodable, Identifiable {
    let id: String
    let provider: String
    let label: String
    let busyLabel: String
    var style: String? = nil
  }
}

struct PrismPageBinding: Decodable {
  let id: String
  let title: String
  let expiresLabel: String
  let copyLabel: String
  let copiedLabel: String
  let retryLabel: String
}

struct PrismPagePricingLabels: Decodable {
  let title: String
  let sharedCapsTitle: String
  let stoppedTitle: String
  let startedTag: String
  let keptTag: String
  let fixedFee: String
  let notBilled: String
  let notCovered: String
  let uncapped: String
  let capReached: String
  let accumulated: String
  let cap: String
  let minuteUnit: String
  let listSeparator: String
}

struct PrismPagePricing: Decodable {
  let id: String
  let rules: PrismResourceBilling.Rules
  /// Only annotates the rules, which stay readable without it.
  @PrismLenient var changes: PrismResourceBilling.Preview?
  let labels: PrismPagePricingLabels
}

struct PrismPageClimate: Decodable {
  let id: String
  /// Unknown, or unreadable here: the card still offers on and off.
  @PrismLenient var state: PrismClimate?
  let needsLocation: Bool
  let title: String
  let unknownStatus: String
  let offLabel: String
  let roomText: String?
  let currentModeLabel: String?
  let turnOnLabel: String
  let turnOffLabel: String
  let temperatureLabel: String
  let lowerTemperatureLabel: String
  let raiseTemperatureLabel: String
  let modeLabel: String
  let fanLabel: String
  let modes: [ModeOption]
  let fanModes: [FanOption]
  let actions: Actions

  struct ModeOption: Decodable, Identifiable, Equatable {
    let value: String
    let label: String
    var icon: String? = nil
    var id: String { value }
  }

  struct FanOption: Decodable, Identifiable, Equatable {
    let value: String
    let label: String
    var id: String { value }
  }

  struct Actions: Decodable, Equatable {
    let on: String
    let off: String
    let setMode: String
    let setTemperature: String
    let setFanMode: String
  }

  /// The wording for a mode, including one just chosen that the entity has not confirmed.
  func label(forMode mode: String) -> String {
    modes.first { $0.value == mode }?.label ?? (mode == state?.mode ? currentModeLabel : nil) ?? mode
  }
}

/// Where the player's cards go. The cards themselves are read apart from the page.
struct PrismPageCards: Decodable {
  let id: String
  let enabled: Bool
  let capture: Bool
  let action: String
  let needsLocation: Bool
  let title: String
  let loadingLabel: String
  let locatingLabel: String
  let swipingLabel: String
  let endingTemplate: String
  let empty: Empty
  let loadError: LoadError
  /// Only where a card can be added.
  var captureUi: CaptureUi? = nil

  struct Action: Decodable, Identifiable {
    let id: String
    let label: String
    let action: String
    var style: String? = nil
  }

  struct Empty: Decodable {
    let text: String
    let actions: [Action]
  }

  struct LoadError: Decodable {
    let title: String
    let actions: [Action]
  }

  struct CaptureUi: Decodable, Equatable {
    let title: String
    let addLabel: String
    let startingText: String
    let waitingText: String
    let cancelLabel: String
    let doneLabel: String
    let leftPageText: String
    let outcomes: Outcomes

    struct Outcomes: Decodable, Equatable {
      let added: String
      let taken: String
      let unsupported: String
      let expired: String
    }
  }

  func ending(last4: String) -> String { endingTemplate.replacingOccurrences(of: "{digits}", with: last4) }
}

struct PrismPageTable: Decodable {
  let id: String
  let title: String
  let status: String
  let capacity: Int
  let emptyLabel: String
  let mineLabel: String
  let seats: [Seat]
  struct Seat: Decodable { let name: String; let mine: Bool }
}

struct PrismPageSection: Decodable {
  let id: String
  var title: String? = nil
  var subtitle: String? = nil
  var style: String? = nil
  let blocks: [PrismPageBlock]
}

struct PrismPageRow: Decodable {
  let id: String
  let blocks: [PrismPageBlock]
}

struct PrismPageKeyValue: Decodable {
  let id: String
  let items: [Item]

  struct Item: Decodable {
    var id: String? = nil
    let label: String
    let value: String
    var tone: String? = nil
  }
}

struct PrismPageBanner: Decodable {
  let id: String
  var title: String? = nil
  let body: String
  var level: String? = nil
}

struct PrismPageImage: Decodable {
  let id: String
  let url: String
  var alt: String? = nil
  var aspectRatio: Double? = nil
}

struct PrismPageInput: Decodable {
  let id: String
  var name: String? = nil
  var label: String? = nil
  var placeholder: String? = nil
  var inputType: String? = nil
  var defaultValue: String? = nil
  var required: Bool? = nil
  var maxLength: Int? = nil
  var helperText: String? = nil
  var enabled: Bool? = nil
}

struct PrismPageSelect: Decodable {
  let id: String
  var name: String? = nil
  var label: String? = nil
  var style: String? = nil
  let options: [Option]
  var defaultValue: String? = nil
  var required: Bool? = nil
  var enabled: Bool? = nil

  struct Option: Decodable, Identifiable {
    let value: String
    let label: String
    var detail: String? = nil
    var disabled: Bool? = nil
    var id: String { value }
  }
}

struct PrismPageToggle: Decodable {
  let id: String
  var name: String? = nil
  let label: String
  var description: String? = nil
  var defaultValue: Bool? = nil
  var required: Bool? = nil
  var enabled: Bool? = nil
}

/// One block of the page. A block this build cannot read, a new kind or a changed one, is `unknown`
/// and is skipped: the platform can add to the page without breaking a released App Clip.
indirect enum PrismPageBlock: Decodable, Identifiable {
  case text(id: String, text: String, style: String?, level: String?)
  case section(PrismPageSection)
  case row(PrismPageRow)
  case kv(PrismPageKeyValue)
  case banner(PrismPageBanner)
  case divider(id: String)
  case image(PrismPageImage)
  case input(PrismPageInput)
  case select(PrismPageSelect)
  case toggle(PrismPageToggle)
  case signin(PrismPageSignIn)
  case binding(PrismPageBinding)
  case pricing(PrismPagePricing)
  case consent(id: String, text: String)
  case climate(PrismPageClimate)
  case table(PrismPageTable)
  case cards(PrismPageCards)
  case button(PrismPageButton)
  case unknown(id: String)

  private enum Keys: String, CodingKey { case kind, id, text, style, level }

  init(from decoder: Decoder) throws {
    let keyed = try decoder.container(keyedBy: Keys.self)
    let id = (try? keyed.decode(String.self, forKey: .id)) ?? UUID().uuidString
    let kind = (try? keyed.decode(String.self, forKey: .kind)) ?? ""
    do {
      switch kind {
      case "text":
        self = .text(
          id: id,
          text: try keyed.decode(String.self, forKey: .text),
          style: try? keyed.decode(String.self, forKey: .style),
          level: try? keyed.decode(String.self, forKey: .level)
        )
      case "section": self = .section(try PrismPageSection(from: decoder))
      case "row": self = .row(try PrismPageRow(from: decoder))
      case "kv": self = .kv(try PrismPageKeyValue(from: decoder))
      case "banner": self = .banner(try PrismPageBanner(from: decoder))
      case "divider": self = .divider(id: id)
      case "image": self = .image(try PrismPageImage(from: decoder))
      case "input": self = .input(try PrismPageInput(from: decoder))
      case "select": self = .select(try PrismPageSelect(from: decoder))
      case "toggle": self = .toggle(try PrismPageToggle(from: decoder))
      case "signin": self = .signin(try PrismPageSignIn(from: decoder))
      case "binding": self = .binding(try PrismPageBinding(from: decoder))
      case "pricing": self = .pricing(try PrismPagePricing(from: decoder))
      case "consent": self = .consent(id: id, text: try keyed.decode(String.self, forKey: .text))
      case "climate": self = .climate(try PrismPageClimate(from: decoder))
      case "table", "mahjong": self = .table(try PrismPageTable(from: decoder))
      case "cards": self = .cards(try PrismPageCards(from: decoder))
      case "button": self = .button(try PrismPageButton(from: decoder))
      default: self = .unknown(id: id)
      }
    } catch {
      self = .unknown(id: id)
    }
  }

  /// Whether this is, or holds, the block with this id.
  func contains(id target: String) -> Bool {
    switch self {
    case .section(let section): return section.id == target || section.blocks.contains { $0.contains(id: target) }
    case .row(let row): return row.id == target || row.blocks.contains { $0.contains(id: target) }
    default: return id == target
    }
  }

  var id: String {
    switch self {
    case .text(let id, _, _, _), .divider(let id), .consent(let id, _), .unknown(let id):
      return id
    case .section(let section): return section.id
    case .row(let row): return row.id
    case .kv(let kv): return kv.id
    case .banner(let banner): return banner.id
    case .image(let image): return image.id
    case .input(let input): return input.id
    case .select(let select): return select.id
    case .toggle(let toggle): return toggle.id
    case .signin(let signIn): return signIn.id
    case .binding(let binding): return binding.id
    case .pricing(let pricing): return pricing.id
    case .climate(let climate): return climate.id
    case .table(let table): return table.id
    case .cards(let cards): return cards.id
    case .button(let button): return button.id
    }
  }
}

/// The page after scanning a resource, as the platform generates it. `docs/player-page.md` in PRiSM
/// says what clients do with it.
struct PrismPage: Decodable {
  static let maxDepth = 8

  let shop: String
  let shopCode: String
  let heroUrl: String?
  let resource: String
  let publicId: String
  /// The player has something billing at this shop, here or elsewhere.
  let billingActive: Bool
  let blocks: [PrismPageBlock]

  /// Flattens container blocks (`section`, `row`) up to `maxDepth` levels.
  func allBlocks(maxDepth: Int = PrismPage.maxDepth) -> [PrismPageBlock] {
    var out: [PrismPageBlock] = []
    func visit(_ items: [PrismPageBlock], depth: Int) {
      guard depth < maxDepth else { return }
      for item in items {
        out.append(item)
        switch item {
        case .section(let section): visit(section.blocks, depth: depth + 1)
        case .row(let row): visit(row.blocks, depth: depth + 1)
        default: break
        }
      }
    }
    visit(blocks, depth: 0)
    return out
  }

  var cards: PrismPageCards? {
    for block in allBlocks() { if case .cards(let cards) = block { return cards } }
    return nil
  }
  func climate(id: String) -> PrismPageClimate? {
    for block in allBlocks() { if case .climate(let climate) = block, climate.id == id { return climate } }
    return nil
  }
  var asksToSignIn: Bool { allBlocks().contains { if case .signin = $0 { return true }; return false } }
  var needsBinding: Bool { allBlocks().contains { if case .binding = $0 { return true }; return false } }
  var asksConsent: Bool { allBlocks().contains { if case .consent = $0 { return true }; return false } }
  func hasButton(id: String) -> Bool {
    allBlocks().contains { if case .button(let button) = $0 { return button.id == id }; return false }
  }
  var buttonIds: [String] {
    allBlocks().compactMap { if case .button(let button) = $0 { return button.id }; return nil }
  }
  /// What the rest of the app reads alongside the page depends on these: the bill, the Live Activity.
  func movedBilling(from other: PrismPage) -> Bool {
    asksConsent != other.asksConsent || needsBinding != other.needsBinding || billingActive != other.billingActive
  }
}

/// A door code, in that action's answer only. Shown above the button that asked for it until it expires.
struct PrismPageCode: Decodable {
  let title: String
  let value: String
  let expiresAt: String
  let expiresLabel: String
  let hint: String
}

struct PrismActionAnswer: Decodable {
  let ok: Bool
  let page: PrismPage
  let notices: [PrismNotice]
  var code: PrismPageCode? = nil
}
