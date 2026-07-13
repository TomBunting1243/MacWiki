import SwiftUI

enum AppLoadingMotion {
    static let overlayScale: CGFloat = 0.992
    static let overlayEntrance = Animation.easeOut(duration: 0.18)
    static let overlaySettle = Animation.spring(response: 0.28, dampingFraction: 0.90)
    static let skeletonRevealDuration: Double = 0.14
    static let skeletonHideDuration: Double = 0.18
    static let skeletonMinimumVisibleDuration: TimeInterval = 0.18
    fileprivate static let shimmerDuration: TimeInterval = 1.18

    static func overlayTransition(
        reduceMotion: Bool,
        anchor: UnitPoint = .center
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .opacity.combined(with: .scale(scale: overlayScale, anchor: anchor))
    }
}

struct AppLoadingStatusCapsule: View {
    let title: String
    var detail: String? = nil
    var symbol: String = "arrow.triangle.2.circlepath"
    var tone: AppLoadingTone = .neutral
    var tint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ViewThatFits {
            capsuleLayout(showsDetail: true)
            capsuleLayout(showsDetail: false)
        }
    }

    private func capsuleLayout(showsDetail: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.accentColor(for: colorScheme, override: tint))
                .frame(width: 22, height: 22)
                .background(
                    tone.iconPlateFill(for: colorScheme, override: tint),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            if showsDetail, let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(tone.strokeColor(for: colorScheme).opacity(0.72), lineWidth: 0.8)
        }
    }
}

struct AppLoadingActivityMark: View {
    var tone: AppLoadingTone = .neutral
    var tint: Color? = nil
    var compact: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if compact {
            AppLoadingBeacon(
                tone: tone,
                tint: tint,
                compact: compact
            )
            .frame(width: 16, height: 12)
        } else {
            AppLoadingBeacon(
                tone: tone,
                tint: tint,
                compact: compact
            )
            .frame(width: 22, height: 16)
            .padding(4)
            .background(
                tone.iconPlateFill(for: colorScheme, override: tint),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
        }
    }
}

struct AppLoadingInlineLabel: View {
    let text: String
    var tone: AppLoadingTone = .neutral
    var tint: Color? = nil
    var font: Font = .footnote.weight(.medium)

