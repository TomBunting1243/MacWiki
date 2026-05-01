import SwiftUI

struct DiscoverEditionBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.12),
                        Color.teal.opacity(colorScheme == .dark ? 0.08 : 0.055),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 300)

                Spacer(minLength: 0)
            }

            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.34 : 0.58),
                    Color(nsColor: .windowBackgroundColor).opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.028),
                                .clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 160)

                Spacer(minLength: 0)
            }
        }
    }
}

enum DiscoverEditionCopy {
    static let leadKicker = "Featured Article"
    static let visualContextTitle = "Visual Context"
    static let visualContextSubtitle = "Commons media"
    static let visualContextUnavailable = "No related Commons media collected for this lead story yet."
    static let commonsSpotlight = "Commons Spotlight"

    static let todayMostReadSubtitle = "Live reader signal"
    static let todayMostReadColumnSubtitle = "What readers are opening now"
    static let newsBriefingSubtitle = "Current events"
    static let collectionsSubtitle = "Reading paths"
    static let allTimeMostReadSubtitle = "Enduring public-record staples"
    static let longestReadsSubtitle = "Long-form articles for a deeper session"
    static let mediaSubtitle = "Images and current context"
    static let imageOfTheDaySubtitle = "From Wikimedia Commons"
    static let inTheNewsSubtitle = "Developing articles"
    static let timeCapsuleSubtitle = "This day in history"
    static let timeMachineSubtitle = "Selected date"
}
