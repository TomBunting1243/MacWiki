import Foundation
import SwiftUI

struct DiscoverFeedSections: View {
    let feed: WikipediaService.DiscoverFeed
    let availableWidth: CGFloat
    let isSearchFieldFocused: Bool
    let refreshGeneration: Int
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let showsTimeTravelSkeleton: Bool
    let timeMachineTargetDate: Date
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var allTimeMostReadStore = DiscoverAllTimeMostReadStore()
    @State private var todayMostReadStore = DiscoverTodayMostReadStore()
    @State private var trendPulseStore = DiscoverTrendPulseStore()
    @State private var todayTrendPulseStore = DiscoverTrendPulseStore()
    @State private var wordCountStore = ArticleWordCountStore()
    @State private var featuredSummaryStore = DiscoverFeaturedSummaryStore()
    @State private var visualContextStore = DiscoverVisualContextStore()
    @State private var activePageViewsPopover: DiscoverPageViewsPopoverPayload?
    @State private var isCollectionsKeyboardFocusActive = false
    @State private var focusedCollectionLane: DiscoverCollectionLane = .mostRead
    @State private var focusedMostReadRowIndex = 0
    @State private var focusedLongestRowIndex = 0
    @State private var isTodayMostReadExpanded = true
    @State private var isMostReadCollectionExpanded = false
    @State private var isLongestReadsCollectionExpanded = false

    private var isUltraCompactLayout: Bool {
        availableWidth < 720
    }

    private var isVeryCompactLayout: Bool {
        availableWidth < 820
    }

    private var isCompactLayout: Bool {
        availableWidth < 940
    }

    private var sectionSpacing: CGFloat {
        if isUltraCompactLayout { return 16 }
        return isVeryCompactLayout ? 20 : (isCompactLayout ? 22 : 26)
    }

    private var heroImageHeight: CGFloat {
        if isUltraCompactLayout { return 172 }
        if isVeryCompactLayout { return 190 }
        if isCompactLayout { return 214 }
        if availableWidth >= 1320 { return 320 }
        if availableWidth >= 1120 { return 286 }
        return 252
    }

    private var leadStoryTitleLineLimit: Int {
        if isUltraCompactLayout { return 3 }
        if isVeryCompactLayout { return 4 }
        return 5
    }

    private var leadStoryDescriptionLineLimit: Int {
        if isUltraCompactLayout { return 2 }
        if isVeryCompactLayout { return 3 }
        return 4
    }

    private var inTheNewsRailLimit: Int {
        isCompactLayout ? 8 : 12
    }

    private var hasTimeCapsuleDetails: Bool {
        !primaryTimelineEvents.isEmpty || !feed.didYouKnow.isEmpty
    }

    private var newsBriefingLimit: Int {
        if isUltraCompactLayout { return 2 }
        if isVeryCompactLayout { return 3 }
        if isCompactLayout { return 4 }
        return 6
    }

    private var allTimeMostReadLimit: Int {
        if isUltraCompactLayout { return 10 }
        if availableWidth >= 1200 { return 22 }
        return isVeryCompactLayout ? 14 : 18
    }

    private var playlistRowLimit: Int {
        if isUltraCompactLayout { return 6 }
        if availableWidth >= 1200 { return 12 }
        return isVeryCompactLayout ? 8 : 10
    }

    private var allTimeMostReadLoadLimit: Int {
        max(allTimeMostReadLimit * 3, 48)
    }

    private var todayMostReadLimit: Int {
        if isUltraCompactLayout { return 8 }
        if isVeryCompactLayout { return 10 }
        if availableWidth >= 1200 { return 14 }
        return 12
    }

    private var allTimeMostReadEntries: [WikipediaService.AllTimeMostReadEntry] {
        Array(allTimeMostReadStore.entries.prefix(allTimeMostReadLimit))
    }

    private var todayMostReadItems: [WikipediaService.SearchResult] {
        Array(todayMostReadStore.results.prefix(todayMostReadLimit))
    }

    private var allTimeMostReadByTitleKey: [String: WikipediaService.AllTimeMostReadEntry] {
        allTimeMostReadStore.entries.reduce(into: [:]) { result, entry in
            let key = ReadStateSync.normalizedTitle(entry.result.title)
            guard !key.isEmpty else { return }
            result[key] = entry
        }
    }

    private var rankedMostReadItems: [WikipediaService.SearchResult] {
        allTimeMostReadEntries.map(\.result)
    }

    private var playlistMostReadItems: [WikipediaService.SearchResult] {
        Array(rankedMostReadItems.prefix(playlistRowLimit))
    }

    private var trendPulseItems: [WikipediaService.SearchResult] {
        var items: [WikipediaService.SearchResult] = []
        if let featuredArticle = feed.featuredArticle {
            items.append(featuredArticle)
        }
        items.append(contentsOf: playlistMostReadItems)
        return items
    }

    private var allTimeMostReadLoadKey: String {
        "\(allTimeMostReadLoadLimit)"
    }

    private var todayMostReadLoadKey: String {
        "today-most-read:\(refreshGeneration)"
    }

    private var todayTrendPulseLoadKey: Int {
        titleFingerprint(
            todayMostReadItems.map(\.title),
            seeds: [AnyHashable(feed.dateKey), AnyHashable("today-most-read-pulse")]
        )
    }

    private var trendPulseLoadKey: Int {
        titleFingerprint(
            trendPulseItems.map(\.title),
            seeds: [AnyHashable(feed.dateKey), AnyHashable("playlist-most-read-pulse")]
        )
    }

    private var featuredArticleTitle: String? {
        feed.featuredArticle?.title
    }

    private var featuredTeaserText: String? {
        guard let featuredArticleTitle else { return nil }
        return featuredSummaryStore.teaser(for: featuredArticleTitle)
    }

    private var isFeaturedTeaserLoading: Bool {
        featuredSummaryStore.isLoading && (featuredTeaserText == nil)
    }

