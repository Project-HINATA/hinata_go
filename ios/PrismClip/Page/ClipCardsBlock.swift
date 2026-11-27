import SwiftUI

/// The player's cards, swiping one, and adding one at the reader.
struct ClipCardsBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let block: PrismPageCards

  var body: some View {
    if model.cardsLoadFailed, let message = model.cardsError {
      // The page is this alone: there is nothing to do but read the cards again.
      VStack(spacing: 20) {
        ClipStatusMessage(titleText: Text(verbatim: block.loadError.title), message: message, symbol: "exclamationmark.triangle")
        actions(block.loadError.actions, topSpacing: 0)
      }
    } else {
      VStack(spacing: 28) {
        header
        if let capture = model.cardCapture, let ui = block.captureUi {
          ClipCardCapture(capture: capture, ui: ui)
        } else {
          content.disabled(model.deviceBusy || !block.enabled)
        }
      }
    }
  }

  private var header: some View {
    ZStack(alignment: .trailing) {
      Text(verbatim: model.cardCapture == nil ? block.title : block.captureUi?.title ?? block.title)
        .font(.title2).frame(maxWidth: .infinity).multilineTextAlignment(.center)
      if block.capture, let ui = block.captureUi, model.cardCapture == nil {
        Button { Task { await model.startCardCapture() } } label: {
          Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
        }
        .accessibilityLabel(Text(verbatim: ui.addLabel))
        .disabled(model.deviceBusy || model.state != .ready)
      }
    }.padding(.bottom, 2)
  }

  private var content: some View {
    VStack(spacing: 0) {
      if model.cardsLoading {
        ProgressView().frame(maxWidth: .infinity).accessibilityLabel(Text(verbatim: block.loadingLabel))
      } else if model.cards.isEmpty {
        Text(verbatim: block.empty.text)
          .foregroundStyle(.secondary).multilineTextAlignment(.center)
        actions(block.empty.actions, topSpacing: 16)
      } else {
        rows
      }
    }
  }

  private var rows: some View {
    VStack(spacing: 0) {
      ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
        if index > 0 { Divider().padding(.leading, 24) }
        let active = model.activeCardId == card.id
        // A swipe's outcome stays on the row the player tapped; nothing else waits for it.
        let feedback = model.cardFeedback?.cardId == card.id ? model.cardFeedback : nil
        Button { Task { await model.login(card: card) } } label: {
          HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
              Text(card.label).font(.title3.weight(.semibold)).foregroundStyle(.primary)
              if let feedback {
                feedbackText(feedback).font(.body.weight(.semibold)).multilineTextAlignment(.leading)
              } else {
                Text(verbatim: active ? detail(card) : ending(card))
                  .font(.body).foregroundStyle(.secondary)
              }
            }
            Spacer(minLength: 0)
            if let feedback {
              Image(systemName: noticeSymbol(feedback.level))
                .font(.title2).foregroundStyle(noticeTint(feedback.level))
            } else if active && [.locating, .sending].contains(model.state) {
              ProgressView()
            } else {
              Image(systemName: "chevron.right").font(.subheadline).foregroundStyle(.tertiary)
            }
          }
          .padding(.horizontal, 24).padding(.vertical, 16)
          .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
          .animation(.easeOut(duration: 0.2), value: feedback)
          .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .tint(.primary)
        .disabled(model.state != .ready)
        .opacity(model.state != .ready && !active ? 0.45 : 1)
      }
    }
    .background(prismCardFill)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  /// The buttons the page offers when there is no card to show. One this build does not know is left out.
  private func actions(_ actions: [PrismPageCards.Action], topSpacing: CGFloat) -> some View {
    ForEach(Array(actions.enumerated()), id: \.element.id) { index, item in
      let paddingTop = index == 0 ? topSpacing : 16
      switch item.action {
      case "cards.capture":
        if block.capture, block.captureUi != nil {
          action(item) { await model.startCardCapture() }.padding(.top, paddingTop)
        }
      case "cards.reload":
        action(item) { await model.refreshCards() }.padding(.top, paddingTop)
      default:
        EmptyView()
      }
    }
  }

  private func action(_ item: PrismPageCards.Action, run: @escaping () async -> Void) -> some View {
    Button { Task { await run() } } label: {
      Text(verbatim: item.label).frame(maxWidth: .infinity).padding(.vertical, 12)
    }
    .clipActionStyle(primary: item.style == "primary")
  }

  private func detail(_ card: ArcadeCard) -> String {
    switch model.state {
    case .locating: return block.locatingLabel
    case .sending: return block.swipingLabel
    default: return ending(card)
    }
  }

  private func feedbackText(_ feedback: CardFeedback) -> Text {
    feedback.parts.enumerated().reduce(Text(verbatim: "")) { text, item in
      let part = Text(item.element.text).foregroundStyle(noticeColor(item.element.level))
      return item.offset == 0 ? part : text + Text(verbatim: " · ").foregroundStyle(.secondary) + part
    }
  }

  private func ending(_ card: ArcadeCard) -> String {
    block.ending(last4: String(card.accessCode.suffix(4)))
  }
}

/// Adding a card at the cabinet's reader: waiting for the card, then what came of it.
struct ClipCardCapture: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let capture: MachineLoginViewModel.CardCapture
  let ui: PrismPageCards.CaptureUi
  var body: some View {
    VStack(spacing: 16) {
      switch capture {
      case .starting, .waiting:
        ProgressView().controlSize(.large)
        Text(verbatim: capture == .starting ? ui.startingText : ui.waitingText)
          .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button { model.dismissCardCapture() } label: {
          Text(verbatim: ui.cancelLabel).frame(maxWidth: .infinity).padding(.vertical, 12)
        }.clipActionStyle()
      case .done(let level, let message):
        Image(systemName: noticeSymbol(level)).font(.largeTitle).foregroundStyle(noticeTint(level))
        Text(verbatim: message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        Button { model.dismissCardCapture() } label: {
          Text(verbatim: ui.doneLabel).frame(maxWidth: .infinity).padding(.vertical, 12)
        }.clipActionStyle()
      }
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background(prismCardFill, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .accessibilityElement(children: .contain)
  }
}
