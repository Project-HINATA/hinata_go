import SwiftUI

/// What every block on a drawn page can reach.
struct ClipPageContext {
  let page: PrismPage
  /// What the player has typed, picked or ticked, keyed by block id.
  let values: [String: PrismPageValue]
  let setValue: (String, PrismPageValue) -> Void
  /// Asks before pressing a button that wants confirming.
  let confirm: (PrismPageButton) -> Void
  /// While set, the page is that block alone and every other one stays off it.
  let soleBlockId: String?

  func shows(_ block: PrismPageBlock) -> Bool {
    soleBlockId.map { block.contains(id: $0) } ?? true
  }
}

/// Draws what the platform says this page is. Only what the player is in the middle of is kept here;
/// each kind of block is its own view.
struct ClipPage: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let page: PrismPage
  @State private var fieldValues: [String: PrismPageValue] = [:]
  @State private var pendingConfirm: PrismPageButton? = nil

  private var context: ClipPageContext {
    let values = page.reconciledValues(from: fieldValues)
    return ClipPageContext(
      page: page,
      values: values,
      setValue: { id, value in
        var updated = values
        updated[id] = value
        fieldValues = updated
      },
      confirm: { pendingConfirm = $0 },
      soleBlockId: model.cardsLoadFailed ? page.cards?.id : nil
    )
  }

  var body: some View {
    let context = context
    VStack(alignment: .leading, spacing: 28) {
      ClipPageBlockList(blocks: page.blocks, depth: 0, context: context)
    }
    // Reconcile field defaults and prune removed field IDs when leaving a step.
    .onChange(of: page.fieldIds) { fieldValues = page.reconciledValues(from: fieldValues) }
    .onChange(of: page.buttonIds) {
      if let pending = pendingConfirm, !page.hasButton(id: pending.id) { pendingConfirm = nil }
    }
    .alert(
      pendingConfirm?.confirm?.title ?? "",
      isPresented: Binding(get: { pendingConfirm?.confirm != nil }, set: { if !$0 { pendingConfirm = nil } }),
      presenting: pendingConfirm
    ) { button in
      if let confirm = button.confirm {
        Button(confirm.cancelLabel, role: .cancel) { pendingConfirm = nil }
        Button(confirm.confirmLabel, role: confirm.destructive == true ? .destructive : nil) {
          let collected = page.collectedPayload(for: button, values: context.values)
          pendingConfirm = nil
          Task { await model.press(button, collected: collected) }
        }
      }
    } message: { button in
      if let confirm = button.confirm { Text(verbatim: confirm.body) }
    }
  }
}

struct ClipPageBlockList: View {
  let blocks: [PrismPageBlock]
  let depth: Int
  let context: ClipPageContext

  var body: some View {
    ForEach(blocks.filter(context.shows)) { block in
      ClipPageBlockView(block: block, depth: depth, context: context)
    }
  }
}

/// Which view draws which kind. A new kind is one view and one line here.
struct ClipPageBlockView: View {
  let block: PrismPageBlock
  let depth: Int
  let context: ClipPageContext

  var body: some View {
    if depth < PrismPage.maxDepth { content }
  }

  @ViewBuilder private var content: some View {
    switch block {
    case .text(_, let text, let style, let level): ClipTextBlock(text: text, style: style, level: level)
    case .section(let section): ClipSectionBlock(section: section, depth: depth, context: context)
    case .row(let row): ClipRowBlock(row: row, depth: depth, context: context)
    case .kv(let kv): ClipKeyValueBlock(kv: kv)
    case .banner(let banner): ClipBannerBlock(banner: banner)
    case .divider: Divider()
    case .image(let image): ClipImageBlock(image: image)
    case .input(let input): ClipInputBlock(input: input, context: context)
    case .select(let select): ClipSelectBlock(select: select, context: context)
    case .toggle(let toggle): ClipToggleBlock(toggle: toggle, context: context)
    case .consent(let id, let text): ClipConsentBlock(id: id, text: text, context: context)
    case .button(let button): ClipButtonBlock(button: button, context: context)
    case .signin(let signIn): ClipSignInButtons(methods: signIn.methods)
    case .binding(let binding):
      VStack(spacing: 12) {
        ClipPlatformBinding(labels: binding)
        AnchoredNotice([binding.id])
      }
    case .pricing(let pricing): ClipResourcePricing(rules: pricing.rules, changes: pricing.changes, labels: pricing.labels)
    case .climate(let climate):
      VStack(spacing: 12) {
        ClipClimateCard(block: climate)
        AnchoredNotice([climate.id])
      }
    case .table(let table): ClipTableBlock(table: table)
    case .cards(let cards): ClipCardsBlock(block: cards)
    // A kind this build does not know yet.
    case .unknown: EmptyView()
    }
  }
}

extension MachineLoginViewModel {
  /// Something is under way, so the page's controls wait for it.
  var pageBusy: Bool { deviceBusy || [.loadingCards, .locating, .sending].contains(state) }
}