    var body: some View {
        HStack(spacing: 8) {
            AppLoadingActivityMark(tone: tone, tint: tint)
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct AppLoadingPanel: View {
    let title: String
    let message: String
    var detail: String? = nil
    var symbol: String = "arrow.triangle.2.circlepath"
    var tone: AppLoadingTone = .neutral
    var width: CGFloat? = nil

    var body: some View {
        AppLoadingSurface(tone: tone) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    AppLoadingActivityMark(tone: tone, compact: false)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.2)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

struct AppLoadingListPlaceholder: View {
    let title: String
    let message: String
    var detail: String? = nil
    var symbol: String = "arrow.triangle.2.circlepath"
    var tone: AppLoadingTone = .neutral
    var rowCount: Int = 5
    var showsThumbnails: Bool = true
    var compact: Bool = false

    var body: some View {
        AppLoadingSurface(tone: tone, cornerRadius: compact ? 14 : 18) {
            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                AppLoadingStatusCapsule(
                    title: title,
                    detail: detail,
                    symbol: symbol,
                    tone: tone
                )

                Text(message)
                    .font(compact ? .footnote : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                VStack(spacing: compact ? 8 : 10) {
                    ForEach(0..<rowCount, id: \.self) { index in
                        HStack(spacing: compact ? 10 : 12) {
                            if showsThumbnails {
                                AppLoadingThumbnailPlaceholder(
                                    width: compact ? 42 : 58,
                                    height: compact ? 42 : 58,
                                    tone: tone
                                )
                            }

                            VStack(alignment: .leading, spacing: compact ? 5 : 6) {
                                AppLoadingSkeletonBar(
                                    width: compact ? 112 + CGFloat((index % 3) * 14) : 156 + CGFloat((index % 3) * 18),
                                    height: compact ? 10 : 12,
                                    cornerRadius: 6,
                                    tone: tone
                                )
                                AppLoadingSkeletonBar(
                                    width: compact ? 160 + CGFloat((index % 2) * 12) : 228 - CGFloat((index % 3) * 18),
                                    height: compact ? 8 : 10,
                                    cornerRadius: 5,
                                    tone: tone
                                )
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

struct AppLoadingThumbnailPlaceholder: View {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat = 10
    var tone: AppLoadingTone = .neutral
    var symbol: String = "photo"

    var body: some View {
        ZStack {
            AppLoadingSkeletonBar(
                width: width,
                height: height,
                cornerRadius: cornerRadius,
                tone: tone
            )
            Image(systemName: symbol)
                .font(.system(size: min(width, height) * 0.24, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }
}

struct AppLoadingSkeletonBar: View {
    let width: CGFloat?
    let height: CGFloat
    var cornerRadius: CGFloat = 8
    var tone: AppLoadingTone = .neutral

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let shimmerPhase = reduceMotion ? -1.1 : shimmerPhase(for: context.date)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: tone.barColors(for: colorScheme),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    if !reduceMotion {
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            Color.white.opacity(colorScheme == .dark ? 0.28 : 0.50),
                                            .clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .rotationEffect(.degrees(14))
                                .offset(x: shimmerPhase * max(proxy.size.width, 1))
                        }
                        .clipped()
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(tone.strokeColor(for: colorScheme).opacity(0.48), lineWidth: 0.8)
                }
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        }
    }

    private func shimmerPhase(for date: Date) -> CGFloat {
        let progress = date.timeIntervalSinceReferenceDate
            .remainder(dividingBy: AppLoadingMotion.shimmerDuration)
            / AppLoadingMotion.shimmerDuration
        return CGFloat((progress * 2.4) - 1.2)
    }
}

struct AppLoadingScanlineOverlay: View {
    var lineOpacity: Double

    var body: some View {
        GeometryReader { proxy in
            let rowHeight: CGFloat = 4
            let lineCount = max(1, Int((proxy.size.height / rowHeight).rounded(.up)))
            VStack(spacing: rowHeight - 1) {
                ForEach(0..<lineCount, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.white.opacity(lineOpacity))
                        .frame(height: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AppLoadingSurface<Content: View>: View {
    let tone: AppLoadingTone
    let cornerRadius: CGFloat
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    init(
        tone: AppLoadingTone,
        cornerRadius: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tone.surfaceWash(for: colorScheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tone.strokeColor(for: colorScheme), lineWidth: 0.9)
            }
            .overlay {
                let scanlineOpacity = tone.scanlineOpacity(for: colorScheme)
                if scanlineOpacity > 0 {
                    AppLoadingScanlineOverlay(lineOpacity: scanlineOpacity)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .blendMode(.screen)
                }
            }
    }
}

private struct AppLoadingBeacon: View {
    let tone: AppLoadingTone
    let tint: Color?
    let compact: Bool

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { context in
            let accent = tone.accentColor(for: colorScheme, override: tint)
            let progress = reduceMotion ? 0.2 : beaconProgress(for: context.date)

            HStack(alignment: .bottom, spacing: compact ? 2.5 : 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(accent.opacity(barOpacity(progress: progress, index: index)))
                        .frame(
                            width: compact ? 2.5 : 3,
                            height: barHeight(progress: progress, index: index)
                        )
                }
            }
        }
    }

    private func beaconProgress(for date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
            .remainder(dividingBy: 0.96)
            / 0.96
    }

    private func barHeight(progress: Double, index: Int) -> CGFloat {
        let wave = max(0.1, sin((progress * .pi * 2.0) + Double(index) * 0.8))
        let baseHeight: CGFloat = compact ? 5 : 7
        let lift: CGFloat = compact ? 5 : 7
        return baseHeight + CGFloat(wave) * lift
    }

    private func barOpacity(progress: Double, index: Int) -> Double {
        let wave = max(0.18, sin((progress * .pi * 2.0) + Double(index) * 0.8))
        return 0.32 + wave * 0.58
    }
}