    private var trendReferenceDate: Date {
        Self.featuredFeedDateFormatter.date(from: feed.dateKey) ?? Date()
    }

    private var mostReadPulseReferenceDate: Date {
        trendReferenceDate
    }

    private var timeMachineDisplayDateLabel: String {
        if showsTimeTravelSkeleton {
            return Self.timeMachineTargetDateFormatter.string(from: timeMachineTargetDate)
        }
        return feed.dateLabel
    }

    private func titleFingerprint<S: Sequence>(
        _ titles: S,
        seeds: [AnyHashable] = []
    ) -> Int where S.Element == String {
        var hasher = Hasher()
        for seed in seeds {
            hasher.combine(seed)
        }
        for title in titles {
            hasher.combine(ReadStateSync.normalizedTitle(title))
        }
        return hasher.finalize()
    }

    private var todayMostReadSubtitle: String {
        DiscoverEditionCopy.todayMostReadColumnSubtitle
    }

    private var playlistMostReadSubtitle: String {
        DiscoverEditionCopy.allTimeMostReadSubtitle
    }

    private var playlistLongestSubtitle: String {
        DiscoverEditionCopy.longestReadsSubtitle
    }

    private var mostReadCollectionMeta: String {
        allTimeMostReadStore.isLoading ? "Updating ranking" : "\(allTimeMostReadEntries.count) ranked"
    }

    private var longestCollectionMeta: String {
        wordCountStore.isLoading ? "Measuring length" : "\(keyboardLongestResults.count) candidates"
    }

    private var todayMostReadMeta: String {
        todayMostReadStore.isLoading ? "Refreshing" : "\(todayMostReadItems.count) articles today"
    }

    private var todayMostReadPreviewTitles: [String] {
        Array(todayMostReadItems.prefix(3).map(\.title))
    }

    private var mostReadPreviewTitles: [String] {
        Array(playlistMostReadItems.prefix(3).map(\.title))
    }

    private var longestReadsPreviewTitles: [String] {
        Array(keyboardLongestResults.prefix(3).map(\.title))
    }

    private var remainingNewsItems: [WikipediaService.SearchResult] {
        feed.inTheNews
    }

    private var primaryTimelineEvents: [WikipediaService.DiscoverFeed.OnThisDayEvent] {
        if !feed.onThisDaySelected.isEmpty {
            return Array(feed.onThisDaySelected.prefix(8))
        }
        return Array(feed.onThisDay.prefix(8))
    }

    private var leadTimelineEvent: WikipediaService.DiscoverFeed.OnThisDayEvent? {
        primaryTimelineEvents.first
    }

    private var supportingTimelineEvents: [WikipediaService.DiscoverFeed.OnThisDayEvent] {
        Array(primaryTimelineEvents.dropFirst())
    }

    private var hasTimeMachineDetails: Bool {
        return !feed.onThisDayBirths.isEmpty || !feed.onThisDayDeaths.isEmpty || !feed.holidays.isEmpty
    }

    private var hasTimeMachineSurface: Bool {
        showsTimeTravelSkeleton || hasTimeMachineDetails
    }

    private var longestReadCandidates: [WikipediaService.SearchResult] {
        Array(allTimeMostReadStore.entries.prefix(allTimeMostReadLoadLimit).map(\.result))
    }

    private var wordCountLoadKey: Int {
        titleFingerprint(
            longestReadCandidates.map(\.title),
            seeds: [AnyHashable("longest-word-count")]
        )
    }

    private var longestReadItems: [DiscoverLongestReadEntry] {
        let enriched = longestReadCandidates.compactMap { result -> DiscoverLongestReadEntry? in
            guard let wordCount = wordCountStore.wordCount(for: result.title), wordCount > 0 else {
                return nil
            }
            return DiscoverLongestReadEntry(result: result, wordCount: wordCount)
        }

        let sorted = enriched.sorted { lhs, rhs in
            if lhs.wordCount == rhs.wordCount {
                return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
            }
            return lhs.wordCount > rhs.wordCount
        }

        return Array(sorted.prefix(playlistRowLimit))
    }

    private var longestFallbackItems: [WikipediaService.SearchResult] {
        Array(longestReadCandidates.prefix(min(playlistRowLimit, 6)))
    }

    private var keyboardMostReadResults: [WikipediaService.SearchResult] {
        playlistMostReadItems
    }

    private var keyboardLongestResults: [WikipediaService.SearchResult] {
        if !longestReadItems.isEmpty {
            return longestReadItems.map(\.result)
        }
        return longestFallbackItems
    }

    private var collectionsKeyboardContext: DiscoverCollectionsKeyboardContext {
        DiscoverCollectionsKeyboardContext(
            mostReadCount: keyboardMostReadResults.count,
            longestCount: keyboardLongestResults.count
        )
    }

    private var visibleKeyboardLanes: [DiscoverCollectionLane] {
        collectionsKeyboardContext.visibleLanes
    }

    private var collectionsFocusDataKey: Int {
        var hasher = Hasher()
        hasher.combine(
            titleFingerprint(
                keyboardMostReadResults.map(\.title),
                seeds: [AnyHashable("keyboard-most-read")]
            )
        )
        hasher.combine(
            titleFingerprint(
                keyboardLongestResults.map(\.title),
                seeds: [AnyHashable("keyboard-longest")]
            )
        )
        return hasher.finalize()
    }

    private var canOpenFocusedCollectionItem: Bool {
        guard !showsTimeTravelSkeleton else { return false }
        guard currentCollectionsKeyboardState().isActive else { return false }
        return focusedCollectionResult != nil
    }

    private func pageViewsRowKey(
        section: String,
        result: WikipediaService.SearchResult,
        index: Int? = nil
    ) -> String {
        let titleKey = ReadStateSync.normalizedTitle(result.title)
        if let index {
            return "\(section):\(index):\(result.id):\(titleKey)"
        }
        return "\(section):\(result.id):\(titleKey)"
    }

