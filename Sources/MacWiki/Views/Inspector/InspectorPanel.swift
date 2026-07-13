import SwiftUI
import SwiftData

/// Inspector panel with grouped, context-sensitive modes.
struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @AppStorage(AppStorageKey.Inspector.infoSplitRatio) private var infoSplitRatioSetting: Double = 0
    @AppStorage(AppStorageKey.Inspector.metadataSectionHeight) private var metadataSectionHeightSetting: Double = 0
    @AppStorage(AppStorageKey.Inspector.tocSectionHeight) private var tocSectionHeightSetting: Double = 0
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var currentArticleHighlights: [Highlight]

    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?
    @State private var rehydrateToast: HighlightRehydrateToast?
    @State private var currentArticleState: ArticleState?
    @State private var cachedCurrentArticleHighlights: [Highlight] = []
    @State private var cachedCurrentArticleTags: [Tag] = []
    @State private var liveMetadataSectionHeight: CGFloat?
    @State private var infoViewportHeight: CGFloat = 0
    @State private var infoTopContentHeight: CGFloat = 0

    init(
        showNewLabelSheet: Binding<Bool>,
        articleForNewLabel: Binding<SavedArticle?>,
        currentArticleTitle: String?
    ) {
        _showNewLabelSheet = showNewLabelSheet
        _articleForNewLabel = articleForNewLabel

        let scopedTitle = currentArticleTitle ?? ""
        _currentArticleHighlights = Query(
            filter: #Predicate<Highlight> { highlight in
                highlight.articleTitle == scopedTitle
            },
            sort: \Highlight.createdAt,
            order: .reverse
        )
    }

    private enum InspectorLayout {
        static let contentTopPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 14
        static let sectionCornerRadius: CGFloat = 12
        static let headerBarHeight: CGFloat = 50
        static let headerHorizontalPadding: CGFloat = 10
        static let tocHeightRange: ClosedRange<CGFloat> = 72...1200
        static let metadataHeightRange: ClosedRange<CGFloat> = 56...520
        static let resizeHandleTopPadding: CGFloat = 0
        static let splitResizeUpdateThreshold: CGFloat = 0.01
        static let infoSplitBudgetRatio: CGFloat = 0.58
        static let infoSplitBudgetRange: ClosedRange<CGFloat> = 128...1400
        static let infoSplitFallbackBudget: CGFloat = 420
        static let infoVerticalPadding: CGFloat = 26
        static let splitSectionChromeHeight: CGFloat = 96
        static let splitHandleHeight: CGFloat = 7
        static let metadataTransitionAnimation = Animation.easeOut(duration: 0.22)
        static let metadataHeightAnimation = Animation.easeOut(duration: 0.18)
    }

    private var usesSplitLayout: Bool {
        !appState.currentArticleMetadata.isEmpty
            && !appState.currentArticleTableOfContents.isEmpty
    }

    private var infoSplitBudget: CGFloat {
        if infoViewportHeight > 0, infoTopContentHeight > 0 {
            let sectionSpacingBudget = InspectorLayout.sectionSpacing * 3
            let remainingScrollableBudget = infoViewportHeight
                - infoTopContentHeight
                - InspectorLayout.infoVerticalPadding
                - InspectorLayout.splitSectionChromeHeight
                - InspectorLayout.splitHandleHeight
                - sectionSpacingBudget
            return InspectorSplitState.budget(
                viewportHeight: max(0, remainingScrollableBudget),
                budgetRatio: 1,
                budgetRange: InspectorLayout.infoSplitBudgetRange,
                fallbackBudget: InspectorLayout.infoSplitFallbackBudget
            )
        }

        return InspectorSplitState.budget(
            viewportHeight: infoViewportHeight,
            budgetRatio: InspectorLayout.infoSplitBudgetRatio,
            budgetRange: InspectorLayout.infoSplitBudgetRange,
            fallbackBudget: InspectorLayout.infoSplitFallbackBudget
        )
    }

    private var persistedMetadataSplitRatio: CGFloat? {
        InspectorSplitState.persistedMetadataSplitRatio(
            infoSplitRatioSetting: infoSplitRatioSetting,
            metadataSectionHeightSetting: metadataSectionHeightSetting,
            tocSectionHeightSetting: tocSectionHeightSetting,
            metadataRange: InspectorLayout.metadataHeightRange,
            tocRange: InspectorLayout.tocHeightRange
        )
    }

    private var resolvedSplitHeights: InspectorInfoSectionSplitSizer.Result {
        let splitHeights: InspectorInfoSectionSplitSizer.Result
        if let persistedMetadataSplitRatio {
            splitHeights = InspectorSplitState.resolveSplitHeights(
                budget: infoSplitBudget,
                effectiveRatio: persistedMetadataSplitRatio,
                metadataRange: InspectorLayout.metadataHeightRange,
                tocRange: InspectorLayout.tocHeightRange
            )
        } else {
            splitHeights = InspectorInfoSectionSplitSizer.calculate(
                metadataContentHeight: estimatedMetadataContentHeight,
                tocContentHeight: estimatedTableOfContentsContentHeight,
                viewportHeight: infoSplitBudget,
                metadataRange: InspectorLayout.metadataHeightRange,
                tocRange: InspectorLayout.tocHeightRange,
                budgetRange: InspectorLayout.infoSplitBudgetRange,
                budgetRatio: 1,
                fallbackBudget: infoSplitBudget
            )
        }

        return InspectorSplitState.expandTOCIntoAvailableSpace(
            splitHeights,
            budget: infoSplitBudget,
            metadataContentHeight: estimatedMetadataContentHeight,
            tocContentHeight: estimatedTableOfContentsContentHeight,
            metadataRange: InspectorLayout.metadataHeightRange,
            tocRange: InspectorLayout.tocHeightRange
        )
    }

    private var estimatedTableOfContentsContentHeight: CGFloat {
        let rows = CGFloat(appState.currentArticleTableOfContents.count)
        return rows * 28 + 12
    }

    private var estimatedTableOfContentsSectionHeight: CGFloat {
        clampTOCHeight(estimatedTableOfContentsContentHeight)
    }

    private var estimatedMetadataContentHeight: CGFloat {
        let rowCount = CGFloat(appState.currentArticleMetadata.count)
        guard rowCount > 0 else { return InspectorLayout.metadataHeightRange.lowerBound }
        return (rowCount * 44) + 24
    }

    private var estimatedMetadataSectionHeight: CGFloat {
        clampMetadataHeight(estimatedMetadataContentHeight)
    }

    private var tableOfContentsSectionHeight: CGFloat {
        if usesSplitLayout {
            return resolvedSplitHeights.tocHeight
        }
        if let stored = sanitizedPersistedHeight(
            tocSectionHeightSetting,
            range: InspectorLayout.tocHeightRange
        ) {
            return clampTOCHeight(stored)
        }
        return estimatedTableOfContentsSectionHeight
    }

    private var metadataSectionHeight: CGFloat {
        if let liveMetadataSectionHeight, liveMetadataSectionHeight.isFinite {
            return clampMetadataHeight(liveMetadataSectionHeight)
        }
        if usesSplitLayout {
            return resolvedSplitHeights.metadataHeight
        }
        if let stored = sanitizedPersistedHeight(
            metadataSectionHeightSetting,
            range: InspectorLayout.metadataHeightRange
        ) {
            return clampMetadataHeight(stored)
        }
        return estimatedMetadataSectionHeight
    }

    private var standardTOCTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .bottom))
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity
                .combined(with: .move(edge: .bottom))
                .combined(with: .scale(scale: 0.985, anchor: .top))
        )
    }

    private var metadataSectionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.992, anchor: .top))
    }

    private var metadataIdentityKey: String {
        appState.currentArticleMetadata.map { "\($0.label)=\($0.value)" }.joined(separator: "|")
    }

    private var derivedArticleDataRefreshKey: String {
        let title = appState.currentArticle?.title ?? ""
        let highlightFingerprint = currentArticleHighlights.reduce(into: Hasher()) { hasher, highlight in
            hasher.combine(highlight.id)
            hasher.combine(highlight.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(stableTagFingerprint(for: highlight.tags))
            hasher.combine(highlight.isArchivedRaw ?? false)
        }.finalize()
        let stateTagFingerprint = stableTagFingerprint(for: currentArticleState?.tags ?? [])
        return "\(title)|\(highlightFingerprint)|\(stateTagFingerprint)"
    }

    private var inspectorChromeHeight: CGFloat {
        InspectorLayout.headerBarHeight
    }

    private var sectionFillOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.30
    }

    private var sectionStrokeOpacity: Double {
        colorScheme == .dark ? 0.10 : 0.08
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsInspectorHeaderBar {
                inspectorHeaderBar
            }

            // Content area
            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, showsInspectorHeaderBar ? InspectorLayout.contentTopPadding : 0)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .overlay(alignment: .bottom) {
            if appState.isHighlightRehydrateInProgress {
                HighlightToastView(toast: HighlightRehydrateToast(message: "Rehydrating…", isSuccess: true), showsSpinner: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
            } else if let toast = rehydrateToast {
                HighlightToastView(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.isHighlightRehydrateInProgress)
        .animation(.easeOut(duration: 0.2), value: rehydrateToast)
        .onChange(of: appState.lastHighlightRehydrateResult) { _, newValue in
            guard let result = newValue else { return }
            let toast = HighlightRehydrateToast(
                message: result.success ? "Rehydrate succeeded" : "Rehydrate failed",
                isSuccess: result.success
            )
            withAnimation(.easeOut(duration: 0.2)) {
                rehydrateToast = toast
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeIn(duration: 0.2)) {
                    if rehydrateToast?.id == toast.id {
                        rehydrateToast = nil
                    }
                }
            }
        }
        .task(id: derivedArticleDataRefreshKey) {
            refreshCachedArticleDerivedData()
        }
        .onAppear {
            sanitizePersistedSplitSettingsIfNeeded()
        }
    }

    private var showsInspectorHeaderBar: Bool {
        true
    }
    
    private var inspectorHeaderBar: some View {
        ZStack {
            if appState.currentArticle != nil {
                inspectorModeSelector
                    .padding(.horizontal, InspectorLayout.headerHorizontalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: InspectorLayout.headerBarHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
        }
        .zIndex(1)
    }

    private var inspectorModeSelector: some View {
        Picker("Inspector mode", selection: inspectorModeSelection) {
            ForEach(inspectorModeOrder, id: \.self) { mode in
                Text(mode.rawValue)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Inspector mode")
    }

    private var inspectorModeOrder: [InspectorMode] {
        [.info, .notes, .references]
    }

    private var inspectorModeSelection: Binding<InspectorMode> {
        Binding(
            get: { appState.inspectorMode },
            set: { mode in
                appState.inspectorMode = mode
            }
        )
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch appState.inspectorMode {
        case .info:
            infoContent
        case .notes:
            notesContent
        case .references:
            referencesContent
        }
    }
    
    private var infoContent: some View {
        GeometryReader { proxy in
            Group {
                if let article = appState.currentArticle {
                    VStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
                        infoTopModules(article)

                        if !appState.currentArticleMetadata.isEmpty {
                            metadataSection
                                .transition(metadataSectionTransition)
                        }

                        if usesSplitLayout {
                            metadataTOCResizeHandle
                        }

                        if !appState.currentArticleTableOfContents.isEmpty {
                            tableOfContentsSection
                                .transition(standardTOCTransition)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                    .animation(reduceMotion ? nil : InspectorLayout.metadataTransitionAnimation, value: appState.currentArticleMetadata.isEmpty)
                } else {
                    ColumnEmptyStateView(
                        title: "No Article",
                        systemImage: "doc.text",
                        description: "Select an article to view info",
                        style: .quiet
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                updateInfoViewportHeight(proxy.size.height)
            }
            .onChange(of: proxy.size.height) { _, newHeight in
                updateInfoViewportHeight(newHeight)
            }
            .onPreferenceChange(InfoTopContentHeightPreferenceKey.self) { newHeight in
                updateInfoTopContentHeight(newHeight)
            }
        }
        .task(id: appState.currentArticle?.title) {
            await loadOrCreateArticleState()
        }
    }

    private func infoTopModules(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
            articleSummaryHeader(article)

            InspectorLabelSection(
                article: article,
                allLabels: allLabels
            )

            InspectorTagStatusBox(
                article: article,
                tags: cachedCurrentArticleTags,
                allTags: allTags,
                highlights: cachedCurrentArticleHighlights
            )
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: InfoTopContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    private var tableOfContentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Contents")
                    .font(MacWikiTypography.inspectorSectionLabel)
                    .foregroundStyle(.primary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(appState.currentArticleTableOfContents.enumerated()), id: \.offset) { index, item in
                            tableOfContentsRow(item: item, index: index)
                        }
                    }
                }
                .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, newId in
                    guard let newId else { return }
                    guard let targetIndex = appState.currentArticleTableOfContents.firstIndex(where: { $0.id == newId }) else {
                        return
                    }
                    withAnimation(.interactiveSpring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.08)) {
                        proxy.scrollTo(targetIndex, anchor: .center)
                    }
                }
            }
            .frame(height: tableOfContentsSectionHeight)
        }
        .padding(12)
        .background {
            inspectorSectionBackground()
        }
    }

    private func tableOfContentsRow(item: ArticleTableOfContentsItem, index: Int) -> some View {
        let isActive = appState.currentVisibleTableOfContentsSectionId == item.id
        let indent = CGFloat(max(item.level - 2, 0)) * 14

        return Button {
            appState.pendingTableOfContentsScrollTarget = item.id
            appState.currentVisibleTableOfContentsSectionId = item.id
        } label: {
            HStack(spacing: 6) {
                if item.level > 2 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(SidebarRowSelectionVisuals.tint)
                                : AnyShapeStyle(.tertiary)
                        )
                }

                Text(item.title)
                    .font(isActive ? MacWikiTypography.inspectorTOCItemActive : MacWikiTypography.inspectorTOCItem)
                    .foregroundStyle(
                        isActive
                            ? AnyShapeStyle(SidebarRowSelectionVisuals.tint)
                            : AnyShapeStyle(.secondary)
                    )
                    .contentTransition(.interpolate)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, indent)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(SidebarRowSelectionVisuals.tint.opacity(isActive ? 0.14 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(SidebarRowSelectionVisuals.tint.opacity(0.28), lineWidth: 0.8)
                    .opacity(isActive ? 1 : 0)
            )
            .scaleEffect(isActive ? 1.015 : 1, anchor: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.74, blendDuration: 0.06), value: isActive)
        .id(index)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(MacWikiTypography.inspectorSectionLabel)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            metadataScrollContent
                .frame(height: metadataSectionHeight, alignment: .top)
                .animation(reduceMotion ? nil : InspectorLayout.metadataHeightAnimation, value: metadataSectionHeight)
        }
        .padding(12)
        .background {
            inspectorSectionBackground()
        }
        .animation(reduceMotion ? nil : InspectorLayout.metadataHeightAnimation, value: metadataIdentityKey)
    }

    private var metadataTOCResizeHandle: some View {
        SectionResizeHandle(
            currentHeight: metadataSectionHeight,
            range: InspectorLayout.metadataHeightRange,
            onHeightChanged: { newHeight in
                updateMetadataResizeHeight(newHeight)
            },
            onDragEnded: { projectedHeight in
                endMetadataResize(at: projectedHeight)
            },
            onReset: {
                resetMetadataResizeHeight()
            }
        )
        .padding(.vertical, InspectorLayout.resizeHandleTopPadding)
    }

    private var metadataScrollContent: some View {
        ScrollView {
            MetadataView(items: appState.currentArticleMetadata)
        }
        // Handle links: Wikipedia = navigate in app, External = Safari
        .environment(\.openURL, OpenURLAction { url in
            // Check if it's a Wikipedia link
            if url.path.hasPrefix("/wiki/") {
                let articlePath = String(url.path.dropFirst(6))
                let title = articlePath.removingPercentEncoding ?? articlePath
                let displayTitle = title.replacingOccurrences(of: "_", with: " ")
                let linkedArticle = Article(id: displayTitle, title: displayTitle)
                appState.openArticle(linkedArticle, inNewTab: false)
                return .handled
            }
            // External links open in Safari
            openURL(url)
            return .handled
        })
    }

    @ViewBuilder
    private func articleSummaryHeader(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let thumbnailURL = article.thumbnailURL {
                CachedThumbnailImage(
                    url: thumbnailURL,
                    targetSize: CGSize(width: 220, height: 118)
                ) { image in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary.opacity(colorScheme == .dark ? 0.18 : 0.28))
                    }
                    .overlay {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                    }
                } placeholder: {
                    AppLoadingThumbnailPlaceholder(
                        width: 220,
                        height: 118,
                        cornerRadius: 10,
                        tone: .accent
                    )
                } failure: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary.opacity(colorScheme == .dark ? 0.18 : 0.28))

                        Image(systemName: "photo")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                if let description = article.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func inspectorSectionBackground() -> some View {
        RoundedRectangle(cornerRadius: InspectorLayout.sectionCornerRadius, style: .continuous)
            .fill(.quaternary.opacity(sectionFillOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: InspectorLayout.sectionCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(sectionStrokeOpacity), lineWidth: 0.8)
            }
    }

    private func clampTOCHeight(_ value: CGFloat) -> CGFloat {
        InspectorSplitState.clampedHeight(value, range: InspectorLayout.tocHeightRange)
    }

    private func clampMetadataHeight(_ value: CGFloat) -> CGFloat {
        InspectorSplitState.clampedHeight(value, range: InspectorLayout.metadataHeightRange)
    }

    private func updateInfoViewportHeight(_ newHeight: CGFloat) {
        guard newHeight.isFinite else { return }
        guard newHeight > 0 else { return }
        guard abs(infoViewportHeight - newHeight) >= 0.5 else { return }
        infoViewportHeight = newHeight
    }

    private func updateInfoTopContentHeight(_ newHeight: CGFloat) {
        guard newHeight.isFinite else { return }
        guard newHeight >= 0 else { return }
        guard abs(infoTopContentHeight - newHeight) >= 0.5 else { return }
        infoTopContentHeight = newHeight
    }

    private func updateMetadataResizeHeight(_ newHeight: CGFloat) {
        guard usesSplitLayout else { return }
        guard newHeight.isFinite else { return }
        let clamped = clampedMetadataSplitHeight(newHeight)
        let baseline = liveMetadataSectionHeight ?? metadataSectionHeight
        guard abs(clamped - baseline) >= InspectorLayout.splitResizeUpdateThreshold else { return }
        liveMetadataSectionHeight = clamped
    }

    private func endMetadataResize(at finalHeight: CGFloat) {
        guard usesSplitLayout else {
            liveMetadataSectionHeight = nil
            return
        }
        guard finalHeight.isFinite else {
            liveMetadataSectionHeight = nil
            return
        }
        let metadataHeight = clampedMetadataSplitHeight(finalHeight)
        let tocHeight = clampTOCHeight(infoSplitBudget - metadataHeight)
        metadataSectionHeightSetting = Double(metadataHeight)
        tocSectionHeightSetting = Double(tocHeight)
        infoSplitRatioSetting = Double(metadataHeight / max(infoSplitBudget, 1))
        liveMetadataSectionHeight = nil
    }

    private func resetMetadataResizeHeight() {
        liveMetadataSectionHeight = nil
        infoSplitRatioSetting = 0
        metadataSectionHeightSetting = 0
        tocSectionHeightSetting = 0
    }

    private func clampedMetadataSplitHeight(_ candidate: CGFloat) -> CGFloat {
        InspectorSplitState.clampedMetadataSplitHeight(
            candidate: candidate,
            budget: infoSplitBudget,
            metadataRange: InspectorLayout.metadataHeightRange,
            tocRange: InspectorLayout.tocHeightRange
        )
    }

    private func sanitizedPersistedHeight(
        _ storedValue: Double,
        range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        InspectorSplitState.sanitizedPersistedHeight(storedValue, range: range)
    }

    private func sanitizePersistedSplitSettingsIfNeeded() {
        let sanitized = InspectorSplitState.sanitizePersistedSettings(
            infoSplitRatioSetting: infoSplitRatioSetting,
            metadataSectionHeightSetting: metadataSectionHeightSetting,
            tocSectionHeightSetting: tocSectionHeightSetting
        )
        infoSplitRatioSetting = sanitized.ratio
        metadataSectionHeightSetting = sanitized.metadataHeight
        tocSectionHeightSetting = sanitized.tocHeight
    }

    private func refreshCachedArticleDerivedData() {
        guard appState.currentArticle != nil else {
            cachedCurrentArticleHighlights = []
            cachedCurrentArticleTags = []
            return
        }

        let matchingHighlights = currentArticleHighlights
        cachedCurrentArticleHighlights = matchingHighlights

        var seen = Set<UUID>()
        let articleTags = currentArticleState?.tags ?? []
        let highlightTags = matchingHighlights.flatMap { $0.tags }
        let mergedTags = (articleTags + highlightTags).filter { tag in
            if seen.contains(tag.id) { return false }
            seen.insert(tag.id)
            return true
        }
        cachedCurrentArticleTags = mergedTags.sorted { $0.sortOrder < $1.sortOrder }
    }
    
    @MainActor
    private func loadOrCreateArticleState() async {
        guard let article = appState.currentArticle else {
            currentArticleState = nil
            return
        }

        if let existing = fetchArticleState(for: article) {
            // Check cancellation before writing — article may have changed
            guard !Task.isCancelled, appState.currentArticle?.title == article.title else { return }
            currentArticleState = existing
            ReadStateSync.syncSavedArticles(title: article.title, isRead: existing.isRead, in: modelContext)
            appState.updateReadState(forTitle: article.title, isRead: existing.isRead)
            modelContext.saveReportingFailure(operation: #function)
            return
        }

        let resolvedReadState = ReadStateSync.resolveReadState(for: article, in: modelContext)

        // Check cancellation before inserting — a rapid tab switch could cause stale writes
        guard !Task.isCancelled, appState.currentArticle?.title == article.title else { return }

        let newState = ArticleState(
            articleTitle: article.title,
            articleURL: article.url,
            isRead: resolvedReadState
        )
        modelContext.insert(newState)
        modelContext.saveReportingFailure(operation: #function)
        currentArticleState = newState
        appState.updateReadState(forTitle: article.title, isRead: resolvedReadState)
    }

    private func fetchArticleState(for article: Article) -> ArticleState? {
        let urlString = article.url.absoluteString
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate { $0.articleURLString == urlString }
        )
        return try? modelContext.fetch(descriptor).first
    }

    @ViewBuilder
    private var notesContent: some View {
        if cachedCurrentArticleHighlights.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "highlighter")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)

                Text("No Highlights Yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Select text in the article to create highlights. Use ⌘H for quick highlighting.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 60)
        } else {
            HighlightListView(highlights: cachedCurrentArticleHighlights)
        }
    }

    @ViewBuilder
    private var referencesContent: some View {
        if appState.currentArticleReferences.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)

                Text("No References Found")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("Citations and sources from the article will appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 60)
        } else {
            ReferenceListView(sections: appState.currentArticleReferences)
        }
    }
}

