import SwiftUI

struct ArticleLoadingSkeletonView: View {
    enum Phase {
        case fetching
        case rendering

        var title: String {
            switch self {
            case .fetching:
                return "Loading Article"
            case .rendering:
                return "Preparing Reader"
            }
        }

        var symbol: String {
            switch self {
            case .fetching:
                return "bolt.horizontal.circle.fill"
            case .rendering:
                return "text.below.photo.fill"
            }
        }
    }

    let articleTitle: String
    let phase: Phase

    @Environment(\.readerChromeMetrics) private var readerChromeMetrics

    private func resolvedTopPadding(for availableWidth: CGFloat, topSafeArea: CGFloat) -> CGFloat {
        let chromeInset = max(topSafeArea, readerChromeMetrics.topObscuredHeight)
        let compactWidthBoost: CGFloat
        switch availableWidth {
        case ..<520:
            compactWidthBoost = 14
        case ..<620:
            compactWidthBoost = 10
        case ..<680:
            compactWidthBoost = 6
        default:
            compactWidthBoost = 0
        }
        return chromeInset + 18 + compactWidthBoost
    }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max(320, min(920, proxy.size.width - 40))
            let topPadding = resolvedTopPadding(for: proxy.size.width, topSafeArea: proxy.safeAreaInsets.top)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AppLoadingStatusCapsule(
                        title: phase.title,
                        detail: articleTitle,
                        symbol: phase.symbol,
                        tone: .neutral
                    )
                    headerBlock(columnWidth: columnWidth)
                    paragraphBlock(columnWidth: columnWidth, widths: [0.97, 0.92, 0.95, 0.88, 0.72])
                    AppLoadingSkeletonBar(
                        width: columnWidth,
                        height: 210,
                        cornerRadius: 14,
                        tone: .neutral
                    )
                    AppLoadingSkeletonBar(
                        width: columnWidth * 0.34,
                        height: 24,
                        cornerRadius: 8,
                        tone: .neutral
                    )
                    paragraphBlock(columnWidth: columnWidth, widths: [0.96, 0.93, 0.90, 0.94, 0.81])
                    paragraphBlock(columnWidth: columnWidth, widths: [0.94, 0.91, 0.86, 0.89, 0.64])
                }
                .frame(width: columnWidth, alignment: .leading)
                .padding(.top, topPadding)
                .padding(.bottom, 56)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func headerBlock(columnWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppLoadingSkeletonBar(
                width: columnWidth * 0.74,
                height: 46,
                cornerRadius: 12,
                tone: .neutral
            )
            AppLoadingSkeletonBar(
                width: columnWidth * 0.45,
                height: 14,
                cornerRadius: 7,
                tone: .neutral
            )
        }
    }

    private func paragraphBlock(columnWidth: CGFloat, widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, fraction in
                AppLoadingSkeletonBar(
                    width: max(140, columnWidth * fraction),
                    height: index == widths.count - 1 ? 12 : 13,
                    cornerRadius: 6,
                    tone: .neutral
                )
            }
        }
    }
}