    private func presentPageViewsPopover(
        for result: WikipediaService.SearchResult,
        rowKey: String,
        initialPulse: WikipediaService.TrendPulse? = nil
    ) {
        activePageViewsPopover = DiscoverPageViewsPopoverPayload(
            rowKey: rowKey,
            title: result.title,
            initialPulse: initialPulse,
            referenceDate: trendReferenceDate
        )
    }

    private func pageViewsPopoverBinding(for rowKey: String) -> Binding<Bool> {
        Binding(
            get: { activePageViewsPopover?.rowKey == rowKey },
            set: { isPresented in
                guard !isPresented else { return }
                if activePageViewsPopover?.rowKey == rowKey {
                    activePageViewsPopover = nil
                }
            }
        )
    }

    @ViewBuilder
    private func pageViewsPopover(for rowKey: String) -> some View {
        if let payload = activePageViewsPopover, payload.rowKey == rowKey {
            DiscoverPageViewsPopoverContent(
                title: payload.title,
                referenceDate: payload.referenceDate,
                initialPulse: payload.initialPulse
            )
        }
    }

    private var focusedCollectionResult: WikipediaService.SearchResult? {
        guard let selection = DiscoverCollectionsKeyboardCoordinator.focusedSelection(
            in: currentCollectionsKeyboardState(),
            context: collectionsKeyboardContext
        ) else {
            return nil
        }

        switch selection.lane {
        case .mostRead:
            guard keyboardMostReadResults.indices.contains(selection.index) else { return nil }
            return keyboardMostReadResults[selection.index]
        case .longest:
            guard keyboardLongestResults.indices.contains(selection.index) else { return nil }
            return keyboardLongestResults[selection.index]
        }
    }

    private func isFocusedCollectionRow(lane: DiscoverCollectionLane, index: Int) -> Bool {
        DiscoverCollectionsKeyboardCoordinator.isFocusedRow(
            lane: lane,
            index: index,
            state: currentCollectionsKeyboardState(),
            context: collectionsKeyboardContext
        )
    }

    private func markCollectionsFocus(lane: DiscoverCollectionLane, index: Int) {
        setCollectionExpansion(lane, isExpanded: true)
        applyCollectionsKeyboardState(
            DiscoverCollectionsKeyboardCoordinator.markedFocus(
                lane: lane,
                index: index,
                state: currentCollectionsKeyboardState(),
                context: collectionsKeyboardContext
            )
        )
    }

    private func collectionExpansionBinding(for lane: DiscoverCollectionLane) -> Binding<Bool> {
        Binding(
            get: {
                switch lane {
                case .mostRead:
                    return isMostReadCollectionExpanded
                case .longest:
                    return isLongestReadsCollectionExpanded
                }
            },
            set: { isExpanded in
                setCollectionExpansion(lane, isExpanded: isExpanded)
            }
        )
    }

    private func setCollectionExpansion(_ lane: DiscoverCollectionLane, isExpanded: Bool) {
        switch lane {
        case .mostRead:
            isMostReadCollectionExpanded = isExpanded
        case .longest:
            isLongestReadsCollectionExpanded = isExpanded
        }

        if !isExpanded && isCollectionsKeyboardFocusActive && focusedCollectionLane == lane {
            applyCollectionsKeyboardState(
                DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
            )
        }
    }

    private func normalizeCollectionsKeyboardFocus() {
        applyCollectionsKeyboardState(
            DiscoverCollectionsKeyboardCoordinator.normalized(
                currentCollectionsKeyboardState(),
                context: collectionsKeyboardContext
            )
        )
    }

    private func moveCollectionsFocus(_ direction: MoveCommandDirection) {
        guard !showsTimeTravelSkeleton else {
            applyCollectionsKeyboardState(
                DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
            )
            return
        }
        applyCollectionsKeyboardState(
            DiscoverCollectionsKeyboardCoordinator.moved(
                currentCollectionsKeyboardState(),
                direction: direction,
                isSearchFieldFocused: isSearchFieldFocused,
                context: collectionsKeyboardContext
            )
        )
    }

    private func openFocusedCollectionItem(inNewTab: Bool) {
        guard let result = focusedCollectionResult else { return }
        onOpen(result, inNewTab)
    }

    private func currentCollectionsKeyboardState() -> DiscoverCollectionsKeyboardState {
        DiscoverCollectionsKeyboardState(
            isActive: isCollectionsKeyboardFocusActive,
            focusedLane: focusedCollectionLane,
            focusedMostReadRowIndex: focusedMostReadRowIndex,
            focusedLongestRowIndex: focusedLongestRowIndex
        )
    }

    private func applyCollectionsKeyboardState(_ state: DiscoverCollectionsKeyboardState) {
        isCollectionsKeyboardFocusActive = state.isActive
        focusedCollectionLane = state.focusedLane
        focusedMostReadRowIndex = state.focusedMostReadRowIndex
        focusedLongestRowIndex = state.focusedLongestRowIndex

        if state.isActive {
            switch state.focusedLane {
            case .mostRead:
                isMostReadCollectionExpanded = true
            case .longest:
                isLongestReadsCollectionExpanded = true
            }
        }
    }

