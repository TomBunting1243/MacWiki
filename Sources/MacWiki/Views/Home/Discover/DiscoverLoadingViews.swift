import Foundation
import SwiftUI

struct DiscoverInlinePageViewsPopoverPayload {
    let rowKey: String
    let title: String
}

struct DiscoverIntroLoadingView: View {
    let referenceDate: Date

    @Environment(\.colorScheme) private var colorScheme

    private var dateLabel: String {
        Self.dateFormatter.string(from: referenceDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                AppLoadingStatusCapsule(
                    title: "Discover",
                    detail: dateLabel,
                    symbol: "newspaper.fill",
                    tone: .accent
                )

                Spacer(minLength: 0)

                AppLoadingInlineLabel(
                    text: "Warming featured stories",
                    tone: .accent,
                    font: .caption.weight(.semibold)
                )
            }

            ViewThatFits {
                HStack(alignment: .top, spacing: 12) {
                    heroColumn
                    supportColumn
                        .frame(width: 280)
                }

                VStack(alignment: .leading, spacing: 12) {
                    heroColumn
                    supportColumn
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.08),
                            Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.04 : 0.14),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.14), lineWidth: 0.9)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 18, y: 6)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    private var heroColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppLoadingSkeletonBar(
                width: nil,
                height: 188,
                cornerRadius: 18,
                tone: .accent
            )

            AppLoadingSkeletonBar(
                width: 220,
                height: 16,
                cornerRadius: 8,
                tone: .accent
            )

            AppLoadingSkeletonBar(
                width: nil,
                height: 12,
                cornerRadius: 6,
                tone: .neutral
            )

            AppLoadingSkeletonBar(
                width: 240,
                height: 10,
                cornerRadius: 5,
                tone: .neutral
            )
        }
    }

    private var supportColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            DiscoverIntroLoadingCard(tone: .accent)
            DiscoverIntroLoadingCard(tone: .neutral)
        }
    }
}

struct DiscoverIntroLoadingCard: View {
    let tone: AppLoadingTone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppLoadingSkeletonBar(width: 128, height: 10, cornerRadius: 5, tone: tone)
            AppLoadingSkeletonBar(width: nil, height: 52, cornerRadius: 12, tone: tone)
            AppLoadingSkeletonBar(width: 172, height: 10, cornerRadius: 5, tone: .neutral)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
    }
}

struct DiscoverTimeMachineLoadingContent: View {
    let isCompactLayout: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompactLayout ? 12 : 14) {
            DiscoverTimeMachineLoadingPulseStrip()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    DiscoverTimeMachineLoadingPanel(
                        title: "Born",
                        systemImage: "sparkles",
                        accent: Color.green.opacity(0.78),
                        rowRange: 0..<3
                    )

                    DiscoverTimeMachineLoadingPanel(
                        title: "Died",
                        systemImage: "moon.stars",
                        accent: Color.pink.opacity(0.72),
                        rowRange: 3..<6
                    )
                }

                VStack(alignment: .leading, spacing: 12) {
                    DiscoverTimeMachineLoadingPanel(
                        title: "Born",
                        systemImage: "sparkles",
                        accent: Color.green.opacity(0.78),
                        rowRange: 0..<3
                    )

                    DiscoverTimeMachineLoadingPanel(
                        title: "Died",
                        systemImage: "moon.stars",
                        accent: Color.pink.opacity(0.72),
                        rowRange: 3..<6
                    )
                }
            }

            DiscoverTimeMachineLoadingPanel(
                title: "Holidays & Observances",
                systemImage: "calendar",
                accent: Color.orange.opacity(0.74),
                rowRange: 6..<9
            )
        }
        .accessibilityHidden(true)
    }
}

private struct DiscoverTimeMachineLoadingPulseStrip: View {
    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            ForEach(0..<8, id: \.self) { index in
                AppLoadingSkeletonBar(
                    width: nil,
                    height: 6 + CGFloat((index % 3) * 3),
                    cornerRadius: 4.5,
                    tone: .retro
                )
            }
        }
        .frame(height: 18)
    }
}

private struct DiscoverTimeMachineLoadingPanel: View {
    let title: String
    let systemImage: String
    let accent: Color
    let rowRange: Range<Int>

    var body: some View {
        DiscoverInsetPanel(accent: accent) {
            VStack(alignment: .leading, spacing: 10) {
                DiscoverTemporalSubsectionHeader(
                    title: title,
                    systemImage: systemImage,
                    accent: accent
                )

                ForEach(Array(rowRange), id: \.self) { index in
                    DiscoverTimeMachineLoadingRow(index: index)
                }
            }
        }
    }
}

private struct DiscoverTimeMachineLoadingRow: View {
    let index: Int

    private var titleMaxWidth: CGFloat {
        132 + CGFloat((index % 3) * 28)
    }

    private var subtitleMaxWidth: CGFloat {
        188 - CGFloat((index % 3) * 18)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AppLoadingSkeletonBar(
                width: 22,
                height: 22,
                cornerRadius: 7,
                tone: .retro
            )

            VStack(alignment: .leading, spacing: 6) {
                AppLoadingSkeletonBar(
                    width: nil,
                    height: 10,
                    cornerRadius: 5,
                    tone: .retro
                )
                .frame(maxWidth: titleMaxWidth, alignment: .leading)

                AppLoadingSkeletonBar(
                    width: nil,
                    height: 8,
                    cornerRadius: 4,
                    tone: .neutral
                )
                .frame(maxWidth: subtitleMaxWidth, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum DiscoverCollectionLane: String, CaseIterable {
    case mostRead
    case longest
}
