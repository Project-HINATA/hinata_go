import SwiftUI

struct ClipButtonBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let button: PrismPageButton
  let context: ClipPageContext

  private static let symbols = [
    "coin": "centsign.circle",
    "power": "power",
    "door": "door.left.hand.open",
    "plus": "plus",
    "refresh": "arrow.clockwise",
    "check": "checkmark",
    "lock": "lock",
    "info": "info.circle",
    "warning": "exclamationmark.triangle",
    "close": "xmark",
    "arrow-right": "arrow.right",
  ]

  var body: some View {
    // Adding a card takes the place of what is done with one.
    if !(model.cardCapture != nil && button.hideDuringCapture == true) {
      let inline = button.answerOnButton != true && context.inlineNoticeAnchor == button.id ? context.inlineNotice : nil
      VStack(spacing: 12) {
        if button.againLabel != nil, let code = model.pageCode { doorCode(code) }
        if context.noticeAboveButton, let inline {
          InlineNotice(notice: inline)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
        control
        if !context.noticeAboveButton, let inline { InlineNotice(notice: inline) }
      }
    }
  }

  private func doorCode(_ code: PrismPageCode) -> some View {
    VStack(spacing: 16) {
      Text(verbatim: code.title).font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
      Text(verbatim: code.value).font(.system(size: 36, design: .monospaced)).tracking(4).textSelection(.enabled)
      Text(verbatim: code.expiresLabel + " " + prismDisplayClock(code.expiresAt, seconds: true)).font(.caption).foregroundStyle(.secondary)
      Text(verbatim: code.hint).font(.subheadline).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity).padding(.vertical, 12)
  }

  private var control: some View {
    let note = button.answerOnButton == true && button.enabled && context.inlineNoticeAnchor == button.id ? context.inlineNotice : nil
    let waiting = context.pressingId == button.id || context.waitingButtonId == button.id
    let off = context.busy || waiting || !context.page.canSubmit(button, values: context.values)
    let isPrimary = button.style == "primary"
    let isDestructive = button.style == "destructive"
    return Button {
      if button.confirm != nil {
        context.confirm(button)
      } else {
        let collected = context.page.collectedPayload(for: button, values: context.values)
        context.press(button, collected)
      }
    } label: {
      HStack(spacing: 10) {
        if waiting { ProgressView() }
        else if let note { Image(systemName: noticeSymbol(note.level)) }
        else if let symbol = button.icon.flatMap({ Self.symbols[$0] }) { Image(systemName: symbol) }
        Text(verbatim: note?.body ?? (model.pageCode != nil ? button.againLabel : nil) ?? button.label)
      }
      // Left to the button style when it has to show being disabled, which a set colour would hide.
      .modifier(ClipLabelTint(color: note.map { noticeColor($0.level) } ?? (isPrimary || off ? nil : (isDestructive ? Color.red : Color.primary))))
      .frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    .clipActionStyle(primary: isPrimary, destructive: isDestructive)
    .disabled(off)
  }
}
