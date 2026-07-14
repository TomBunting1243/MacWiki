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
        .discoverSurfaceChrome(
            cornerRadius: 20,
            tintColors: [
                Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.08),
                Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.04 : 0.14),
                .clear
            ],
            borderOpacity: colorScheme == .dark ? 0.18 : 0.14,
            borderWidth: 0.9,
            shadowOpacity: colorScheme == .dark ? 0.22 : 0.08,
            shadowRadius: 18,
            shadowY: 6
        )
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
        .discoverSurfaceChrome(
            cornerRadius: 16,
            material: .regular,
            borderOpacity: 0.12
        )
    }
}

enum DiscoverCollectionLane: String, CaseIterable {
    case mostRead
    case longest
}
