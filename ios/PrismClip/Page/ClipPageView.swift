import SwiftUI

/// Shared form input and confirmation state across body `blocks` and sticky `footer` of a page.
@MainActor
final class ClipPageFormState: ObservableObject {
  @Published var values: [String: PrismPageValue] = [:]
  @Published var pendingConfirm: PrismPageButton? = nil
}

/// What every block on a drawn page can reach.
struct ClipPageContext {
  let page: PrismPage
  /// What the player has typed, picked or ticked, keyed by block id.
  let values: [String: PrismPageValue]
  let setValue: (String, PrismPageValue) -> Void
  /// Asks before pressing a button that wants confirming.
  let confirm: (PrismPageButton) -> Void
  let press: (PrismPageButton, [String: Any]) -> Void
  let busy: Bool
  let pressingId: String?
  let waitingButtonId: String?
  let inlineNotice: PrismNotice?
  let inlineNoticeAnchor: String
  let noticeAboveButton: Bool
  let openTarget: ((PrismPageTarget) -> Void)?
  let loadMore: ((String, PrismPageTarget) -> Void)?
  let loadingMoreId: String?
  /// Loading more of a list failed: shown at that list's button, where the player is looking.
  let loadMoreError: (blockId: String, message: String)?
  /// Reads the page again.
  let refresh: () -> Void
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
  @ObservedObject var form: ClipPageFormState
  var sheetMode = false

  private var context: ClipPageContext {
    makeClipPageContext(page: page, form: form, model: model, sheetMode: sheetMode, noticeAboveButton: false)
  }

  var body: some View {
    let context = context
    VStack(alignment: .leading, spacing: 28) {
      ClipPageBlockList(blocks: page.blocks, depth: 0, context: context)
    }
    // Reconcile field defaults and prune removed field IDs when leaving a step.
    .onChange(of: page.fieldIds) { form.values = page.reconciledValues(from: form.values) }
    .onChange(of: page.buttonIds) {
      if let pending = form.pendingConfirm, !page.hasButton(id: pending.id) { form.pendingConfirm = nil }
    }
    .alert(
      form.pendingConfirm?.confirm?.title ?? "",
      isPresented: Binding(get: { form.pendingConfirm?.confirm != nil }, set: { if !$0 { form.pendingConfirm = nil } }),
      presenting: form.pendingConfirm
    ) { button in
      if let confirm = button.confirm {
        Button(confirm.cancelLabel, role: .cancel) { form.pendingConfirm = nil }
        Button(confirm.confirmLabel, role: confirm.destructive == true ? .destructive : nil) {
          let collected = page.collectedPayload(for: button, values: context.values)
          form.pendingConfirm = nil
          context.press(button, collected)
        }
      }
    } message: { button in
      if let confirm = button.confirm { Text(verbatim: confirm.body) }
    }
  }
}

/// Renders the page's sticky `footer` blocks, sharing form values and confirmation state with `ClipPage`.
struct ClipPageFooter: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let page: PrismPage
  @ObservedObject var form: ClipPageFormState
  var sheetMode = false

  var body: some View {
    if let footer = page.footer, !footer.isEmpty {
      let context = makeClipPageContext(page: page, form: form, model: model, sheetMode: sheetMode, noticeAboveButton: true)
      VStack(spacing: 12) {
        ClipPageBlockList(blocks: footer, depth: 0, context: context)
      }
    }
  }
}

@MainActor
private func makeClipPageContext(
  page: PrismPage,
  form: ClipPageFormState,
  model: MachineLoginViewModel,
  sheetMode: Bool,
  noticeAboveButton: Bool
) -> ClipPageContext {
  let values = page.reconciledValues(from: form.values)
  return ClipPageContext(
    page: page,
    values: values,
    setValue: { id, value in
      var updated = values
      updated[id] = value
      form.values = updated
    },
    confirm: { form.pendingConfirm = $0 },
    press: { button, collected in
      if sheetMode {
        Task { await model.pressSheet(button, collected: collected) }
      } else {
        Task { await model.press(button, collected: collected) }
      }
    },
    busy: sheetMode ? model.sheetBusy : model.pageBusy,
    pressingId: sheetMode ? model.sheetPressing : model.pressing,
    waitingButtonId: sheetMode ? model.sheetWaitingButtonId : model.waitingButtonId,
    inlineNotice: sheetMode ? model.sheetInlineNotice : model.inlineNotice,
    inlineNoticeAnchor: sheetMode ? model.sheetInlineNoticeAnchor : model.inlineNoticeAnchor,
    noticeAboveButton: noticeAboveButton,
    openTarget: sheetMode ? { target in Task { await model.openSheetTarget(target) } } : nil,
    loadMore: sheetMode ? { id, target in Task { await model.loadMoreSheetList(blockId: id, target: target) } } : nil,
    loadingMoreId: sheetMode ? model.sheetLoadingMoreId : nil,
    loadMoreError: sheetMode ? model.sheetLoadMoreError : nil,
    refresh: sheetMode
      ? { _ = Task { await model.reloadAccountSheet() } }
      : { _ = Task { await model.refreshVisit(silent: true) } },
    soleBlockId: (!sheetMode && model.cardsLoadFailed) ? page.cards?.id : nil
  )
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
    case .bill(let bill): ClipBillBlock(block: bill, refresh: context.refresh)
    case .list(let list): ClipListBlock(list: list, context: context)
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
