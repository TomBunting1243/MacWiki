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
                            Color.white.opacity(colorScheme == .dark ? 0.02 : 0.10),
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

struct DiscoverTimeTravelSkeletonView: View {
    let targetDate: Date
    let availableWidth: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var cardColumns: [GridItem] {
        if availableWidth < 840 {
            return [GridItem(.flexible(minimum: 240), spacing: 10)]
        }
        return [
            GridItem(.flexible(minimum: 220), spacing: 10),
            GridItem(.flexible(minimum: 220), spacing: 10)
        ]
    }

    private var targetDateLabel: String {
        Self.targetDateFormatter.string(from: targetDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                AppLoadingStatusCapsule(
                    title: "Time Machine",
                    detail: "Locking to \(targetDateLabel)",
                    symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    tone: .retro
                )

                Spacer(minLength: 0)

                Text("SCANNING")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.58, green: 0.80, blue: 1.0).opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.36, green: 0.46, blue: 0.86).opacity(colorScheme == .dark ? 0.22 : 0.14),
                                Color(red: 0.78, green: 0.47, blue: 0.94).opacity(colorScheme == .dark ? 0.18 : 0.10)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule(style: .continuous)
                    )
            }

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

            LazyVGrid(columns: cardColumns, spacing: 10) {
                ForEach(0..<6, id: \.self) { index in
                    DiscoverTimeTravelSkeletonCard(index: index)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(red: 0.58, green: 0.80, blue: 1.0).opacity(colorScheme == .dark ? 0.28 : 0.20), lineWidth: 0.9)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.36, green: 0.46, blue: 0.86).opacity(colorScheme == .dark ? 0.16 : 0.12),
                            Color(red: 0.78, green: 0.47, blue: 0.94).opacity(colorScheme == .dark ? 0.10 : 0.08),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            AppLoadingScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.026 : 0.018)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .blendMode(.screen)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.09), radius: 12, y: 5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let targetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()
}

struct DiscoverTimeTravelSkeletonCard: View {
    let index: Int

    private var titleWidth: CGFloat {
        120 + CGFloat((index % 3) * 28)
    }

    private var subtitleWidth: CGFloat {
        84 + CGFloat((index % 2) * 24)
    }

    private var lineWidth: CGFloat {
        160 - CGFloat((index % 3) * 16)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppLoadingSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 7,
                    tone: .retro
                )

                VStack(alignment: .leading, spacing: 5) {
                    AppLoadingSkeletonBar(
                        width: titleWidth,
                        height: 10,
                        cornerRadius: 5,
                        tone: .retro
                    )
                    AppLoadingSkeletonBar(
                        width: subtitleWidth,
                        height: 9,
                        cornerRadius: 5,
                        tone: .neutral
                    )
                }

                Spacer(minLength: 0)
            }

            AppLoadingSkeletonBar(
                width: nil,
                height: 12,
                cornerRadius: 6,
                tone: .retro
            )
            AppLoadingSkeletonBar(
                width: lineWidth,
                height: 10,
                cornerRadius: 5,
                tone: .neutral
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
    }
}

enum DiscoverCollectionLane: String, CaseIterable {
    case mostRead
    case longest
}
