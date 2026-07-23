import SwiftUI

enum DiscoverTypography {
    static let editorialKicker = Font.system(.caption2, design: .rounded, weight: .semibold)
    static let editionDate = Font.system(.caption, design: .rounded, weight: .medium)
    static let sectionTitle = Font.title2.weight(.semibold)
    static let sectionSubtitle = Font.system(.caption2, design: .rounded, weight: .semibold)
    static let featureTitle = Font.largeTitle.weight(.semibold)
    static let featureDescription = Font.body
    static let featureTeaser = Font.callout
    static let newsCardTitle = Font.headline
    static let newsRailTitle = Font.title3.weight(.semibold)
    static let newsCardDescription = Font.caption
    static let compactRank = Font.system(.callout, design: .rounded, weight: .semibold)
    static let compactTitle = Font.callout.weight(.medium)
    static let compactDescription = Font.caption
    static let storyBody = Font.body
    static let mediaTitle = Font.title3.weight(.semibold)
    static let mediaDescription = Font.callout
    static let mediaMeta = Font.caption.weight(.medium)
    static let cardTitle = Font.headline
    static let cardBody = Font.callout
    static let cardMetadata = Font.caption
    static let controlLabel = Font.callout.weight(.semibold)
    static let controlAuxiliary = Font.caption.weight(.medium)
    static let statistic = Font.caption.weight(.semibold)
    static let popoverTitle = Font.headline

    static func mastheadTitle(isCompact: Bool) -> Font {
        isCompact ? .title.weight(.semibold) : .largeTitle.weight(.semibold)
    }
}

struct DiscoverFeatureModule: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let trendPulse: WikipediaService.TrendPulse?
    let isTrendPulseLoading: Bool
    let visualContextImages: [WikipediaService.VisualContextImage]
    let isVisualContextLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let isCompactLayout: Bool
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let onOpenURL: (URL) -> Void
    let onTrendTapped: (WikipediaService.TrendPulse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DiscoverFeatureCard(
                result: result,
                teaserText: teaserText,
                isTeaserLoading: isTeaserLoading,
                trendPulse: trendPulse,
                isTrendPulseLoading: isTrendPulseLoading,
                heroImageHeight: heroImageHeight,
                titleLineLimit: titleLineLimit,
                descriptionLineLimit: descriptionLineLimit,
                onOpen: onOpen,
                onTrendTapped: onTrendTapped
            )

            Group {
                if isVisualContextLoading {
                    AppLoadingInlineLabel(
                        text: "Loading visual context…",
                        tone: .accent,
                        font: .system(size: 12.5, weight: .medium)
                    )
                    .padding(.vertical, 6)
                } else if !visualContextImages.isEmpty {
                    DiscoverVisualContextStrip(
                        images: visualContextImages,
                        isCompactLayout: isCompactLayout,
                        showsSurface: false,
                        onOpenURL: onOpenURL
                    )
                } else {
                    Text(DiscoverEditionCopy.visualContextUnavailable)
                        .font(DiscoverTypography.cardBody.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiscoverFeatureCard: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let trendPulse: WikipediaService.TrendPulse?
    let isTrendPulseLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let onTrendTapped: (WikipediaService.TrendPulse) -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var displayTitle: String {
        let trimmed = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Featured Story" : trimmed
    }

    private var displayDescription: String? {
        guard let description = result.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else {
            return nil
        }
        return description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onOpen(result, SystemBridge.isCommandPressed)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if result.thumbnailURL != nil {
                        featureImage
                            .frame(maxWidth: .infinity)
                            .frame(height: heroImageHeight)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(DiscoverEditionCopy.leadKicker)
                            .font(DiscoverTypography.editorialKicker)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)

                        Text(displayTitle)
                            .font(DiscoverTypography.featureTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(titleLineLimit)
                            .lineSpacing(2)

                        if let displayDescription {
                            Text(displayDescription)
                                .font(DiscoverTypography.featureDescription)
                                .foregroundStyle(.secondary)
                                .lineLimit(descriptionLineLimit)
                                .lineSpacing(1.5)
                        }

                        if isTeaserLoading {
                            AppLoadingInlineLabel(
                                text: "Loading article teaser…",
                                tone: .accent,
                                font: .system(size: 11.5, weight: .medium)
                            )
                            .padding(.top, 2)
                        } else if let teaserText, !teaserText.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(teaserText)
                                    .font(DiscoverTypography.featureTeaser)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(9)
                                    .lineSpacing(1.45)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(16)
                }
            }
            .buttonStyle(DiscoverInteractivePressStyle())
            .accessibilityLabel(displayTitle)

            featuredStats
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(minHeight: result.thumbnailURL == nil ? 0 : heroImageHeight + 72)
        .discoverSurfaceChrome(
            cornerRadius: 14,
            material: .regular,
            borderOpacity: isHovered ? 0.46 : 0.32,
            borderWidth: 0.8
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .discoverHoverEffect(.hero, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var featuredStats: some View {
        if let trendPulse {
            DiscoverTrendPulseBadge(
                pulse: trendPulse,
                onTap: {
                    onTrendTapped(trendPulse)
                }
            )
            .padding(.top, 3)
        } else if isTrendPulseLoading {
            AppLoadingInlineLabel(
                text: "Loading page views…",
                tone: .accent,
                font: .system(size: 11.5, weight: .medium)
            )
            .padding(.top, 3)
        }
    }

    @ViewBuilder
    private var featureImage: some View {
        if let thumbnailURL = result.thumbnailURL {
            CachedThumbnailImage(
                url: thumbnailURL,
                targetSize: CGSize(width: 980, height: heroImageHeight),
                animatesNetworkSuccess: !reduceMotion
            ) { image in
                ZStack {
                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                }
            } placeholder: {
                AppLoadingThumbnailPlaceholder(
                    width: 320,
                    height: heroImageHeight,
                    cornerRadius: 14,
                    tone: .accent
                )
            } failure: {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.25), Color.blue.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }
}
