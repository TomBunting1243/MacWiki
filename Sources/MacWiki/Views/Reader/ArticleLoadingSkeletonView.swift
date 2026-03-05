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

    @AppStorage("tabBarLiquidGlass") private var tabBarLiquidGlass = true
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = -1.1
    @State private var isShimmerAnimating = false

    private func resolvedTopPadding(for availableWidth: CGFloat) -> CGFloat {
        // In liquid-glass mode, the reader content underlaps the tab strip + toolbar lane.
        // Keep the skeleton status capsule clear of the chrome and add a compact-width bump.
        guard tabBarLiquidGlass, !appState.isWikiHopNavigationLocked else {
            switch availableWidth {
            case ..<520: return 30
            case ..<680: return 26
            default: return 24
            }
        }
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
        return ColumnChromeMetrics.readerContentTopInset(
            windowTopObscuredHeight: appState.windowTopObscuredHeight,
            additionalSpacing: 20 + compactWidthBoost
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max(320, min(920, proxy.size.width - 40))
            let topPadding = resolvedTopPadding(for: proxy.size.width)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statusCapsule
                    headerBlock(columnWidth: columnWidth)
                    paragraphBlock(columnWidth: columnWidth, widths: [0.97, 0.92, 0.95, 0.88, 0.72])
                    SkeletonBar(
                        width: columnWidth,
                        height: 210,
                        cornerRadius: 14,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: !reduceMotion
                    )
                    SkeletonBar(
                        width: columnWidth * 0.34,
                        height: 24,
                        cornerRadius: 8,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: !reduceMotion
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
        .onAppear {
            updateShimmerAnimation()
        }
        .onChange(of: reduceMotion) { _, _ in
            updateShimmerAnimation()
        }
        .onDisappear {
            isShimmerAnimating = false
        }
    }

    private func updateShimmerAnimation() {
        if reduceMotion {
            isShimmerAnimating = false
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                shimmerPhase = -1.1
            }
            return
        }

        guard !isShimmerAnimating else { return }
        isShimmerAnimating = true
        shimmerPhase = -1.1
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.1
        }
    }

    private var statusCapsule: some View {
        ViewThatFits {
            HStack(spacing: 8) {
                Image(systemName: phase.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(phase.title)
                    .font(.caption.weight(.semibold))
                Text(articleTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Image(systemName: phase.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(phase.title)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
        )
    }

    private func headerBlock(columnWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBar(
                width: columnWidth * 0.74,
                height: 46,
                cornerRadius: 12,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: !reduceMotion
            )
            SkeletonBar(
                width: columnWidth * 0.45,
                height: 14,
                cornerRadius: 7,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: !reduceMotion
            )
        }
    }

    private func paragraphBlock(columnWidth: CGFloat, widths: [CGFloat]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(widths.enumerated()), id: \.offset) { index, fraction in
                SkeletonBar(
                    width: max(140, columnWidth * fraction),
                    height: index == widths.count - 1 ? 12 : 13,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: !reduceMotion
                )
            }
        }
    }
}

private struct SkeletonBar: View {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10),
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseGradient)
            .overlay {
                if shimmerEnabled {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.white.opacity(colorScheme == .dark ? 0.24 : 0.48),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .rotationEffect(.degrees(15))
                        .offset(x: shimmerPhase * width)
                        .blendMode(.screen)
                        .clipped()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14), lineWidth: 0.7)
            )
            .frame(width: width, height: height)
    }
}
