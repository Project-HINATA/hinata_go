import SwiftUI

struct ClipTextBlock: View {
  let text: String
  let style: String?
  let level: String?

  var body: some View {
    if style == "heading" {
      let color: Color? = level == "error" ? .red : (level == "muted" ? .secondary : nil)
      Text(verbatim: text).font(.title2).modifier(ClipLabelTint(color: color))
        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
    } else if level == "error" {
      Text(verbatim: text).font(style == "caption" ? .caption : (style == "body" ? .body : .subheadline)).foregroundStyle(.red)
    } else if style == "body" {
      Text(verbatim: text).font(.body)
        .foregroundStyle(level == "muted" ? .secondary : .primary)
        .multilineTextAlignment(.leading)
    } else if style == "caption" {
      Text(verbatim: text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
    } else {
      Text(verbatim: text).font(.subheadline).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }
  }
}

struct ClipSectionBlock: View {
  @Environment(\.prismInCard) private var inCard
  let section: PrismPageSection
  let depth: Int
  let context: ClipPageContext

  var body: some View {
    let isCard = section.style == "card"
    let content = VStack(alignment: .leading, spacing: 16) {
      if section.title != nil || section.subtitle != nil {
        VStack(alignment: .leading, spacing: 4) {
          if let title = section.title { Text(verbatim: title).font(.title3.weight(.semibold)) }
          if let subtitle = section.subtitle { Text(verbatim: subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
      }
      ClipPageBlockList(blocks: section.blocks, depth: depth + 1, context: context)
        .environment(\.prismInCard, inCard || isCard)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    if isCard {
      content.padding(20).background(prismCardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    } else {
      content
    }
  }
}

struct ClipRowBlock: View {
  let row: PrismPageRow
  let depth: Int
  let context: ClipPageContext

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ForEach(row.blocks.filter(context.shows)) { child in
        ClipPageBlockView(block: child, depth: depth + 1, context: context)
          .frame(maxWidth: .infinity)
      }
    }
  }
}

struct ClipKeyValueBlock: View {
  let kv: PrismPageKeyValue

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(kv.items.enumerated()), id: \.offset) { index, item in
        if index > 0 { Divider() }
        let iconName = symbol(for: item.icon)
        let badgeText = item.badge.flatMap { $0.isEmpty ? nil : $0 }
        if iconName != nil || badgeText != nil {
          let badgeColor = color(item.badgeTone ?? item.tone)
          HStack(alignment: .center, spacing: 14) {
            if let iconName {
              Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(badgeColor)
                .frame(width: 38, height: 38)
                .background(badgeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
              Text(verbatim: item.label)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
              if let badgeText {
                Text(verbatim: badgeText)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(badgeColor)
                  .padding(.horizontal, 9)
                  .padding(.vertical, 3)
                  .background(badgeColor.opacity(0.12), in: Capsule())
              }
            }
            Spacer(minLength: 12)
            Text(verbatim: item.value)
              .font(.headline.weight(item.tone == "muted" ? .regular : .semibold))
              .monospacedDigit()
              .foregroundStyle(color(item.tone))
              .multilineTextAlignment(.trailing)
          }
          .padding(.vertical, 18)
        } else {
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: item.label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(verbatim: item.value)
              .font(.subheadline.weight(item.tone == "muted" ? .regular : .semibold))
              .monospacedDigit()
              .foregroundStyle(color(item.tone))
              .multilineTextAlignment(.trailing)
          }
          .padding(.vertical, 18)
        }
      }
    }
  }

  private func symbol(for icon: String?) -> String? {
    switch icon {
    case "wallet": return "wallet.pass.fill"
    case "gift": return "gift.fill"
    case "coins": return "banknote.fill"
    case "coupon": return "ticket.fill"
    case "pass": return "checkmark.seal.fill"
    case "ticket": return "tag.fill"
    case "asset": return "sparkles"
    default: return nil
    }
  }

  private func color(_ tone: String?) -> Color {
    switch tone {
    case "muted": return .secondary
    case "accent": return .blue
    case "success": return .green
    case "warning": return .orange
    case "error": return .red
    case "purple": return .purple
    default: return .primary
    }
  }
}

struct ClipBannerBlock: View {
  let banner: PrismPageBanner

  var body: some View {
    let level = banner.level ?? "info"
    let tint = color(level)
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: noticeSymbol(level)).font(.title3).foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 4) {
        if let title = banner.title { Text(verbatim: title).font(.subheadline.weight(.semibold)) }
        Text(verbatim: banner.body).font(.subheadline).foregroundStyle(.primary.opacity(0.85))
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.2)))
  }

  private func color(_ level: String) -> Color {
    switch level {
    case "success": return .green
    case "warning": return .orange
    case "error": return .red
    default: return .blue
    }
  }
}

struct ClipImageBlock: View {
  @EnvironmentObject private var model: MachineLoginViewModel
  let image: PrismPageImage

  var body: some View {
    if let url = PrismPage.resolveImageURL(image.url, origin: model.api.baseURL) {
      if let ratio = image.aspectRatio, ratio > 0 {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let loaded): loaded.resizable().scaledToFill()
          case .empty: Color.primary.opacity(0.04)
          default: EmptyView()
          }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(CGFloat(ratio), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(Text(verbatim: image.alt ?? ""))
      } else {
        AsyncImage(url: url) { phase in
          switch phase {
          case .success(let loaded): loaded.resizable().scaledToFit()
          case .empty: Color.primary.opacity(0.04).frame(height: 160)
          default: EmptyView()
          }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(Text(verbatim: image.alt ?? ""))
      }
    }
  }
}
