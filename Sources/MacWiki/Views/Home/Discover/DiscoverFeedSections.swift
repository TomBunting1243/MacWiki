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
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

    private var usesOpeningModuleSplit: Bool {
        availableWidth >= 760 && !feed.newsStories.isEmpty
    }

    private var openingModuleColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 280), spacing: 14),
            GridItem(.flexible(minimum: 280), spacing: 14)
        ]
    }

    private var usesCollectionsExplorationSplit: Bool {
        availableWidth >= 1040
    }

    private var collectionsExplorationRailWidth: CGFloat {
        min(max(availableWidth * 0.34, 318), 372)
    }

    private var usesMediaSpotlightSplit: Bool {
        availableWidth >= 980 && feed.featuredImage != nil && !remainingNewsItems.isEmpty
    }

    private var mediaSpotlightRailWidth: CGFloat {
        min(max(availableWidth * 0.31, 292), 344)
    }

    private var inTheNewsRailLimit: Int {
        usesMediaSpotlightSplit ? 4 : (isCompactLayout ? 8 : 12)
    }

    private var usesTimeCapsuleSpread: Bool {
        availableWidth >= 940 && !primaryTimelineEvents.isEmpty && !feed.didYouKnow.isEmpty
    }

    private var timeCapsuleRailWidth: CGFloat {
        min(max(availableWidth * 0.33, 292), 356)
    }

    private var hasTimeCapsuleDetails: Bool {
        !primaryTimelineEvents.isEmpty || !feed.didYouKnow.isEmpty
    }

    private var usesTemporalExplorationSpread: Bool {
        availableWidth >= 1120 && hasTimeCapsuleDetails && hasTimeMachineDetails
    }

    private var temporalExplorationRailWidth: CGFloat {
        min(max(availableWidth * 0.39, 352), 424)
    }

    private var usesTimeMachineTwinColumns: Bool {
        availableWidth >= 900 && !feed.onThisDayBirths.isEmpty && !feed.onThisDayDeaths.isEmpty
    }

    private var playlistColumns: [GridItem] {
        if availableWidth < 900 {
            return [GridItem(.flexible(minimum: 280), spacing: 0)]
        }
        return [
            GridItem(.flexible(minimum: 300), spacing: 12),
            GridItem(.flexible(minimum: 300), spacing: 12)
        ]
    }

    private var newsBriefingLimit: Int {
        if isUltraCompactLayout { return 2 }
        if isVeryCompactLayout { return 3 }
        if isCompactLayout { return 4 }
        return 6
    }

    private var allTimeMostReadLimit: Int {
        if isUltraCompactLayout { return 10 }
        return isVeryCompactLayout ? 14 : 18
    }

    private var playlistRowLimit: Int {
        if isUltraCompactLayout { return 6 }
        return isVeryCompactLayout ? 8 : 10
    }

    private var allTimeMostReadLoadLimit: Int {
        max(allTimeMostReadLimit * 3, 48)
    }

    private var todayMostReadLimit: Int {
        if isUltraCompactLayout { return 8 }
        if isVeryCompactLayout { return 10 }
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
            playlistMostReadItems.map(\.title),
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
        "PLACEHOLDER"
    }

    private var playlistMostReadSubtitle: String {
        "PLACEHOLDER"
    }

    private var playlistLongestSubtitle: String {
        "PLACEHOLDER"
    }

    private var mostReadCollectionMeta: String {
        "PLACEHOLDER"
    }

    private var longestCollectionMeta: String {
        "PLACEHOLDER"
    }

    private var todayMostReadMeta: String {
        "PLACEHOLDER"
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

    private var visibleKeyboardLanes: [DiscoverCollectionLane] {
        var lanes: [DiscoverCollectionLane] = []
        if !keyboardMostReadResults.isEmpty {
            lanes.append(.mostRead)
        }
        if !keyboardLongestResults.isEmpty {
            lanes.append(.longest)
        }
        return lanes
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
        guard isCollectionsKeyboardFocusActive else { return false }
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
        switch focusedCollectionLane {
        case .mostRead:
            guard keyboardMostReadResults.indices.contains(focusedMostReadRowIndex) else { return nil }
            return keyboardMostReadResults[focusedMostReadRowIndex]
        case .longest:
            guard keyboardLongestResults.indices.contains(focusedLongestRowIndex) else { return nil }
            return keyboardLongestResults[focusedLongestRowIndex]
        }
    }

    private func rowCount(for lane: DiscoverCollectionLane) -> Int {
        switch lane {
        case .mostRead: return keyboardMostReadResults.count
        case .longest: return keyboardLongestResults.count
        }
    }

    private func focusedRowIndex(for lane: DiscoverCollectionLane) -> Int {
        switch lane {
        case .mostRead: return focusedMostReadRowIndex
        case .longest: return focusedLongestRowIndex
        }
    }

    private func setFocusedRowIndex(_ index: Int, for lane: DiscoverCollectionLane) {
        let upperBound = max(rowCount(for: lane) - 1, 0)
        let clamped = min(max(index, 0), upperBound)
        switch lane {
        case .mostRead:
            focusedMostReadRowIndex = clamped
        case .longest:
            focusedLongestRowIndex = clamped
        }
    }

    private func isFocusedCollectionRow(lane: DiscoverCollectionLane, index: Int) -> Bool {
        guard isCollectionsKeyboardFocusActive else { return false }
        guard focusedCollectionLane == lane else { return false }
        return focusedRowIndex(for: lane) == index
    }

    private func markCollectionsFocus(lane: DiscoverCollectionLane, index: Int) {
        focusedCollectionLane = lane
        setFocusedRowIndex(index, for: lane)
        isCollectionsKeyboardFocusActive = true
    }

    private func normalizeCollectionsKeyboardFocus() {
        let lanes = visibleKeyboardLanes
        guard !lanes.isEmpty else {
            isCollectionsKeyboardFocusActive = false
            focusedMostReadRowIndex = 0
            focusedLongestRowIndex = 0
            return
        }

        if !lanes.contains(focusedCollectionLane) {
            focusedCollectionLane = lanes.contains(.mostRead) ? .mostRead : lanes[0]
        }

        setFocusedRowIndex(focusedMostReadRowIndex, for: .mostRead)
        setFocusedRowIndex(focusedLongestRowIndex, for: .longest)
    }

    private func shiftCollectionsFocusLane(_ direction: MoveCommandDirection) {
        let lanes = visibleKeyboardLanes
        guard lanes.count > 1 else { return }
        guard let laneIndex = lanes.firstIndex(of: focusedCollectionLane) else {
            focusedCollectionLane = lanes[0]
            setFocusedRowIndex(0, for: lanes[0])
            return
        }

        let targetLaneIndex: Int
        if direction == .left {
            targetLaneIndex = max(laneIndex - 1, 0)
        } else if direction == .right {
            targetLaneIndex = min(laneIndex + 1, lanes.count - 1)
        } else {
            return
        }

        guard targetLaneIndex != laneIndex else { return }
        let targetLane = lanes[targetLaneIndex]
        let sourceIndex = focusedRowIndex(for: focusedCollectionLane)
        focusedCollectionLane = targetLane
        setFocusedRowIndex(sourceIndex, for: targetLane)
    }

    private func moveCollectionsFocus(_ direction: MoveCommandDirection) {
        guard !isSearchFieldFocused else { return }
        normalizeCollectionsKeyboardFocus()
        guard !visibleKeyboardLanes.isEmpty else { return }

        if !isCollectionsKeyboardFocusActive {
            isCollectionsKeyboardFocusActive = true
            if !visibleKeyboardLanes.contains(focusedCollectionLane) {
                focusedCollectionLane = visibleKeyboardLanes.contains(.mostRead) ? .mostRead : visibleKeyboardLanes[0]
            }
            if direction == .up {
                setFocusedRowIndex(max(rowCount(for: focusedCollectionLane) - 1, 0), for: focusedCollectionLane)
            } else if direction == .left || direction == .right {
                shiftCollectionsFocusLane(direction)
            }
            return
        }

        switch direction {
        case .up:
            let nextIndex = max(focusedRowIndex(for: focusedCollectionLane) - 1, 0)
            setFocusedRowIndex(nextIndex, for: focusedCollectionLane)
        case .down:
            let maxIndex = max(rowCount(for: focusedCollectionLane) - 1, 0)
            let nextIndex = min(focusedRowIndex(for: focusedCollectionLane) + 1, maxIndex)
            setFocusedRowIndex(nextIndex, for: focusedCollectionLane)
        case .left, .right:
            shiftCollectionsFocusLane(direction)
        default:
            break
        }
    }

    private func openFocusedCollectionItem(inNewTab: Bool) {
        guard let result = focusedCollectionResult else { return }
        onOpen(result, inNewTab)
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
        DiscoverEditorialPanel(accent: .accentColor, tone: .atlas) {
            DiscoverPlaylistColumn(
                title: "Most Read",
                subtitle: playlistMostReadSubtitle,
                meta: mostReadCollectionMeta,
                systemImage: "chart.line.uptrend.xyaxis",
                tint: .accentColor,
                showsLoading: trendPulseStore.isLoading,
                isKeyboardFocused: isCollectionsKeyboardFocusActive && focusedCollectionLane == .mostRead,
                showsSurface: false
            ) {
                if playlistMostReadItems.isEmpty {
                    DiscoverPlaylistPlaceholder(
                        text: allTimeMostReadStore.isLoading
                            ? "Loading all-time most read…"
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
    }

    @ViewBuilder
    private var longestReadsCollectionModule: some View {
        DiscoverEditorialPanel(accent: Color.orange.opacity(0.9), tone: .notebook) {
            DiscoverPlaylistColumn(
                title: "Longest Reads",
                subtitle: playlistLongestSubtitle,
                meta: longestCollectionMeta,
                systemImage: "text.alignleft",
                tint: Color.orange.opacity(0.9),
                showsLoading: wordCountStore.isLoading,
                isKeyboardFocused: isCollectionsKeyboardFocusActive && focusedCollectionLane == .longest,
                showsSurface: false
            ) {
                if longestReadItems.isEmpty {
                    if longestFallbackItems.isEmpty {
                        DiscoverPlaylistPlaceholder(
                            text: wordCountStore.isLoading
                                ? "Finding long reads…"
                                : "No all-time long-read candidates are available yet."
                        )
                    } else {
                        ForEach(Array(longestFallbackItems.enumerated()), id: \.element.id) { index, result in
                            let rowKey = pageViewsRowKey(section: "collection-longest-fallback", result: result, index: index)
                            DiscoverPlaylistArticleRow(
                                result: result,
                                rank: index + 1,
                                primaryStat: wordCountStore.isLoading ? "Loading words…" : "Word count unavailable",
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
    }

    @ViewBuilder
    private var todayMostReadSection: some View {
        DiscoverEditorialPanel(accent: Color.blue.opacity(0.9), tone: .feature) {
            VStack(alignment: .leading, spacing: 12) {
                DiscoverSectionHeader(
                    title: "Today’s Most Read",
                    subtitle: "PLACEHOLDER"
                )
                DiscoverPlaylistColumn(
                    title: "Today",
                    subtitle: todayMostReadSubtitle,
                    meta: todayMostReadMeta,
                    systemImage: "sun.max.fill",
                    tint: Color.blue.opacity(0.9),
                    showsLoading: todayMostReadStore.isLoading || todayTrendPulseStore.isLoading,
                    isKeyboardFocused: false,
                    showsSurface: false
                ) {
                    if todayMostReadItems.isEmpty {
                        DiscoverPlaylistPlaceholder(
                            text: todayMostReadStore.isLoading
                                ? "Loading today’s most read…"
                                : "Today’s Most Read is unavailable right now."
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
        }
    }

    @ViewBuilder
    private var newsBriefingSection: some View {
        if !feed.newsStories.isEmpty {
            DiscoverEditorialPanel(accent: Color.teal.opacity(0.84), tone: .notebook) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(
                        title: "News Briefing",
                        subtitle: "PLACEHOLDER"
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
                subtitle: "PLACEHOLDER"
            )

            VStack(alignment: .leading, spacing: 16) {
                mostReadCollectionModule
                longestReadsCollectionModule
            }
        }
    }

    @ViewBuilder
    private var mediaSpotlightSection: some View {
        if let featuredImage = feed.featuredImage {
            VStack(alignment: .leading, spacing: 16) {
                DiscoverEditorialPanel(accent: Color.indigo.opacity(0.82), tone: .feature) {
                    VStack(alignment: .leading, spacing: 12) {
                        DiscoverSectionHeader(title: "Image of the Day", subtitle: "PLACEHOLDER")
                        DiscoverFeaturedImageCard(image: featuredImage)
                    }
                }
            }
        }

        if !remainingNewsItems.isEmpty {
            DiscoverEditorialPanel(accent: Color.red.opacity(0.78), tone: .notebook) {
                VStack(alignment: .leading, spacing: 12) {
                    DiscoverSectionHeader(title: "In the News", subtitle: "PLACEHOLDER")
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
                    DiscoverSectionHeader(title: "Time Capsule", subtitle: "PLACEHOLDER")
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
        if hasTimeMachineDetails {
            DiscoverEditorialPanel(
                accent: Color.indigo.opacity(0.84),
                tone: .timewarp,
                contentPadding: isCompactLayout ? 14 : 18
            ) {
                VStack(alignment: .leading, spacing: isCompactLayout ? 14 : 18) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        DiscoverSectionHeader(title: "Time Machine", subtitle: "PLACEHOLDER")

                        Spacer(minLength: 0)

                        if !feed.dateLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(feed.dateLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
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
    private var temporalExplorationStage: some View {
        VStack(alignment: .leading, spacing: 18) {
            timeCapsuleStage
            timeMachineStage
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
            if let featured = feed.featuredArticle {
                DiscoverMasthead(
                    dateLabel: feed.dateLabel,
                    isCompactLayout: isCompactLayout
                )
                let featuredRowKey = pageViewsRowKey(section: "featured", result: featured)
                DiscoverFeatureModule(
                    result: featured,
                    teaserText: featuredTeaserText,
                    isTeaserLoading: isFeaturedTeaserLoading,
                    visualContextImages: visualContextStore.images,
                    isVisualContextLoading: visualContextStore.isLoading && visualContextStore.images.isEmpty,
                    heroImageHeight: heroImageHeight,
                    titleLineLimit: leadStoryTitleLineLimit,
                    descriptionLineLimit: leadStoryDescriptionLineLimit,
                    isCompactLayout: isCompactLayout,
                    onOpen: onOpen,
                    onOpenURL: { url in
                        openURL(url)
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

            openingEditorialSpread

            collectionsStage

            mediaSpotlightSection

            temporalExplorationStage
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
                isCollectionsKeyboardFocusActive = false
            }
        }
        .onMoveCommand { direction in
            moveCollectionsFocus(direction)
        }
        .onExitCommand {
            isCollectionsKeyboardFocusActive = false
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
                results: playlistMostReadItems,
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today’s Edition")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(1.0)
                        .foregroundStyle(.tertiary)

                    Text("Discover")
                        .font(.system(size: isCompactLayout ? 31 : 38, weight: .semibold, design: .serif))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                if !trimmedDateLabel.isEmpty {
                    Text(trimmedDateLabel)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.045), in: Capsule())
                        .multilineTextAlignment(.trailing)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.top, 2)
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
        VStack(alignment: .leading, spacing: showsSubtitle ? 4 : 0) {
            if showsSubtitle {
                Text(normalizedSubtitle)
                    .font(DiscoverTypography.sectionSubtitle)
                    .textCase(.uppercase)
                    .tracking(0.75)
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(DiscoverTypography.sectionTitle)
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
        case .feature:
            return [accent.opacity(0.14), Color.primary.opacity(0.03), Color.white.opacity(0.16)]
        case .notebook:
            return [Color.primary.opacity(0.018), accent.opacity(0.055), Color.white.opacity(0.10)]
        case .atlas:
            return [accent.opacity(0.09), Color.primary.opacity(0.022), Color.white.opacity(0.12)]
        case .archive:
            return [accent.opacity(0.08), Color.orange.opacity(0.05), Color.white.opacity(0.14)]
        case .timewarp:
            return [accent.opacity(0.12), Color.primary.opacity(0.026), Color.white.opacity(0.16)]
        }
    }

    var topRuleHeight: CGFloat {
        switch self {
        case .feature: return 3
        case .timewarp: return 2.5
        case .notebook, .atlas, .archive: return 2
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .feature:
            return 26
        case .notebook, .atlas:
            return 22
        case .archive:
            return 20
        case .timewarp:
            return 24
        }
    }

    var borderOpacity: Double {
        switch self {
        case .feature:
            return 0.16
        case .notebook:
            return 0.12
        case .atlas:
            return 0.13
        case .archive:
            return 0.11
        case .timewarp:
            return 0.16
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .feature:
            return 0.08
        case .notebook:
            return 0.05
        case .atlas:
            return 0.055
        case .archive:
            return 0.04
        case .timewarp:
            return 0.07
        }
    }
}

struct DiscoverEditorialPanel<Content: View>: View {
    let accent: Color
    var tone: DiscoverEditorialPanelTone = .feature
    var contentPadding: CGFloat = 16
    let content: Content

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
            LinearGradient(
                colors: [accent.opacity(0.8), accent.opacity(0.18)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: tone.topRuleHeight)

            content
                .padding(contentPadding)
        }
        .background(
            LinearGradient(
                colors: tone.backgroundColors(accent: accent),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(accent.opacity(tone.borderOpacity), lineWidth: 0.9)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                .blendMode(.screen)
        }
        .shadow(color: accent.opacity(tone.shadowOpacity), radius: 18, y: 8)
    }
}

struct DiscoverInsetPanel<Content: View>: View {
    let accent: Color
    var contentPadding: CGFloat = 12
    let content: Content

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
        .background(
            LinearGradient(
                colors: [
                    accent.opacity(0.055),
                    Color.primary.opacity(0.018),
                    Color.white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(accent.opacity(0.1), lineWidth: 0.8)
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

struct DiscoverPlaylistColumn<Content: View>: View {
    let title: String
    let subtitle: String
    let meta: String?
    let systemImage: String
    let tint: Color
    let showsLoading: Bool
    let isKeyboardFocused: Bool
    let showsSurface: Bool
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    init(
        title: String,
        subtitle: String,
        meta: String? = nil,
        systemImage: String,
        tint: Color,
        showsLoading: Bool = false,
        isKeyboardFocused: Bool = false,
        showsSurface: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.systemImage = systemImage
        self.tint = tint
        self.showsLoading = showsLoading
        self.isKeyboardFocused = isKeyboardFocused
        self.showsSurface = showsSurface
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 19, height: 19)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let meta, !meta.isEmpty {
                        Text(meta)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                if showsLoading {
                    AppLoadingActivityMark(tone: .accent, tint: tint)
                        .padding(.top, 1)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                content
            }
        }
        .padding(12)
        .background(
            Group {
                if showsSurface {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(isHovered || isKeyboardFocused ? 0.045 : 0.025))
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: showsSurface ? 16 : 18, style: .continuous)
                .strokeBorder(
                    isKeyboardFocused
                        ? tint.opacity(0.48)
                        : Color.primary.opacity(isHovered ? (showsSurface ? 0.12 : 0.09) : (showsSurface ? 0.07 : 0.05)),
                    lineWidth: isKeyboardFocused ? 1.1 : 0.8
                )
        }
        .overlay {
            if showsSurface {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [tint.opacity(0.18), Color.primary.opacity(0.02)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            }
        }
        .scaleEffect(reduceMotion ? 1 : ((isHovered || isKeyboardFocused) ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isKeyboardFocused)
        .onHover { isHovered = $0 }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            onFocus?()
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("\(rank)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(2)
                    if let description = result.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1.5) {
                    Text(primaryStat)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(statTint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .monospacedDigit()

                    if let secondaryStat, !secondaryStat.isEmpty {
                        Text(secondaryStat)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isKeyboardFocused
                            ? statTint.opacity(0.16)
                            : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isKeyboardFocused
                            ? statTint.opacity(0.55)
                            : Color.primary.opacity(isHovered ? 0.14 : 0),
                        lineWidth: isKeyboardFocused ? 1.05 : 0.8
                    )
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .scaleEffect(reduceMotion ? 1 : ((isHovered || isKeyboardFocused) ? 1.005 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isKeyboardFocused)
        .accessibilityLabel(result.title)
        .accessibilityValue(secondaryStat.map { "\(primaryStat), \($0)" } ?? primaryStat)
        .accessibilityHint("Open article. Use arrows to move focus and Return to open.")
    }
}

enum DiscoverTypography {
    static let sectionTitle = Font.system(size: 21, weight: .semibold, design: .serif)
    static let sectionSubtitle = Font.system(size: 10.5, weight: .semibold, design: .rounded)
    static let featureTitle = Font.system(size: 31, weight: .semibold, design: .serif)
    static let featureDescription = Font.system(size: 13.5, weight: .regular)
    static let newsCardTitle = Font.system(size: 13.5, weight: .semibold, design: .rounded)
    static let newsRailTitle = Font.system(size: 14.5, weight: .semibold)
    static let newsCardDescription = Font.system(size: 11.5, weight: .regular)
    static let compactRank = Font.system(size: 14.5, weight: .semibold, design: .rounded)
    static let compactTitle = Font.system(size: 12.5, weight: .medium)
    static let compactDescription = Font.system(size: 11, weight: .regular)
    static let storyBody = Font.system(size: 14, weight: .regular, design: .serif)
    static let mediaTitle = Font.system(size: 16.5, weight: .semibold, design: .rounded)
    static let mediaDescription = Font.system(size: 12.5, weight: .regular)
    static let mediaMeta = Font.system(size: 11.5, weight: .medium)
}

struct DiscoverFeatureModule: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let visualContextImages: [WikipediaService.VisualContextImage]
    let isVisualContextLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let isCompactLayout: Bool
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DiscoverFeatureCard(
                result: result,
                teaserText: teaserText,
                isTeaserLoading: isTeaserLoading,
                heroImageHeight: heroImageHeight,
                titleLineLimit: titleLineLimit,
                descriptionLineLimit: descriptionLineLimit,
                onOpen: onOpen,
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
                    Text("PLACEHOLDER")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.9)
        }
    }
}

struct DiscoverFeatureCard: View {
    let result: WikipediaService.SearchResult
    let teaserText: String?
    let isTeaserLoading: Bool
    let heroImageHeight: CGFloat
    let titleLineLimit: Int
    let descriptionLineLimit: Int
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    var showsSurface: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

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
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                featureImage
                .frame(maxWidth: .infinity)
                .frame(height: heroImageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("PLACEHOLDER")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.9)
                        .foregroundStyle(.tertiary)

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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if showsSurface {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.13 : 0.07), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.1 : 0.04), lineWidth: 0.8)
            }
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.005 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var featureImage: some View {
        if let thumbnailURL = result.thumbnailURL {
            CachedThumbnailImage(
                url: thumbnailURL,
                targetSize: CGSize(width: 320, height: heroImageHeight),
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0.08), lineWidth: 0.8)
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.01 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
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
            DiscoverSparkline(points: pulse.points, tint: trendColor)
                .frame(width: 64, height: 16)

            Text(deltaText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(trendColor)
                .lineLimit(1)

            Text("\(latestViewsText) views")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .contentShape(Capsule())
        .highPriorityGesture(
            TapGesture().onEnded {
                onTap?()
            }
        )
        .help("Show views details")
    }
}
