import SwiftUI

/// The player's air conditioner, matching the Web device page. Off, it is one button; on,
/// the target temperature is the centre with round − and + either side, and mode and fan
/// speed are segmented rows underneath. The card takes the running mode's colour.
///
/// A choice is shown at once and gives way to what Home Assistant reports, or falls back
/// after a few seconds if it never does. Quick − / + presses are sent as one temperature, so
/// an on-site location fix is not taken for every step.
struct ClipClimateCard: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let block: PrismPageClimate
  @State private var draftMode: String?
  @State private var draftFan: String?
  @State private var draftTemperature: Double?
  @State private var sendTemperature: Task<Void, Never>?
  @State private var expireDraft: Task<Void, Never>?

  private static let modeSymbols: [String: String] = [
    "cool": "snowflake", "heat": "sun.max", "dry": "drop", "fan": "fan", "auto": "arrow.triangle.2.circlepath",
  ]

  private var state: PrismClimate? { block.state }
  private var actions: PrismPageClimate.Actions { block.actions }
  private var mode: String { draftMode ?? state?.mode ?? "off" }
  private var fanMode: String? { draftFan ?? state?.fanMode }
  private var temperature: Double? { draftTemperature ?? state?.temperature }
  private var isOn: Bool { state?.isOn == true }
  private var busy: Bool { model.deviceBusy || [.locating, .sending].contains(model.state) }

  private var accent: Color {
    guard isOn else { return .secondary }
    switch mode {
    case "heat": return Color(red: 0.91, green: 0.44, blue: 0.16)
    case "dry": return Color(red: 0.10, green: 0.60, blue: 0.54)
    case "fan_only": return Color(red: 0.37, green: 0.45, blue: 0.53)
    case "auto", "heat_cool": return Color(red: 0.48, green: 0.35, blue: 0.84)
    default: return .blue
    }
  }

  private func degrees(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: block.title).font(.title3.weight(.semibold))
          status.font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if isOn {
          Button { send(actions.off) } label: {
            Label(block.turnOffLabel, systemImage: "power").font(.subheadline.weight(.semibold))
              .padding(.horizontal, 14).padding(.vertical, 9)
              .background(Color.primary.opacity(0.07), in: Capsule())
          }.buttonStyle(.plain)
        }
      }
      if state == nil {
        HStack(spacing: 10) { powerButton(on: true); powerButton(on: false) }
      } else if !isOn {
        powerButton(on: true)
      } else {
        if let temperature { temperatureRow(temperature) }
        if !block.modes.isEmpty {
          segments(
            title: block.modeLabel,
            options: block.modes.map { option in
              ClipSegment(id: option.value, label: option.label, symbol: option.icon.flatMap { Self.modeSymbols[$0] })
            },
            selected: mode
          ) { value in
            draftMode = value; hold(); send(actions.setMode, ["mode": value])
          }
        }
        if !block.fanModes.isEmpty {
          segments(
            title: block.fanLabel,
            options: block.fanModes.map { ClipSegment(id: $0.value, label: $0.label) },
            selected: fanMode ?? ""
          ) { value in
            draftFan = value; hold(); send(actions.setFanMode, ["fanMode": value])
          }
        }
      }
    }
    .padding(20)
    .background(accent.opacity(isOn ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(accent.opacity(isOn ? 0.18 : 0.08)))
    .animation(.easeInOut(duration: 0.25), value: mode)
    .onChange(of: block.state) {
      if draftMode == state?.mode { draftMode = nil }
      if draftFan == state?.fanMode { draftFan = nil }
      if draftTemperature == state?.temperature { draftTemperature = nil }
    }
    .onDisappear { sendTemperature?.cancel(); expireDraft?.cancel() }
  }

  private var status: Text {
    guard state != nil else { return Text(verbatim: block.unknownStatus) }
    let head = isOn ? block.label(forMode: mode) : block.offLabel
    let line = [head, block.roomText].compactMap { $0 }.joined(separator: " · ")
    return Text(verbatim: line)
  }

  private func powerButton(on: Bool) -> some View {
    Button { send(on ? actions.on : actions.off) } label: {
      HStack(spacing: 10) {
        if busy { ProgressView() } else { Image(systemName: "power") }
        Text(verbatim: on ? block.turnOnLabel : block.turnOffLabel)
      }.frame(maxWidth: .infinity).padding(.vertical, 12)
    }.clipActionStyle(primary: on)
  }

  private func temperatureRow(_ value: Double) -> some View {
    HStack(spacing: 12) {
      round("minus", label: block.lowerTemperatureLabel, disabled: value <= (state?.minTemperature ?? 16)) { nudge(-1) }
      Spacer(minLength: 0)
      VStack(spacing: 2) {
        HStack(alignment: .top, spacing: 2) {
          Text(verbatim: degrees(value)).font(.system(size: 64, weight: .light, design: .rounded)).monospacedDigit()
            .contentTransition(.numericText(value: value))
          Text(verbatim: "°").font(.system(size: 30, weight: .light, design: .rounded)).padding(.top, 6)
        }.foregroundStyle(accent)
        Text(verbatim: block.temperatureLabel).font(.footnote).foregroundStyle(.secondary)
      }
      .accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      round("plus", label: block.raiseTemperatureLabel, disabled: value >= (state?.maxTemperature ?? 30)) { nudge(1) }
    }
    .animation(.snappy, value: value)
  }

  private func round(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol).font(.title2.weight(.medium)).foregroundStyle(accent)
        .frame(width: 56, height: 56)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }
    .buttonStyle(.plain)
    .opacity(disabled ? 0.35 : 1)
    .disabled(disabled)
    .accessibilityLabel(Text(verbatim: label))
  }

  private func segments(
    title: String, options: [ClipSegment], selected: String, choose: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(verbatim: title).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
      // Up to six speeds or modes share one row.
      ClipSegmentedControl(segments: options, selected: selected, accent: accent, fits: 6) { value in
        if value != selected { choose(value) }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel(Text(verbatim: title))
    }
  }

  private func send(_ action: String, _ extra: [String: Any] = [:]) {
    Task { await model.climate(action, extra, blockId: block.id) }
  }

  /// Keep a choice on screen while Home Assistant catches up, but not forever.
  private func hold() {
    expireDraft?.cancel()
    expireDraft = Task {
      try? await Task.sleep(for: .seconds(6))
      guard !Task.isCancelled else { return }
      draftMode = nil; draftFan = nil; draftTemperature = nil
    }
  }

  private func nudge(_ direction: Int) {
    guard let state, let current = temperature else { return }
    let next = state.nudged(current, by: direction)
    guard next != current else { return }
    draftTemperature = next
    hold()
    sendTemperature?.cancel()
    sendTemperature = Task {
      // Presses are gathered: each one starts the wait again, so stepping through several
      // degrees sends one request instead of one per press.
      try? await Task.sleep(for: .milliseconds(1000))
      // A press made while another action runs waits for it rather than being dropped.
      while !Task.isCancelled && busy { try? await Task.sleep(for: .milliseconds(200)) }
      guard !Task.isCancelled, let wanted = draftTemperature else { return }
      hold()
      await model.climate(actions.setTemperature, ["temperature": wanted], blockId: block.id)
    }
  }
}
