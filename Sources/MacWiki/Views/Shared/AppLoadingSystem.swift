import SwiftUI

enum AppLoadingMotion {
    static let overlayScale: CGFloat = 0.992
    static let skeletonRevealDuration: Double = 0.14
    static let skeletonHideDuration: Double = 0.18
    static let skeletonMinimumVisibleDuration: TimeInterval = 0.18

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
    var tone: AppLoadingTone = .neutral
    var tint: Color? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization

    var body: some View {
        ViewThatFits {
            capsuleLayout(showsDetail: true)
            capsuleLayout(showsDetail: false)
        }
    }

    private func capsuleLayout(showsDetail: Bool) -> some View {
        HStack(spacing: 8) {
            AppLoadingActivityMark(
                tone: tone,
                tint: tint,
                accessibilityLabel: "Loading \(title)"
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
        .background {
            if accessibilityPersonalization.reduceTransparency {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            } else {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    tone.strokeColor(for: colorScheme).opacity(0.72),
                    lineWidth: accessibilityPersonalization.colorSchemeContrast == .increased ? 1.2 : 0.8
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading \(title)")
        .accessibilityValue(showsDetail ? (detail ?? "") : "")
    }
}

struct AppLoadingActivityMark: View {
    var tone: AppLoadingTone = .neutral
    var tint: Color? = nil
    var accessibilityLabel: String = "Loading"
    var compact: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if compact {
            ProgressView()
                .controlSize(.mini)
                .accessibilityLabel(accessibilityLabel)
                .frame(width: 16, height: 12)
        } else {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(accessibilityLabel)
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
            AppLoadingActivityMark(
                tone: tone,
                tint: tint,
                accessibilityLabel: text
            )
            Text(text)
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct AppLoadingListPlaceholder: View {
    let title: String
    let message: String
    var detail: String? = nil
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
        .accessibilityHidden(true)
    }
}

struct AppLoadingSkeletonBar: View {
    let width: CGFloat?
    let height: CGFloat
    var cornerRadius: CGFloat = 8
    var tone: AppLoadingTone = .neutral

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: tone.barColors(for: colorScheme),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tone.strokeColor(for: colorScheme).opacity(0.48), lineWidth: 0.8)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

private struct AppLoadingSurface<Content: View>: View {
    let tone: AppLoadingTone
    let cornerRadius: CGFloat
    let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization

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
            .background {
                if accessibilityPersonalization.reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tone.surfaceWash(for: colorScheme))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        tone.strokeColor(for: colorScheme),
                        lineWidth: accessibilityPersonalization.colorSchemeContrast == .increased ? 1.4 : 0.9
                    )
            }
    }
}
