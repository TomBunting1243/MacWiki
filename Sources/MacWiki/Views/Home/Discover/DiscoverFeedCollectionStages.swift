import SwiftUI

extension DiscoverFeedSections {
    @ViewBuilder
    var collectionsKeyboardShortcutHost: some View {
        VStack(spacing: 0) {
            Button(action: { openFocusedCollectionItem(inNewTab: false) }) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [])

            Button(action: { openFocusedCollectionItem(inNewTab: true) }) {
                EmptyView()
            }
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0.001)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .disabled(!canOpenFocusedCollectionItem || isSearchFieldFocused)
    }

    @ViewBuilder
    var mostReadCollectionModule: some View {
        DiscoverExpandableCollectionCard(
            title: "Most Read",
            subtitle: playlistMostReadSubtitle,
            meta: mostReadCollectionMeta,
            systemImage: "chart.line.uptrend.xyaxis",
            tint: .accentColor,
            showsLoading: allTimeMostReadStore.isLoading || trendPulseStore.isLoading,
            isKeyboardFocused: isCollectionsKeyboardFocusActive && focusedCollectionLane == .mostRead,
            isExpanded: collectionExpansionBinding(for: .mostRead),
            collapsedPreviewTitles: mostReadPreviewTitles
        ) {
            if playlistMostReadItems.isEmpty {
                DiscoverPlaylistPlaceholder(
                    text: allTimeMostReadStore.isLoading
                        ? "Loading all-time most read..."
                        : "All-time Most Read is unavailable right now."
                )
            } else {
                ForEach(Array(playlistMostReadItems.enumerated()), id: \.element.id) { index, result in
                    let rowKey = pageViewsRowKey(section: "collection-most-read", result: result, index: index)
                    let trendPulse = trendPulseStore.pulse(for: result.title)
                    DiscoverPlaylistArticleRow(
                        result: result,
                        rank: index + 1,
                        primaryStat: mostReadPrimaryStat(for: result),
                        secondaryStat: mostReadSecondaryStat(for: result),
                        statTint: mostReadStatTint(for: result),
                        isKeyboardFocused: isFocusedCollectionRow(lane: .mostRead, index: index),
                        onFocus: {
                            markCollectionsFocus(lane: .mostRead, index: index)
                        },
                        onOpen: onOpen
                    )
                    .contextMenu {
                        discoverContextMenu(for: result) {
                            presentPageViewsPopover(
                                for: result,
                                rowKey: rowKey,
                                initialPulse: trendPulse
                            )
                        }
                    }
                    .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                        pageViewsPopover(for: rowKey)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var longestReadsCollectionModule: some View {
        DiscoverExpandableCollectionCard(
            title: "Longest Reads",
            subtitle: playlistLongestSubtitle,
            meta: longestCollectionMeta,
            systemImage: "text.alignleft",
            tint: Color.orange.opacity(0.92),
            showsLoading: allTimeMostReadStore.isLoading || wordCountStore.isLoading,
            isKeyboardFocused: isCollectionsKeyboardFocusActive && focusedCollectionLane == .longest,
            isExpanded: collectionExpansionBinding(for: .longest),
            collapsedPreviewTitles: longestReadsPreviewTitles
        ) {
            if longestReadItems.isEmpty {
                if longestFallbackItems.isEmpty {
                    DiscoverPlaylistPlaceholder(
                        text: wordCountStore.isLoading
                            ? "Finding long reads..."
                            : "No all-time long-read candidates are available yet."
                    )
                } else {
                    ForEach(Array(longestFallbackItems.enumerated()), id: \.element.id) { index, result in
                        let rowKey = pageViewsRowKey(section: "collection-longest-fallback", result: result, index: index)
                        DiscoverPlaylistArticleRow(
                            result: result,
                            rank: index + 1,
                            primaryStat: wordCountStore.isLoading ? "Loading words..." : "Word count unavailable",
                            secondaryStat: wordCountStore.isLoading ? nil : "Open to inspect",
                            statTint: .secondary,
                            isKeyboardFocused: isFocusedCollectionRow(lane: .longest, index: index),
                            onFocus: {
                                markCollectionsFocus(lane: .longest, index: index)
                            },
                            onOpen: onOpen
                        )
                        .contextMenu {
                            discoverContextMenu(for: result) {
                                presentPageViewsPopover(for: result, rowKey: rowKey)
                            }
                        }
                        .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                            pageViewsPopover(for: rowKey)
                        }
                    }
                }
            } else {
                ForEach(Array(longestReadItems.enumerated()), id: \.element.id) { index, entry in
                    let rowKey = pageViewsRowKey(section: "collection-longest", result: entry.result, index: index)
                    DiscoverPlaylistArticleRow(
                        result: entry.result,
                        rank: index + 1,
                        primaryStat: formattedWordCount(entry.wordCount),
                        secondaryStat: estimatedReadingTimeText(for: entry.wordCount),
                        statTint: Color.orange.opacity(0.92),
                        isKeyboardFocused: isFocusedCollectionRow(lane: .longest, index: index),
                        onFocus: {
                            markCollectionsFocus(lane: .longest, index: index)
                        },
                        onOpen: onOpen
                    )
                    .contextMenu {
                        discoverContextMenu(for: entry.result) {
                            presentPageViewsPopover(for: entry.result, rowKey: rowKey)
                        }
                    }
                    .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                        pageViewsPopover(for: rowKey)
                    }
                }
            }
        }
    }

    @ViewBuilder
    var todayMostReadSection: some View {
        let columnCount = responsiveLayout.todayMostReadColumnCount(
            hasNewsBriefing: !feed.newsStories.isEmpty,
            itemCount: todayMostReadItems.count
        )

        DiscoverExpandableCollectionCard(
            title: "Today’s Most Read",
            subtitle: todayMostReadSubtitle,
            meta: todayMostReadMeta,
            systemImage: "sun.max.fill",
            tint: Color.blue.opacity(0.92),
            showsLoading: todayMostReadStore.isLoading || todayTrendPulseStore.isLoading,
            isKeyboardFocused: false,
            isExpanded: $isTodayMostReadExpanded,
            collapsedPreviewTitles: todayMostReadPreviewTitles
        ) {
            if todayMostReadItems.isEmpty {
                if todayMostReadStore.errorMessage != nil {
                    DiscoverPlaylistPlaceholder(
                        text: DiscoverTodayMostReadPresentation.placeholder(
                            isLoading: false,
                            hasFailure: true
                        ),
                        actionTitle: "Try Again"
                    ) {
                        todayMostReadStore.queueLoad(forceRefresh: true)
                    }
                } else {
                    DiscoverPlaylistPlaceholder(
                        text: DiscoverTodayMostReadPresentation.placeholder(
                            isLoading: todayMostReadStore.isLoading,
                            hasFailure: false
                        )
                    )
                }
            } else {
                todayMostReadRows(columnCount: columnCount)
            }
        }
    }

    @ViewBuilder
    private func todayMostReadRows(columnCount: Int) -> some View {
        if columnCount == 2 {
            let splitIndex = (todayMostReadItems.count + 1) / 2

            HStack(alignment: .top, spacing: 8) {
                todayMostReadColumn(todayMostReadItems[..<splitIndex], rankOffset: 0)
                todayMostReadColumn(todayMostReadItems[splitIndex...], rankOffset: splitIndex)
            }
        } else {
            todayMostReadColumn(todayMostReadItems[...], rankOffset: 0)
        }
    }

    private func todayMostReadColumn(
        _ items: ArraySlice<WikipediaService.SearchResult>,
        rankOffset: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { offset, result in
                todayMostReadRow(result, index: rankOffset + offset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func todayMostReadRow(
        _ result: WikipediaService.SearchResult,
        index: Int
    ) -> some View {
        let rowKey = pageViewsRowKey(section: "today-most-read", result: result, index: index)
        let trendPulse = todayMostReadPulse(for: result)

        return DiscoverPlaylistArticleRow(
            result: result,
            rank: index + 1,
            primaryStat: todayMostReadPrimaryStat(for: result),
            secondaryStat: todayMostReadSecondaryStat(for: result),
            statTint: todayMostReadStatTint(for: result),
            isKeyboardFocused: false,
            onFocus: nil,
            onOpen: onOpen
        )
        .contextMenu {
            discoverContextMenu(for: result) {
                presentPageViewsPopover(
                    for: result,
                    rowKey: rowKey,
                    initialPulse: trendPulse
                )
            }
        }
        .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
            pageViewsPopover(for: rowKey)
        }
    }

    @ViewBuilder
    var newsBriefingSection: some View {
        if !feed.newsStories.isEmpty {
            DiscoverEditorialPanel(accent: Color.teal.opacity(0.84), tone: .notebook) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(
                        title: "News Briefing",
                        subtitle: DiscoverEditionCopy.newsBriefingSubtitle
                    )
                    VStack(spacing: 10) {
                        ForEach(feed.newsStories.prefix(newsBriefingLimit)) { story in
                            DiscoverNewsStoryCard(
                                story: story,
                                onOpen: onOpen,
                                referenceDate: trendReferenceDate,
                                showsSurface: false
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var openingEditorialSpread: some View {
        if responsiveLayout.prefersEditorialSpread {
            Grid(horizontalSpacing: responsiveLayout.editorialColumnSpacing, verticalSpacing: 0) {
                GridRow(alignment: .top) {
                    todayMostReadSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    newsBriefingSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                todayMostReadSection
                newsBriefingSection
            }
        }
    }

    @ViewBuilder
    var collectionsStage: some View {
        VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 16) {
            DiscoverSectionHeader(
                title: "Collections",
                subtitle: DiscoverEditionCopy.collectionsSubtitle
            )

            if responsiveLayout.prefersEditorialSpread {
                Grid(horizontalSpacing: responsiveLayout.editorialColumnSpacing, verticalSpacing: 0) {
                    GridRow(alignment: .top) {
                        mostReadCollectionModule
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        longestReadsCollectionModule
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    mostReadCollectionModule
                    longestReadsCollectionModule
                }
            }
        }
    }

    @ViewBuilder
    var mediaSpotlightSection: some View {
        if feed.featuredImage != nil || !remainingNewsItems.isEmpty {
            VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 16) {
                DiscoverSectionHeader(title: "Media & Current Events", subtitle: DiscoverEditionCopy.mediaSubtitle)

                VStack(alignment: .leading, spacing: 16) {
                    mediaSpotlightImageModule
                    inTheNewsModule
                }
            }
        }
    }

    @ViewBuilder
    var mediaSpotlightImageModule: some View {
        if let featuredImage = feed.featuredImage {
            DiscoverEditorialPanel(accent: Color.indigo.opacity(0.82), tone: .feature) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(title: "Image of the Day", subtitle: DiscoverEditionCopy.imageOfTheDaySubtitle)
                    DiscoverFeaturedImageCard(
                        image: featuredImage,
                        prefersHorizontalLayout: responsiveLayout.prefersEditorialSpread
                    )
                }
            }
        }
    }

    @ViewBuilder
    var inTheNewsModule: some View {
        if !remainingNewsItems.isEmpty {
            DiscoverEditorialPanel(accent: Color.red.opacity(0.78), tone: .notebook) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(title: "In the News", subtitle: DiscoverEditionCopy.inTheNewsSubtitle)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
                            count: responsiveLayout.prefersEditorialSpread ? 2 : 1
                        ),
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(remainingNewsItems.prefix(inTheNewsRailLimit)) { result in
                            let rowKey = pageViewsRowKey(section: "in-news", result: result)
                            DiscoverNewsCard(
                                result: result,
                                style: responsiveLayout.prefersEditorialSpread ? .rail : .standard,
                                onOpen: onOpen
                            )
                                .contextMenu {
                                    discoverContextMenu(for: result) {
                                        presentPageViewsPopover(for: result, rowKey: rowKey)
                                    }
                                }
                                .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                                    pageViewsPopover(for: rowKey)
                                }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    var timeCapsuleHistoryModule: some View {
        if leadTimelineEvent != nil || !supportingTimelineEvents.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                DiscoverTemporalSubsectionHeader(
                    title: "This Day in History",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    accent: Color.mint.opacity(0.82)
                )

                if let leadTimelineEvent {
                    DiscoverOnThisDayFeatureCard(
                        event: leadTimelineEvent,
                        accent: Color.mint.opacity(0.82),
                        onOpen: onOpen
                    )
                }

                if !supportingTimelineEvents.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(supportingTimelineEvents) { event in
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
    }

    @ViewBuilder
    var timeCapsuleDidYouKnowModule: some View {
        if !feed.didYouKnow.isEmpty {
            DiscoverInsetPanel(accent: Color.yellow.opacity(0.76)) {
                VStack(alignment: .leading, spacing: 10) {
                    DiscoverTemporalSubsectionHeader(
                        title: "Did You Know?",
                        systemImage: "lightbulb.max",
                        accent: Color.yellow.opacity(0.76)
                    )

                    ForEach(feed.didYouKnow.prefix(8)) { fact in
                        DiscoverDidYouKnowRow(
                            fact: fact,
                            onOpen: onOpen,
                            referenceDate: trendReferenceDate,
                            showsSurface: false
                        )
                    }
                }
            }
        }
    }
}