private struct SectionResizeHandle: View {
    let currentHeight: CGFloat
    let range: ClosedRange<CGFloat>
    let onHeightChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var dragStartHeight: CGFloat?
    @State private var isHovering = false

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(isHovering ? 0.26 : 0.14))
            .frame(width: isHovering ? 22 : 18, height: isHovering ? 2.3 : 1.9)
        .frame(maxWidth: .infinity)
        .frame(height: 7)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resize metadata and contents sections")
        .accessibilityValue("\(Int(currentHeight.rounded())) pixels")
        .accessibilityHint("Drag up or down to resize. Double click to reset.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustHeight(by: 24)
            case .decrement:
                adjustHeight(by: -24)
            default:
                break
            }
        }
        .accessibilityAction(named: "Reset", onReset)
        .highPriorityGesture(
            // Use a global coordinate space so translation remains stable while
            // the splitter itself moves during live resize.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartHeight == nil {
                        dragStartHeight = currentHeight.isFinite ? currentHeight : range.lowerBound
                    }
                    let baseHeight = (dragStartHeight ?? currentHeight).isFinite
                        ? (dragStartHeight ?? currentHeight)
                        : range.lowerBound
                    guard value.translation.height.isFinite else { return }
                    let candidate = baseHeight + value.translation.height
                    let clamped = min(max(candidate, range.lowerBound), range.upperBound)
                    onHeightChanged(clamped)
                }
                .onEnded { value in
                    let baseHeight = (dragStartHeight ?? currentHeight).isFinite
                        ? (dragStartHeight ?? currentHeight)
                        : range.lowerBound
                    guard value.translation.height.isFinite else {
                        onDragEnded(baseHeight)
                        dragStartHeight = nil
                        return
                    }
                    let candidate = baseHeight + value.translation.height
                    let clamped = min(max(candidate, range.lowerBound), range.upperBound)
                    onDragEnded(clamped)
                    dragStartHeight = nil
                }
        )
        .onTapGesture(count: 2) {
            onReset()
        }
    }

    private func adjustHeight(by delta: CGFloat) {
        let baseHeight = currentHeight.isFinite ? currentHeight : range.lowerBound
        let clamped = min(max(baseHeight + delta, range.lowerBound), range.upperBound)
        onHeightChanged(clamped)
        onDragEnded(clamped)
    }
}

private struct InfoTopContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct HighlightRehydrateToast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isSuccess: Bool
}

private struct HighlightToastView: View {
    let toast: HighlightRehydrateToast
    var showsSpinner: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            if showsSpinner {
                AppLoadingActivityMark(tone: .accent)
            } else {
                Image(systemName: toast.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(toast.message)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08))
        )
        .foregroundStyle(toast.isSuccess ? .green : .orange)
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 8, y: 4)
    }
}