    @ViewBuilder
    private var collectionsKeyboardShortcutHost: some View {
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
    private var mostReadCollectionModule: some View {
        DiscoverExpandableCollectionCard(
            title: "Most Read",
            subtitle: playlistMostReadSubtitle,
            meta: mostReadCollectionMeta,
            systemImage: "chart.line.uptrend.xyaxis",
            tint: .accentColor,
            showsLoading: trendPulseStore.isLoading,
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
    private var longestReadsCollectionModule: some View {
        DiscoverExpandableCollectionCard(
            title: "Longest Reads",
            subtitle: playlistLongestSubtitle,
            meta: longestCollectionMeta,
            systemImage: "text.alignleft",
            tint: Color.orange.opacity(0.92),
            showsLoading: wordCountStore.isLoading,
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
    private var todayMostReadSection: some View {
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
                DiscoverPlaylistPlaceholder(
                    text: todayMostReadStore.isLoading
                        ? "Loading today's most read..."
                        : "Today's Most Read is unavailable right now."
                )
            } else {
                ForEach(Array(todayMostReadItems.enumerated()), id: \.element.id) { index, result in
                    let rowKey = pageViewsRowKey(section: "today-most-read", result: result, index: index)
                    let trendPulse = todayMostReadPulse(for: result)
                    DiscoverPlaylistArticleRow(
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
            }
        }
    }

    @ViewBuilder
    private var newsBriefingSection: some View {
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
    private var openingEditorialSpread: some View {
        VStack(alignment: .leading, spacing: 18) {
            todayMostReadSection
            newsBriefingSection
        }
    }

    @ViewBuilder
    private var collectionsStage: some View {
        VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 16) {
            DiscoverSectionHeader(
                title: "Collections",
                subtitle: DiscoverEditionCopy.collectionsSubtitle
            )

            VStack(alignment: .leading, spacing: 16) {
                mostReadCollectionModule
                longestReadsCollectionModule
            }
        }
    }

    @ViewBuilder
    private var mediaSpotlightSection: some View {
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
    private var mediaSpotlightImageModule: some View {
        if let featuredImage = feed.featuredImage {
            DiscoverEditorialPanel(accent: Color.indigo.opacity(0.82), tone: .feature) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(title: "Image of the Day", subtitle: DiscoverEditionCopy.imageOfTheDaySubtitle)
                    DiscoverFeaturedImageCard(
                        image: featuredImage,
                        prefersHorizontalLayout: false
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var inTheNewsModule: some View {
        if !remainingNewsItems.isEmpty {
            DiscoverEditorialPanel(accent: Color.red.opacity(0.78), tone: .notebook) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(title: "In the News", subtitle: DiscoverEditionCopy.inTheNewsSubtitle)
                    VStack(spacing: 10) {
                        ForEach(remainingNewsItems.prefix(inTheNewsRailLimit)) { result in
                            let rowKey = pageViewsRowKey(section: "in-news", result: result)
                            DiscoverNewsCard(result: result, onOpen: onOpen)
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
    private var timeCapsuleHistoryModule: some View {
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
    private var timeCapsuleDidYouKnowModule: some View {
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

    @ViewBuilder
    private var timeCapsuleStage: some View {
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
    private var timeMachineBirthsModule: some View {
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
    private var timeMachineDeathsModule: some View {
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
    private var timeMachineHolidaysModule: some View {
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
    private var timeMachineStage: some View {
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

                        if showsTimeTravelSkeleton {
                            AppLoadingInlineLabel(
                                text: "Scanning",
                                tone: .retro,
                                font: .caption.weight(.semibold)
                            )
                            .fixedSize()
                        }

                        if !timeMachineDisplayDateLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(timeMachineDisplayDateLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.055), in: Capsule())
                        }
                    }

                    if showsTimeTravelSkeleton {
                        DiscoverTimeMachineLoadingContent(isCompactLayout: isCompactLayout)
                    } else {
                        if !feed.onThisDayBirths.isEmpty || !feed.onThisDayDeaths.isEmpty {
                            timeMachineBirthsModule
                            timeMachineDeathsModule
                        }

                        timeMachineHolidaysModule
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var temporalExplorationStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            timeCapsuleStage
            timeMachineStage
        }
    }

    @ViewBuilder
    private var leadEditionStage: some View {
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
    private func featuredStoryModule(_ featured: WikipediaService.SearchResult) -> some View {
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

    var body: some View {
        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
            if showsTimeTravelSkeleton {
                timeMachineStage
            } else {
                leadEditionStage
                collectionsStage
                mediaSpotlightSection
                temporalExplorationStage
            }
        }
        .background {
            collectionsKeyboardShortcutHost
        }
        .onAppear {
            normalizeCollectionsKeyboardFocus()
        }
        .onChange(of: feed.dateKey) { _, _ in
            activePageViewsPopover = nil
        }
        .onChange(of: collectionsFocusDataKey) { _, _ in
            normalizeCollectionsKeyboardFocus()
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused {
                applyCollectionsKeyboardState(
                    DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
                )
            }
        }
        .onMoveCommand { direction in
            moveCollectionsFocus(direction)
        }
        .onExitCommand {
            applyCollectionsKeyboardState(
                DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
            )
        }
        .task(id: todayMostReadLoadKey) {
            todayMostReadStore.queueLoad(forceRefresh: refreshGeneration > 0)
        }
        .task(id: allTimeMostReadLoadKey) {
            allTimeMostReadStore.queueLoad(limit: allTimeMostReadLoadLimit)
        }
        .task(id: todayTrendPulseLoadKey) {
            todayTrendPulseStore.queueLoad(
                results: todayMostReadItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: trendPulseLoadKey) {
            trendPulseStore.queueLoad(
                results: trendPulseItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: wordCountLoadKey) {
            wordCountStore.queueLoad(results: longestReadCandidates)
        }
        .task(id: featuredArticleTitle) {
            featuredSummaryStore.queueLoad(featuredTitle: featuredArticleTitle)
            visualContextStore.queueLoad(featuredTitle: featuredArticleTitle)
        }
        .onDisappear {
            todayMostReadStore.cancel()
            todayTrendPulseStore.cancel()
            allTimeMostReadStore.cancel()
            trendPulseStore.cancel()
            wordCountStore.cancel()
            featuredSummaryStore.cancel()
            visualContextStore.cancel()
        }
    }

    private func mostReadPulse(for result: WikipediaService.SearchResult) -> WikipediaService.TrendPulse? {
        trendPulseStore.pulse(for: result.title)
    }

    private func todayMostReadPulse(for result: WikipediaService.SearchResult) -> WikipediaService.TrendPulse? {
        todayTrendPulseStore.pulse(for: result.title)
    }

    private func allTimeMostReadEntry(
        for result: WikipediaService.SearchResult
    ) -> WikipediaService.AllTimeMostReadEntry? {
        allTimeMostReadByTitleKey[ReadStateSync.normalizedTitle(result.title)]
    }

    private func mostReadPrimaryStat(for result: WikipediaService.SearchResult) -> String {
        if let allTimeViews = allTimeMostReadEntry(for: result)?.totalViews {
            return "\(abbreviatedViewCount(allTimeViews)) all-time"
        }
        guard let pulse = mostReadPulse(for: result) else {
            return trendPulseStore.isLoading ? "All-time loading…" : "All-time unavailable"
        }
        return "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    private func mostReadSecondaryStat(for result: WikipediaService.SearchResult) -> String? {
        guard let pulse = mostReadPulse(for: result) else {
            return trendPulseStore.isLoading ? "Loading recent pulse…" : "Recent pulse unavailable"
        }
        return ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews,
            fallback: "No delta yet",
            suffix: "recent"
        )
    }

    private func mostReadStatTint(for result: WikipediaService.SearchResult) -> Color {
        guard let pulse = mostReadPulse(for: result),
              let fraction = trendDeltaFraction(for: pulse) else {
            return .secondary
        }

        if fraction > 0 { return Color.green.opacity(0.85) }
        if fraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    private func todayMostReadPrimaryStat(for result: WikipediaService.SearchResult) -> String {
        guard let pulse = todayMostReadPulse(for: result) else {
            return todayTrendPulseStore.isLoading ? "Views loading…" : "Views unavailable"
        }
        return "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    private func todayMostReadSecondaryStat(for result: WikipediaService.SearchResult) -> String? {
        guard let pulse = todayMostReadPulse(for: result) else {
            return todayTrendPulseStore.isLoading ? nil : "No trend data"
        }
        return ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews,
            fallback: "No delta yet"
        )
    }

    private func todayMostReadStatTint(for result: WikipediaService.SearchResult) -> Color {
        guard let pulse = todayMostReadPulse(for: result),
              let fraction = trendDeltaFraction(for: pulse) else {
            return .secondary
        }

        if fraction > 0 { return Color.green.opacity(0.85) }
        if fraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    private func trendDeltaFraction(for pulse: WikipediaService.TrendPulse) -> Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return Double(pulse.latestViews - previous) / Double(previous)
    }

    private func formattedWordCount(_ wordCount: Int) -> String {
        ArticlePresentationFormatter.wordCountText(wordCount)
    }

    private func estimatedReadingTimeText(for wordCount: Int) -> String {
        ArticlePresentationFormatter.readingTimeText(forWordCount: wordCount)
    }

    private func formattedReadingDuration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        if remainderMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainderMinutes)m"
    }

    private static let featuredFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let timeMachineTargetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    @ViewBuilder
    private func discoverContextMenu(
        for result: WikipediaService.SearchResult,
        onShowPageViews: (() -> Void)? = nil
    ) -> some View {
        SearchResultContextMenuContent(
            result: result,
            allLists: allLists,
            allLabels: allLabels,
            allTags: allTags,
            onOpen: { inNewTab in
                onOpen(result, inNewTab)
            },
            onShowPageViews: onShowPageViews
        )
    }
}

struct DiscoverMasthead: View {
    let dateLabel: String
    let isCompactLayout: Bool

    private var trimmedDateLabel: String {
        dateLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today’s Edition")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)

                    Text("Discover")
                        .font(.system(size: isCompactLayout ? 30 : 36, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                if !trimmedDateLabel.isEmpty {
                    Text(trimmedDateLabel)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.6)
                        }
                        .multilineTextAlignment(.trailing)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }
}

struct DiscoverSectionHeader: View {
    let title: String
    let subtitle: String

    private var normalizedSubtitle: String {
        subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsSubtitle: Bool {
        !normalizedSubtitle.isEmpty && normalizedSubtitle != "PLACEHOLDER"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsSubtitle ? 3 : 0) {
            if showsSubtitle {
                Text(normalizedSubtitle)
                    .font(DiscoverTypography.sectionSubtitle)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(DiscoverTypography.sectionTitle)
                .foregroundStyle(.primary)
        }
    }
}

enum DiscoverEditorialPanelTone {
    case feature
    case notebook
    case atlas
    case archive
    case timewarp

    func backgroundColors(accent: Color) -> [Color] {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return [
                Color(nsColor: .controlBackgroundColor).opacity(0.34),
                Color(nsColor: .windowBackgroundColor).opacity(0.18)
            ]
        }
    }

    var topRuleHeight: CGFloat {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp: return 0
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return 16
        }
    }

    var borderOpacity: Double {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return 0.08
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return 0.04
        }
    }
}

struct DiscoverEditorialPanel<Content: View>: View {
    let accent: Color
    var tone: DiscoverEditorialPanelTone = .feature
    var contentPadding: CGFloat = 16
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: Color,
        tone: DiscoverEditorialPanelTone = .feature,
        contentPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.tone = tone
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        let cornerRadius = tone.cornerRadius

        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(contentPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { editorialGlassBackground(cornerRadius: cornerRadius) }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(0.30))
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(tone.shadowOpacity), radius: 8, y: 3)
    }

    @ViewBuilder
    private func editorialGlassBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let accentOpacity = colorScheme == .dark ? 0.055 : 0.078

        if #available(macOS 26, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(accentOpacity),
                                Color(nsColor: .controlBackgroundColor).opacity(0.20),
                                Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.035 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        } else {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(accentOpacity),
                                Color(nsColor: .controlBackgroundColor).opacity(0.25),
                                Color(nsColor: .windowBackgroundColor).opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        }
    }
}

struct DiscoverInsetPanel<Content: View>: View {
    let accent: Color
    var contentPadding: CGFloat = 12
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: Color,
        contentPadding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(contentPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { insetGlassBackground }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.32), lineWidth: 0.7)
        }
    }

    @ViewBuilder
    private var insetGlassBackground: some View {
        let cornerRadius: CGFloat = 14
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if #available(macOS 26, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(colorScheme == .dark ? 0.045 : 0.07),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        } else {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [accent.opacity(0.06), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        }
    }
}

struct DiscoverTemporalSubsectionHeader: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Label(title, systemImage: systemImage)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(accent.opacity(0.18))
                .frame(height: 1)
                .padding(.leading, 2)
        }
    }
}

struct DiscoverLongestReadEntry: Identifiable {
    let result: WikipediaService.SearchResult
    let wordCount: Int

    var id: String {
        "\(result.id)-\(result.title.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

struct DiscoverExpandableCollectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let meta: String?
    let systemImage: String
    let tint: Color
    let showsLoading: Bool
    let isKeyboardFocused: Bool
    @Binding var isExpanded: Bool
    let collapsedPreviewTitles: [String]
    let content: Content
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.16)
    }

    init(
        title: String,
        subtitle: String,
        meta: String? = nil,
        systemImage: String,
        tint: Color,
        showsLoading: Bool = false,
        isKeyboardFocused: Bool = false,
        isExpanded: Binding<Bool>,
        collapsedPreviewTitles: [String] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.systemImage = systemImage
        self.tint = tint
        self.showsLoading = showsLoading
        self.isKeyboardFocused = isKeyboardFocused
        self._isExpanded = isExpanded
        self.collapsedPreviewTitles = collapsedPreviewTitles
        self.content = content()
    }

    var body: some View {
        let cornerRadius: CGFloat = 18

        VStack(alignment: .leading, spacing: 0) {
            headerButton

            cardBodyContent
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { collectionGlassBackground(cornerRadius: cornerRadius) }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(isKeyboardFocused ? 0.80 : (isHovered ? 0.64 : 0.42)))
                .frame(width: 3)
                .padding(.vertical, 13)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    isKeyboardFocused
                        ? tint.opacity(0.62)
                        : Color(nsColor: .separatorColor).opacity(isHovered ? 0.48 : 0.30),
                    lineWidth: isKeyboardFocused ? 1.1 : 0.7
                )
        }
        .discoverHoverEffect(.card, isActive: isHovered || isKeyboardFocused, reduceMotion: reduceMotion)
        .animation(hoverAnimation, value: isKeyboardFocused)
        .animation(hoverAnimation, value: isHovered)
        .animation(expansionAnimation, value: isExpanded)
        .onHover { isHovered = $0 }
    }

    private var headerButton: some View {
        Button {
            withAnimation(expansionAnimation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                collectionIcon
                collectionTitleBlock
                Spacer(minLength: 8)
                loadingIndicator
                disclosureIndicator
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse \(title)" : "Expand \(title)")
        .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")
    }

    private var collectionIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.96))
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(
                    colors: [
                        tint.opacity(0.94),
                        tint.opacity(colorScheme == .dark ? 0.60 : 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .shadow(color: tint.opacity(isHovered || isKeyboardFocused ? 0.22 : 0.12), radius: 8, y: 3)
            .symbolEffect(.bounce, value: isExpanded)
    }

    private var collectionTitleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let meta, !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if showsLoading {
            AppLoadingActivityMark(tone: .accent, tint: tint)
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isExpanded ? tint : Color.secondary.opacity(0.62))
            .frame(width: 28, height: 28)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(tint.opacity(isExpanded ? 0.26 : 0.12), lineWidth: 0.7)
            }
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .animation(expansionAnimation, value: isExpanded)
    }

    @ViewBuilder
    private var cardBodyContent: some View {
        if isExpanded {
            expandedContent
                .padding(.top, 12)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -4)),
                        removal: .opacity.combined(with: .offset(y: -2))
                    )
                )
        } else if !collapsedPreviewTitles.isEmpty {
            collapsedPreview
                .padding(.top, 10)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -3)),
                        removal: .opacity.combined(with: .offset(y: -2))
                    )
                )
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.36))
                .frame(height: 0.7)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    @ViewBuilder
    private func collectionGlassBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isActive = isHovered || isKeyboardFocused
        let glowOpacity = isActive ? 0.18 : 0.11
        let baseWash = colorScheme == .dark ? 0.42 : 0.82
        let tintWash = colorScheme == .dark ? 0.045 : 0.060

        if #available(macOS 26, *) {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(glowOpacity),
                                tint.opacity(tintWash),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape
                        .inset(by: 0.5)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(baseWash))
                }
                .overlay {
                    shape
                        .inset(by: 1)
                        .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.035 : 0.38),
                                Color.white.opacity(colorScheme == .dark ? 0.012 : 0.10),
                                tint.opacity(colorScheme == .dark ? 0.020 : 0.030)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.46), lineWidth: 0.8)
                        .blendMode(.plusLighter)
                }
        } else {
            shape
                .fill(.regularMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(baseWash))
                }
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(glowOpacity),
                                tint.opacity(0.028),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
        }
    }

    private var collapsedPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(collapsedPreviewTitles.enumerated()), id: \.offset) { index, title in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .frame(width: 18, alignment: .leading)

                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.36 : 0.78),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.26), lineWidth: 0.6)
                }
            }
        }
    }
}

