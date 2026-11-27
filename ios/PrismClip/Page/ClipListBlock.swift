import SwiftUI

/// Renders a server-driven `list` block (e.g. checkout history) with optional date-grouped
/// light cards, shop-timezone timestamps, drill-down navigation, and `moreTarget` pagination.
struct ClipListBlock: View {
  let list: PrismPageList
  let context: ClipPageContext

  private struct ItemGroup: Identifiable {
    let id: String
    let label: String
    let items: [PrismPageListItem]
  }

  private var displayZone: TimeZone {
    list.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
  }

  private var hasGroups: Bool {
    list.items.contains { !($0.group ?? "").isEmpty }
  }

  private var groupedItems: [ItemGroup] {
    var groups: [(label: String, items: [PrismPageListItem])] = []
    for item in list.items {
      let label = item.group ?? ""
      if let lastIndex = groups.indices.last, groups[lastIndex].label == label {
        groups[lastIndex].items.append(item)
      } else {
        groups.append((label: label, items: [item]))
      }
    }
    return groups.enumerated().map { index, group in
      ItemGroup(id: "\(index)-\(group.label)", label: group.label, items: group.items)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if list.items.isEmpty, let emptyText = list.emptyText {
        VStack(spacing: 16) {
          Image(systemName: list.emptyIcon == "inbox" ? "tray" : "doc.text")
            .font(.largeTitle)
          Text(verbatim: emptyText)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
      } else if hasGroups {
        VStack(alignment: .leading, spacing: 18) {
          ForEach(groupedItems) { group in
            VStack(alignment: .leading, spacing: 8) {
              if !group.label.isEmpty {
                Text(verbatim: group.label)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 4)
              }
              VStack(spacing: 0) {
                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                  if index > 0 { Divider() }
                  row(for: item, grouped: true).id(item.id)
                }
              }
              .background(prismCardFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
          }
        }
      } else {
        ForEach(list.items) { item in
          row(for: item, grouped: false).id(item.id)
        }
      }
      if let moreTarget = list.moreTarget, let moreLabel = list.moreLabel {
        let loadingMore = context.loadingMoreId == list.id
        Button {
          context.loadMore?(list.id, moreTarget)
        } label: {
          HStack(spacing: 10) {
            if loadingMore { ProgressView() }
            Text(verbatim: moreLabel)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        }
        .clipActionStyle()
        .disabled(loadingMore || context.busy)
        .padding(.top, 20)
      }
      if let failure = context.loadMoreError, failure.blockId == list.id {
        Text(verbatim: failure.message)
          .font(.subheadline)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  @ViewBuilder private func row(for item: PrismPageListItem, grouped: Bool) -> some View {
    let title = item.titleTimestamp.map { prismDisplayDate($0, timeZone: displayZone) } ?? item.title
    let subtitle: String? = {
      if let ts = item.subtitleTimestamp {
        return (item.subtitlePrefix ?? "") + prismDisplayDate(ts, timeZone: displayZone)
      }
      if let sub = item.subtitle {
        return (item.subtitlePrefix ?? "") + sub
      }
      return nil
    }()
    let titleView: Text = {
      let base = Text(verbatim: title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
      if let meta = item.titleMeta, !meta.isEmpty {
        return base + Text(verbatim: "  \(meta)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      return base
    }()
    let bodyContent = HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        titleView.monospacedDigit()
        if let subtitle {
          Text(verbatim: subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
      }
      Spacer(minLength: 12)
      if let trailing = item.trailing {
        VStack(alignment: .trailing, spacing: 2) {
          Text(verbatim: trailing)
            .font(.headline.weight(.semibold))
            .monospacedDigit()
            .fixedSize()
            .foregroundStyle(.primary)
          if let orig = item.trailingStrikethrough, !orig.isEmpty {
            Text(verbatim: orig)
              .font(.caption)
              .strikethrough()
              .monospacedDigit()
              .fixedSize()
              .foregroundStyle(.secondary)
          }
        }
      }
      if item.open != nil {
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }
    }
    .padding(.horizontal, grouped ? 16 : 0)
    .padding(.vertical, grouped ? 14 : 18)
    .contentShape(Rectangle())
    .overlay(alignment: .bottom) {
      if !grouped {
        Divider().frame(height: 1)
      }
    }

    if let target = item.open {
      Button {
        context.openTarget?(target)
      } label: {
        bodyContent
      }
      .buttonStyle(.plain)
      .disabled(context.busy)
    } else {
      bodyContent
    }
  }
}
