import Foundation
import SwiftUI

struct DiscoverHolidayRow: View {
    let holiday: WikipediaService.DiscoverFeed.HolidayItem
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    var showsSurface: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingPageViewsPopover = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if let article = holiday.article {
                onOpen(article, SystemBridge.isCommandPressed)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(holiday.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                    if let article = holiday.article {
                        Text(article.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(holiday.article?.title ?? holiday.text)
        .padding(10)
        .background(
            Group {
                if showsSurface {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.048 : 0.026))
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: showsSurface ? 12 : 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.15 : (showsSurface ? 0.08 : 0.05)), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: showsSurface ? 12 : 14, style: .continuous))
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let article = holiday.article {
                ArticleQuickActionsMenuContent(
                    title: article.title,
                    onOpen: { onOpen(article, false) },
                    onOpenInNewTab: { onOpen(article, true) },
                    onShowPageViews: { showingPageViewsPopover = true }
                )
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = holiday.article {
                DiscoverPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

}

struct DiscoverSearchResultRow: View {
    let result: WikipediaService.SearchResult
    let isSaved: Bool
    let onOpen: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 44,
                    cornerRadius: 8,
                    imagePadding: 3
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 14, weight: .semibold))
                    if let description = result.description {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0), lineWidth: 0.8)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
    }
}
