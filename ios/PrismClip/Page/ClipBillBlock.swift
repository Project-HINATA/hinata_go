import SwiftUI

/// Renders a server-driven `bill` block: in `live` mode it estimates the checkout preview locally
/// from `billingInputs` using `PrismCheckoutEngine` (falling back to `preview` when absent); in
/// `settled` mode it draws the settled status, total, post-checkout balance, and timeline.
struct ClipBillBlock: View {
  let block: PrismPageBill
  @State private var computed: PrismCheckout? = nil
  @State private var failed = false
  @State private var attempt = 0

  private var displayZone: TimeZone {
    block.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
  }

  private var taskKey: String {
    let snapshotStamp = block.billingInputs?.billingSnapshot?.capturedAt.timeIntervalSince1970 ?? -1
    let playerCount = block.billingInputs?.billingSnapshot?.players.count ?? -1
    let previewTotal = block.preview?.settlementPreview.total ?? -1
    return "\(block.id):\(block.mode):\(block.timeZone ?? ""):\(block.billingInputs?.playerId ?? ""):\(snapshotStamp):\(playerCount):\(previewTotal):\(block.settledAt ?? ""):\(attempt)"
  }

  var body: some View {
    Group {
      if block.mode == "settled" {
        settledView
      } else if failed {
        errorView
      } else if let preview = computed ?? (block.billingInputs == nil ? block.preview : nil) {
        liveView(preview)
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .task(id: taskKey) {
      await resolvePreview()
    }
  }

  private var settledView: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 12) {
        Image(systemName: "checkmark.circle").foregroundStyle(.green).font(.largeTitle)
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: block.labels.settledTitle).font(.title2.weight(.semibold))
          if let settledAt = block.settledAt {
            Text(verbatim: prismDisplayDate(settledAt, timeZone: displayZone))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      if let settled = block.preview {
        VStack(alignment: .leading, spacing: 20) {
          ClipBillTotal(total: settled.settlementPreview.total, timeline: settled.timeline, labels: block.labels)
            .frame(maxWidth: 480, alignment: .leading).padding(.bottom, 4)
          if let balanceAfter = block.balanceAfter {
            HStack(alignment: .firstTextBaseline) {
              Text(verbatim: block.labels.balanceAfterLabel)
              Spacer()
              Text(balanceAfter.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
            }
            .padding(.vertical, 12)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .background(prismCardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          }
          billBreakdown(settled)
        }
      }
    }
  }

  private func liveView(_ preview: PrismCheckout) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      ClipBillTotal(total: preview.settlementPreview.total, timeline: preview.timeline, labels: block.labels)
        .frame(maxWidth: 480, alignment: .leading).padding(.bottom, 4)
      billBreakdown(preview)
    }
    .padding(.horizontal, 4)
  }

  private var errorView: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(verbatim: block.labels.estimateError)
        .font(.subheadline)
        .foregroundStyle(.red)
      Button {
        attempt += 1
      } label: {
        Text(verbatim: block.labels.retryLabel)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .clipActionStyle()
    }
  }

  @ViewBuilder private func billBreakdown(_ preview: PrismCheckout) -> some View {
    if let timeline = preview.timeline {
      ClipBillTimeline(timeline: timeline, timeZone: block.timeZone, labels: block.labels)
    } else {
      ForEach(preview.chargeItems) { item in
        HStack(alignment: .firstTextBaseline) {
          Text(verbatim: item.label)
          Spacer()
          Text(item.amount.formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
        }
        .padding(.vertical, 12)
      }
      ForEach(preview.adjustments) { item in
        HStack(alignment: .firstTextBaseline) {
          Text(verbatim: item.label)
          Spacer()
          Text(item.amount.formatted(.number.precision(.fractionLength(2))))
            .monospacedDigit()
            .foregroundStyle(item.amount < 0 ? Color.green : Color.primary)
        }
        .padding(.vertical, 12)
      }
    }
  }

  private func resolvePreview() async {
    guard block.mode != "settled" else {
      computed = block.preview
      failed = false
      return
    }
    guard let inputs = block.billingInputs else {
      computed = block.preview
      failed = false
      return
    }
    guard let snapshot = inputs.billingSnapshot else {
      if let fallback = block.preview {
        computed = fallback
        failed = false
      } else {
        computed = nil
        failed = true
      }
      return
    }
    failed = false
    do {
      let playerId = inputs.playerId
      let result = try await Task.detached(priority: .userInitiated) {
        PrismCheckout(try PrismCheckoutEngine.preview(snapshot: snapshot, playerId: playerId).view())
      }.value
      guard !Task.isCancelled else { return }
      computed = result
      failed = false
    } catch {
      guard !Task.isCancelled else { return }
      if let fallback = block.preview {
        computed = fallback
        failed = false
      } else {
        computed = nil
        failed = true
      }
    }
  }
}
