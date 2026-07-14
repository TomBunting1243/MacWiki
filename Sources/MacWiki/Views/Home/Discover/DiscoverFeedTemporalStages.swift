import SwiftUI

extension DiscoverFeedSections {
    @ViewBuilder
    var timeCapsuleStage: some View {
        if hasTimeCapsuleDetails {
            DiscoverEditorialPanel(
                accent: Color.mint.opacity(0.84),
                tone: .archive,
                contentPadding: isCompactLayout ? 14 : 18
            ) {
                VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 18) {
                    DiscoverSectionHeader(title: "Time Capsule", subtitle: DiscoverEditionCopy.timeCapsuleSubtitle)
                    timeCapsuleHistoryModule
                    timeCapsuleDidYouKnowModule
                }
            }
        }
    }

    @ViewBuilder
    var timeMachineBirthsModule: some View {
        if !feed.onThisDayBirths.isEmpty {
            DiscoverInsetPanel(accent: Color.green.opacity(0.78)) {
                VStack(alignment: .leading, spacing: 10) {
                    DiscoverTemporalSubsectionHeader(
                        title: "Born",
                        systemImage: "sparkles",
                        accent: Color.green.opacity(0.78)
                    )

                    ForEach(feed.onThisDayBirths.prefix(6)) { event in
                        DiscoverOnThisDayRow(
                            event: event,
                            onOpen: onOpen,
                            referenceDate: trendReferenceDate,
                            showsSurface: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    var timeMachineDeathsModule: some View {
        if !feed.onThisDayDeaths.isEmpty {
            DiscoverInsetPanel(accent: Color.pink.opacity(0.72)) {
                VStack(alignment: .leading, spacing: 10) {
                    DiscoverTemporalSubsectionHeader(
                        title: "Died",
                        systemImage: "moon.stars",
                        accent: Color.pink.opacity(0.72)
                    )

                    ForEach(feed.onThisDayDeaths.prefix(6)) { event in
                        DiscoverOnThisDayRow(
                            event: event,
                            onOpen: onOpen,
                            referenceDate: trendReferenceDate,
                            showsSurface: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    var timeMachineHolidaysModule: some View {
        if !feed.holidays.isEmpty {
            DiscoverInsetPanel(accent: Color.orange.opacity(0.74)) {
                VStack(alignment: .leading, spacing: 10) {
                    DiscoverTemporalSubsectionHeader(
                        title: "Holidays & Observances",
                        systemImage: "calendar",
                        accent: Color.orange.opacity(0.74)
                    )

                    ForEach(feed.holidays.prefix(8)) { holiday in
                        DiscoverHolidayRow(
                            holiday: holiday,
                            onOpen: onOpen,
                            referenceDate: trendReferenceDate,
                            showsSurface: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    var timeMachineStage: some View {
        if hasTimeMachineSurface {
            DiscoverEditorialPanel(
                accent: Color.indigo.opacity(0.84),
                tone: .timewarp,
                contentPadding: isCompactLayout ? 14 : 18
            ) {
                VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        DiscoverSectionHeader(title: "Time Machine", subtitle: DiscoverEditionCopy.timeMachineSubtitle)

                        Spacer(minLength: 0)

                        if !timeMachineDisplayDateLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(timeMachineDisplayDateLabel)
                                .font(DiscoverTypography.editionDate.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.055), in: Capsule())
                        }
                    }

                    if !feed.onThisDayBirths.isEmpty || !feed.onThisDayDeaths.isEmpty {
                        timeMachineBirthsModule
                        timeMachineDeathsModule
                    }

                    timeMachineHolidaysModule
                }
            }
        }
    }

    @ViewBuilder
    var temporalExplorationStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            timeCapsuleStage
            timeMachineStage
        }
    }

    @ViewBuilder
    var leadEditionStage: some View {
        VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 18) {
            DiscoverMasthead(
                dateLabel: feed.dateLabel,
                isCompactLayout: isCompactLayout
            )

            if let featured = feed.featuredArticle {
                VStack(alignment: .leading, spacing: 16) {
                    featuredStoryModule(featured)
                    openingEditorialSpread
                }
            } else {
                openingEditorialSpread
            }
        }
    }

    @ViewBuilder
    func featuredStoryModule(_ featured: WikipediaService.SearchResult) -> some View {
        let featuredRowKey = pageViewsRowKey(section: "featured", result: featured)
        let featuredPulse = mostReadPulse(for: featured)
        DiscoverFeatureModule(
            result: featured,
            teaserText: featuredTeaserText,
            isTeaserLoading: isFeaturedTeaserLoading,
            trendPulse: featuredPulse,
            isTrendPulseLoading: trendPulseStore.isLoading && featuredPulse == nil,
            visualContextImages: visualContextStore.images,
            isVisualContextLoading: visualContextStore.isLoading && visualContextStore.images.isEmpty,
            heroImageHeight: heroImageHeight,
            titleLineLimit: leadStoryTitleLineLimit,
            descriptionLineLimit: leadStoryDescriptionLineLimit,
            isCompactLayout: isCompactLayout,
            onOpen: onOpen,
            onOpenURL: { url in
                openURL(url)
            },
            onTrendTapped: { pulse in
                presentPageViewsPopover(
                    for: featured,
                    rowKey: featuredRowKey,
                    initialPulse: pulse
                )
            }
        )
        .contextMenu {
            discoverContextMenu(for: featured) {
                presentPageViewsPopover(for: featured, rowKey: featuredRowKey)
            }
        }
        .popover(isPresented: pageViewsPopoverBinding(for: featuredRowKey), arrowEdge: .trailing) {
            pageViewsPopover(for: featuredRowKey)
        }
    }
}
