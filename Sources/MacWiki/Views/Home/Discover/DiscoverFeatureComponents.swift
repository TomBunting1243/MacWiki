import SwiftUI

enum DiscoverTypography {
    static let sectionTitle = Font.system(size: 20, weight: .semibold)
    static let sectionSubtitle = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    static let featureTitle = Font.system(size: 29, weight: .semibold)
    static let featureDescription = Font.system(size: 14, weight: .regular)
    static let newsCardTitle = Font.system(size: 14.5, weight: .semibold)
    static let newsRailTitle = Font.system(size: 15, weight: .semibold)
    static let newsCardDescription = Font.system(size: 11.5, weight: .regular)
    static let compactRank = Font.system(size: 14.5, weight: .semibold, design: .rounded)
    static let compactTitle = Font.system(size: 12.5, weight: .medium)
    static let compactDescription = Font.system(size: 11, weight: .regular)
    static let storyBody = Font.system(size: 14, weight: .regular)
    static let mediaTitle = Font.system(size: 16.5, weight: .semibold, design: .rounded)
    static let mediaDescription = Font.system(size: 12.5, weight: .regular)
    static let mediaMeta = Font.system(size: 11.5, weight: .medium)
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
        VStack(alignment: .leading, spacing: 0) {
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
                onTrendTapped: onTrendTapped,
                showsSurface: false
            )
            .padding(12)

            Divider()
                .overlay(Color.primary.opacity(0.05))

            Group {
                if isVisualContextLoading {
                    AppLoadingInlineLabel(
                        text: "Loading visual context…",
                        tone: .accent,
                        font: .system(size: 12.5, weight: .medium)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else if !visualContextImages.isEmpty {
                    DiscoverVisualContextStrip(
                        images: visualContextImages,
                        isCompactLayout: isCompactLayout,
                        showsSurface: false,
                        onOpenURL: onOpenURL
                    )
                    .padding(12)
                } else {
                    Text(DiscoverEditionCopy.visualContextUnavailable)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .discoverSurfaceChrome(
            cornerRadius: 16,
            material: .regular,
            borderOpacity: 0.34
        )
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
    var showsSurface: Bool = true
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
                    featureImage
                        .frame(maxWidth: .infinity)
                        .frame(height: heroImageHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(DiscoverEditionCopy.leadKicker)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                                    .font(.system(size: 13.5, weight: .regular))
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
        .frame(minHeight: heroImageHeight + 72)
        .discoverSurfaceChrome(
            isEnabled: showsSurface,
            cornerRadius: 14,
            material: .regular,
            borderOpacity: isHovered ? 0.46 : 0.32,
            borderWidth: 0.8
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if !showsSurface {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.36 : 0.18), lineWidth: 0.7)
            }
        }
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
                tone: .retro,
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
                        .aspectRatio(contentMode: .fill)
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
        } else {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.25), Color.blue.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
