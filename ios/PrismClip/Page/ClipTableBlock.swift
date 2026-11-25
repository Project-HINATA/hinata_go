import SwiftUI

struct ClipTableBlock: View {
  let table: PrismPageTable
  var body: some View {
    VStack(spacing: 16) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 4) {
          Text(verbatim: table.title).font(.title3.weight(.semibold))
          Text(verbatim: table.status).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer()
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text("\(table.seats.count)").font(.title2.weight(.semibold))
          Text("/ \(table.capacity)").font(.body).foregroundStyle(.secondary)
        }.monospacedDigit()
      }
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
        ForEach(0..<table.capacity, id: \.self) { index in
          let seat = index < table.seats.count ? table.seats[index] : nil
          VStack(alignment: .leading, spacing: 6) {
            if let seat { Text(verbatim: seat.name).font(.body.weight(.medium)) }
            else { Text(verbatim: table.emptyLabel).font(.body).foregroundStyle(.tertiary) }
            if seat?.mine == true { Text(verbatim: table.mineLabel).font(.caption).foregroundStyle(.secondary) }
          }
          .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
          .padding(16)
          .background(prismCardFill.opacity(seat == nil ? 0 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(seat?.mine == true ? 0.3 : seat == nil ? 0.08 : 0), lineWidth: seat?.mine == true ? 1.5 : 1))
        }
      }
    }.frame(maxWidth: .infinity)
  }
}

/// The player's air conditioner, matching the Web device page. Off, it is one button; on,
/// the target temperature is the centre with round − and + either side, and mode and fan
/// speed are segmented rows underneath. The card takes the running mode's colour.
///
/// A choice is shown at once and gives way to what Home Assistant reports, or falls back
/// after a few seconds if it never does. Quick − / + presses are sent as one temperature, so
/// an on-site location fix is not taken for every step.