struct DiscoverPlaylistPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct DiscoverInteractivePressStyle: ButtonStyle {
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.985
    var pressedOpacity: Double = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

struct DiscoverPlaylistArticleRow: View {
    let result: WikipediaService.SearchResult
    let rank: Int
    let primaryStat: String
    let secondaryStat: String?
    let statTint: Color
    let isKeyboardFocused: Bool
    let onFocus: (() -> Void)?
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var rowFill: Color {
        if isKeyboardFocused {
            return statTint.opacity(colorScheme == .dark ? 0.24 : 0.17)
        }
        if isHovered {
            return Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.48 : 0.84)
        }
        return Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.36 : 0.74)
    }

    private var rowStroke: Color {
        if isKeyboardFocused {
            return statTint.opacity(0.56)
        }
        if isHovered {
            return Color(nsColor: .separatorColor).opacity(0.42)
        }
        return Color(nsColor: .separatorColor).opacity(0.20)
    }

    var body: some View {
        Button {
            onFocus?()
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(rank)")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)

                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 46,
                    cornerRadius: 8,
                    imagePadding: 3
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(MacWikiTypography.compactRowTitle)
                        .lineLimit(2)
                    if let description = result.description, !description.isEmpty {
                        Text(description)
                            .font(MacWikiTypography.settingsHelp)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1.5) {
                    Text(primaryStat)
                        .font(MacWikiTypography.compactStatistic)
                        .foregroundStyle(statTint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .monospacedDigit()

                    if let secondaryStat, !secondaryStat.isEmpty {
                        Text(secondaryStat)
                            .font(MacWikiTypography.compactStatistic)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(rowStroke, lineWidth: isKeyboardFocused ? 1.05 : 0.75)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .discoverHoverEffect(.row, isActive: isHovered || isKeyboardFocused, reduceMotion: reduceMotion)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isKeyboardFocused)
        .accessibilityLabel(result.title)
        .accessibilityValue(secondaryStat.map { "\(primaryStat), \($0)" } ?? primaryStat)
        .accessibilityHint("Open article. Use arrows to move focus and Return to open.")
    }
}

enum DiscoverTypography {
    static let sectionTitle = Font.system(size: 20, weight: .semibold)
    static let sectionSubtitle = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    static let featureTitle = Font.system(size: 29, weight: .semibold)
    static let featureDescription = Font.system(size: 14, weight: .regular)
    static let newsCardTitle = Font.system(size: 14.5, weight: .semibold)
    static let newsRailTitle = Font.system(size: 15, weight: .semibold)
    static let newsCardDescription = Font.system(size: 11.5, weight: .regular)
    static let compactRank = Font.system(size: 14.5, weight: .semibold, design: .rounded)
    static let compactTitle = Font.system(size: 12.5, weight: .medium)
    static let compactDescription = Font.system(size: 11, weight: .regular)
    static let storyBody = Font.system(size: 14, weight: .regular)
    static let mediaTitle = Font.system(size: 16.5, weight: .semibold, design: .rounded)
    static let mediaDescription = Font.system(size: 12.5, weight: .regular)
    static let mediaMeta = Font.system(size: 11.5, weight: .medium)
}

struct DiscoverFeatureModule: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let trendPulse: WikipediaService.TrendPulse?
    let isTrendPulseLoading: Bool
    let visualContextImages: [WikipediaService.VisualContextImage]
    let isVisualContextLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let isCompactLayout: Bool
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let onOpenURL: (URL) -> Void
    let onTrendTapped: (WikipediaService.TrendPulse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoverFeatureCard(
                result: result,
                teaserText: teaserText,
                isTeaserLoading: isTeaserLoading,
                trendPulse: trendPulse,
                isTrendPulseLoading: isTrendPulseLoading,
                heroImageHeight: heroImageHeight,
                titleLineLimit: titleLineLimit,
                descriptionLineLimit: descriptionLineLimit,
                onOpen: onOpen,
                onTrendTapped: onTrendTapped,
                showsSurface: false
            )
            .padding(12)

            Divider()
                .overlay(Color.primary.opacity(0.05))

            Group {
                if isVisualContextLoading {
                    AppLoadingInlineLabel(
                        text: "Loading visual context…",
                        tone: .accent,
                        font: .system(size: 12.5, weight: .medium)
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else if !visualContextImages.isEmpty {
                    DiscoverVisualContextStrip(
                        images: visualContextImages,
                        isCompactLayout: isCompactLayout,
                        showsSurface: false,
                        onOpenURL: onOpenURL
                    )
                    .padding(12)
                } else {
                    Text(DiscoverEditionCopy.visualContextUnavailable)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.34), lineWidth: 0.7)
        }
    }
}

struct DiscoverFeatureCard: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let trendPulse: WikipediaService.TrendPulse?
    let isTrendPulseLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let onTrendTapped: (WikipediaService.TrendPulse) -> Void
    var showsSurface: Bool = true
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var suppressPrimaryTapFromTrend = false

    private var displayTitle: String {
        let trimmed = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Featured Story" : trimmed
    }

    private var displayDescription: String? {
        guard let description = result.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else {
            return nil
        }
        return description
    }

    var body: some View {
        Button {
            if suppressPrimaryTapFromTrend {
                suppressPrimaryTapFromTrend = false
                return
            }
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                featureImage
                .frame(maxWidth: .infinity)
                .frame(height: heroImageHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(DiscoverEditionCopy.leadKicker)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Text(displayTitle)
                        .font(DiscoverTypography.featureTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(titleLineLimit)
                        .lineSpacing(2)

                    if let displayDescription {
                        Text(displayDescription)
                            .font(DiscoverTypography.featureDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(descriptionLineLimit)
                            .lineSpacing(1.5)
                    }

                    featuredStats

                    if isTeaserLoading {
                        AppLoadingInlineLabel(
                            text: "Loading article teaser…",
                            tone: .accent,
                            font: .system(size: 11.5, weight: .medium)
                        )
                        .padding(.top, 2)
                    } else if let teaserText, !teaserText.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(teaserText)
                                .font(.system(size: 13.5, weight: .regular))
                                .foregroundStyle(.secondary)
                                .lineLimit(9)
                                .lineSpacing(1.45)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(displayTitle)
        .frame(minHeight: heroImageHeight + 72)
        .background(
            Group {
                if showsSurface {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if showsSurface {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.46 : 0.32), lineWidth: 0.8)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.36 : 0.18), lineWidth: 0.7)
            }
        }
        .discoverHoverEffect(.hero, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var featuredStats: some View {
        if let trendPulse {
            DiscoverTrendPulseBadge(
                pulse: trendPulse,
                onTap: {
                    suppressPrimaryTapFromTrend = true
                    onTrendTapped(trendPulse)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        suppressPrimaryTapFromTrend = false
                    }
                }
            )
            .padding(.top, 3)
        } else if isTrendPulseLoading {
            AppLoadingInlineLabel(
                text: "Loading page views…",
                tone: .retro,
                font: .system(size: 11.5, weight: .medium)
            )
            .padding(.top, 3)
        }
    }

    @ViewBuilder
    private var featureImage: some View {
        if let thumbnailURL = result.thumbnailURL {
            CachedThumbnailImage(
                url: thumbnailURL,
                targetSize: CGSize(width: 980, height: heroImageHeight),
                animatesNetworkSuccess: !reduceMotion
            ) { image in
                ZStack {
                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } placeholder: {
                AppLoadingThumbnailPlaceholder(
                    width: 320,
                    height: heroImageHeight,
                    cornerRadius: 14,
                    tone: .accent
                )
            } failure: {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.25), Color.blue.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        } else {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.25), Color.blue.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct DiscoverNewsCard: View {
    let result: WikipediaService.SearchResult
    var style: DiscoverNewsCardStyle = .standard
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            if style == .rail {
                HStack(alignment: .top, spacing: 10) {
                    newsThumbnail
                        .frame(width: 94, height: 94)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.title)
                            .font(DiscoverTypography.newsRailTitle)
                            .lineLimit(3)
                            .lineSpacing(1.2)
                        if let description = result.description {
                            Text(description)
                                .font(DiscoverTypography.newsCardDescription)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .lineSpacing(1.1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    newsThumbnail
                        .frame(height: 120)
                    Text(result.title)
                        .font(DiscoverTypography.newsCardTitle)
                        .lineLimit(2)
                        .lineSpacing(1.2)
                    if let description = result.description {
                        Text(description)
                            .font(DiscoverTypography.newsCardDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(1.1)
                    }
                }
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .padding(style == .rail ? 10 : 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.46 : 0.32), lineWidth: 0.7)
        }
        .discoverHoverEffect(.card, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var newsThumbnail: some View {
        if let thumbnailURL = result.thumbnailURL {
            CachedThumbnailImage(
                url: thumbnailURL,
                targetSize: style.thumbnailTargetSize,
                animatesNetworkSuccess: !reduceMotion
            ) { image in
                ZStack {
                    Rectangle()
                        .fill(Color.primary.opacity(0.04))
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            } placeholder: {
                AppLoadingThumbnailPlaceholder(
                    width: style.thumbnailTargetSize.width,
                    height: style.thumbnailTargetSize.height,
                    cornerRadius: 10,
                    tone: .accent
                )
            } failure: {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
            }
            .frame(width: style == .rail ? style.thumbnailTargetSize.width : nil)
            .frame(maxWidth: style == .standard ? .infinity : nil)
            .frame(height: style.thumbnailTargetSize.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

enum DiscoverNewsCardStyle {
    case standard
    case rail

    var thumbnailTargetSize: CGSize {
        switch self {
        case .standard:
            return CGSize(width: 220, height: 116)
        case .rail:
            return CGSize(width: 94, height: 94)
        }
    }
}

struct DiscoverCompactArticleCard: View {
    let result: WikipediaService.SearchResult
    let rank: Int
    let trendPulse: WikipediaService.TrendPulse?
    var onTrendTapped: ((WikipediaService.TrendPulse) -> Void)? = nil
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @State private var suppressPrimaryTapFromTrend = false

    var body: some View {
        Button {
            if suppressPrimaryTapFromTrend {
                suppressPrimaryTapFromTrend = false
                return
            }
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            HStack(spacing: 9) {
                Text("\(rank)")
                    .font(DiscoverTypography.compactRank)
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading)

                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 62,
                    cornerRadius: 8,
                    imagePadding: 4
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.title)
                        .font(DiscoverTypography.compactTitle)
                        .lineLimit(2)
                        .lineSpacing(1.05)
                    if let description = result.description {
                        Text(description)
                            .font(DiscoverTypography.compactDescription)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .lineSpacing(1.0)
                    }
                    if let trendPulse {
                        DiscoverTrendPulseBadge(
                            pulse: trendPulse,
                            onTap: {
                                suppressPrimaryTapFromTrend = true
                                onTrendTapped?(trendPulse)
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 700_000_000)
                                    suppressPrimaryTapFromTrend = false
                                }
                            }
                        )
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(result.title)
        .padding(9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct DiscoverTrendPulseBadge: View {
    let pulse: WikipediaService.TrendPulse
    var onTap: (() -> Void)? = nil

    private var deltaFraction: Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return (Double(pulse.latestViews - previous) / Double(previous))
    }

    private var deltaText: String {
        ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews
        )
    }

    private var trendSymbol: String {
        guard let deltaFraction else { return "chart.line.uptrend.xyaxis" }
        return deltaFraction < 0 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis"
    }

    private var trendColor: Color {
        guard let deltaFraction else { return .secondary }
        if deltaFraction > 0 { return Color.green.opacity(0.85) }
        if deltaFraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    private var latestViewsText: String {
        abbreviatedViewCount(pulse.latestViews)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: trendSymbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(trendColor)

            DiscoverSparkline(points: pulse.points, tint: trendColor)
                .frame(width: 54, height: 14)

            Text(deltaText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(trendColor)
                .lineLimit(1)

            Text("\(latestViewsText) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(trendColor.opacity(0.10), in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(trendColor.opacity(0.18), lineWidth: 0.7)
        }
        .contentShape(Capsule())
        .highPriorityGesture(
            TapGesture().onEnded {
                onTap?()
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(deltaText), \(latestViewsText) views")
        .accessibilityHint("Show views details")
        .accessibilityAction {
            onTap?()
        }
        .help("Show views details")
    }
}
