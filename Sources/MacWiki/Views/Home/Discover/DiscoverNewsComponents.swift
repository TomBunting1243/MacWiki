import SwiftUI

struct DiscoverNewsCard: View {
    let result: WikipediaService.SearchResult
    var style: DiscoverNewsCardStyle = .standard
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            if style == .rail {
                HStack(alignment: .top, spacing: 10) {
                    newsThumbnail
                        .frame(width: 94, height: 94)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.title)
                            .font(DiscoverTypography.newsRailTitle)
                            .lineLimit(3)
                            .lineSpacing(1.2)
                        if let description = result.description {
                            Text(description)
                                .font(DiscoverTypography.newsCardDescription)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(1.1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    newsThumbnail
                        .frame(height: 120)
                    Text(result.title)
                        .font(DiscoverTypography.newsCardTitle)
                        .lineLimit(2)
                        .lineSpacing(1.2)
                    if let description = result.description {
                        Text(description)
                            .font(DiscoverTypography.newsCardDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(1.1)
                    }
                }
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .padding(style == .rail ? 10 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.46 : 0.32), lineWidth: 0.7)
        }
        .discoverHoverEffect(.card, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var newsThumbnail: some View {
        if let thumbnailURL = result.thumbnailURL {
            CachedThumbnailImage(
                url: thumbnailURL,
                targetSize: style.thumbnailTargetSize,
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
                    width: style.thumbnailTargetSize.width,
                    height: style.thumbnailTargetSize.height,
                    cornerRadius: 10,
                    tone: .accent
                )
            } failure: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
            }
            .frame(width: style == .rail ? style.thumbnailTargetSize.width : nil)
            .frame(maxWidth: style == .standard ? .infinity : nil)
            .frame(height: style.thumbnailTargetSize.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

enum DiscoverNewsCardStyle {
    case standard
    case rail

    var thumbnailTargetSize: CGSize {
        switch self {
        case .standard:
            return CGSize(width: 220, height: 116)
        case .rail:
            return CGSize(width: 94, height: 94)
        }
    }
}

struct DiscoverCompactArticleCard: View {
    let result: WikipediaService.SearchResult
    let rank: Int
    let trendPulse: WikipediaService.TrendPulse?
    var onTrendTapped: ((WikipediaService.TrendPulse) -> Void)? = nil
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @State private var suppressPrimaryTapFromTrend = false

    var body: some View {
        Button {
            if suppressPrimaryTapFromTrend {
                suppressPrimaryTapFromTrend = false
                return
            }
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            HStack(spacing: 9) {
                Text("\(rank)")
                    .font(DiscoverTypography.compactRank)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading)

                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 62,
                    cornerRadius: 8,
                    imagePadding: 4
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(DiscoverTypography.compactTitle)
                        .lineLimit(2)
                        .lineSpacing(1.05)
                    if let description = result.description {
                        Text(description)
                            .font(DiscoverTypography.compactDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(1.0)
                    }
                    if let trendPulse {
                        DiscoverTrendPulseBadge(
                            pulse: trendPulse,
                            onTap: {
                                suppressPrimaryTapFromTrend = true
                                onTrendTapped?(trendPulse)
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    suppressPrimaryTapFromTrend = false
                                }
                            }
                        )
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DiscoverTrendPulseBadge: View {
    let pulse: WikipediaService.TrendPulse
    var onTap: (() -> Void)? = nil

    private var deltaFraction: Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return (Double(pulse.latestViews - previous) / Double(previous))
    }

    private var deltaText: String {
        ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews
        )
    }

    private var trendSymbol: String {
        guard let deltaFraction else { return "chart.line.uptrend.xyaxis" }
        return deltaFraction < 0 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis"
    }

    private var trendColor: Color {
        guard let deltaFraction else { return .secondary }
        if deltaFraction > 0 { return Color.green.opacity(0.85) }
        if deltaFraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    private var latestViewsText: String {
        abbreviatedViewCount(pulse.latestViews)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: trendSymbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(trendColor)

            DiscoverSparkline(points: pulse.points, tint: trendColor)
                .frame(width: 54, height: 14)

            Text(deltaText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(trendColor)
                .lineLimit(1)

            Text("\(latestViewsText) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(trendColor.opacity(0.10), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(trendColor.opacity(0.18), lineWidth: 0.7)
        }
        .contentShape(Capsule())
        .highPriorityGesture(
            TapGesture().onEnded {
                onTap?()
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(deltaText), \(latestViewsText) views")
        .accessibilityHint("Show views details")
        .accessibilityAction {
            onTap?()
        }
        .help("Show views details")
    }
}
