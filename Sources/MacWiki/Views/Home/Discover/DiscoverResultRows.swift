import Foundation
import SwiftUI

struct DiscoverHolidayRow: View {
    let holiday: WikipediaService.DiscoverFeed.HolidayItem
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    var showsSurface: Bool = true
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var showingPageViewsPopover = false
    @State private var isHovered = false

    var body: some View {
        Group {
            if let article = holiday.article {
                Button {
                    onOpen(article, SystemBridge.isCommandPressed)
                } label: {
                    rowContent
                }
            } else {
                rowContent
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(holiday.article?.title ?? holiday.text)
        .padding(10)
        .discoverSurfaceChrome(
            isEnabled: showsSurface,
            cornerRadius: 12,
            borderOpacity: isHovered ? 0.44 : 0.30
        )
        .background {
            if !showsSurface {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.04 : 0.018))
            }
        }
        .overlay {
            if !showsSurface {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.44 : 0.30), lineWidth: 0.7)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: showsSurface ? 12 : 14, style: .continuous))
        .discoverHoverEffect(.row, isActive: isHovered && holiday.article != nil, reduceMotion: reduceMotion)
        .onHover { isHovered = holiday.article != nil && $0 }
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

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(holiday.text)
                    .font(MacWikiTypography.compactRowBody)
                    .lineLimit(3)
                if let article = holiday.article {
                    Text(article.title)
                        .font(MacWikiTypography.compactRowMetadata)
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 0)
        }
    }

}

struct DiscoverSearchResultRow: View {
    let result: WikipediaService.SearchResult
    let isSaved: Bool
    let isKeyboardFocused: Bool
    let onOpen: () -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 50,
                    cornerRadius: 9,
                    imagePadding: 3
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(MacWikiTypography.compactRowTitle)
                    if let description = result.description {
                        Text(description)
                            .font(MacWikiTypography.settingsHelp)
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
            .padding(.vertical, 10)
            .discoverSurfaceChrome(
                cornerRadius: 14,
                tintColors: isKeyboardFocused ? [Color.accentColor.opacity(0.12), .clear] : [],
                borderColor: isKeyboardFocused ? Color.accentColor : Color(nsColor: .separatorColor),
                borderOpacity: isKeyboardFocused ? 0.66 : (isHovered ? 0.46 : 0.32),
                borderWidth: isKeyboardFocused ? 1.1 : 0.7
            )
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .accessibilityValue(isSaved ? "Saved" : "Not Saved")
        .accessibilityAddTraits(isKeyboardFocused ? .isSelected : [])
        .discoverHoverEffect(.row, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
