import SwiftUI
import SwiftData

private enum InspectorModePillStyle {
    static func foregroundPrimaryOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.76 : 0.70
    }

    static func foregroundSelectedOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.84 : 0.78
    }

    static func foregroundHoverOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.78 : 0.72
    }

    static func activeFillOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.055 : 0.035
    }

    static func activeStrokeOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.10 : 0.075
    }

    static func hoverFillOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.05 : 0.035
    }

    static func hoverStrokeOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.10 : 0.075
    }
}

/// Inspector panel with grouped, context-sensitive modes.
struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("tabBarLiquidGlass") private var tabBarLiquidGlass = true
    @AppStorage("inspectorTOCPresentation") private var tocPresentation: InspectorTableOfContentsPresentation = .standard
    @AppStorage("inspectorInfoSplitRatio") private var infoSplitRatioSetting: Double = 0
    @AppStorage("inspectorMetadataSectionHeight") private var metadataSectionHeightSetting: Double = 0
    @AppStorage("inspectorTOCSectionHeight") private var tocSectionHeightSetting: Double = 0
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
        static let contentTopPadding: CGFloat = 10
        static let sectionSpacing: CGFloat = 14
        static let sectionCornerRadius: CGFloat = 12
        static let headerBarHeight: CGFloat = 60
        static let headerHorizontalPadding: CGFloat = 14
        static let headerTopPadding: CGFloat = 6
        static let headerBottomPadding: CGFloat = 8
        static let headerRowSpacing: CGFloat = 6
        static let modeSelectorLabelPointSize: CGFloat = 11.5
        static let tocHeightRange: ClosedRange<CGFloat> = 72...560
        static let metadataHeightRange: ClosedRange<CGFloat> = 56...520
        static let resizeHandleTopPadding: CGFloat = 0
        static let splitResizeUpdateThreshold: CGFloat = 0.01
        static let defaultInfoSplitRatio: CGFloat = 0.5
        static let infoSplitBudgetRatio: CGFloat = 0.58
        static let infoSplitBudgetRange: ClosedRange<CGFloat> = 280...620
        static let infoSplitFallbackBudget: CGFloat = 420
        static let floatingTOCMetadataBottomInset: CGFloat = 72
    }

    private var usesSplitLayout: Bool {
        tocPresentation == .standard
            && !appState.currentArticleMetadata.isEmpty
            && !appState.currentArticleTableOfContents.isEmpty
    }

    private var infoSplitBudget: CGFloat {
        let proposedBudget: CGFloat
        if infoViewportHeight.isFinite, infoViewportHeight > 0 {
            proposedBudget = infoViewportHeight * max(InspectorLayout.infoSplitBudgetRatio, 0)
        } else {
            proposedBudget = InspectorLayout.infoSplitFallbackBudget
        }
        return min(
            max(proposedBudget, InspectorLayout.infoSplitBudgetRange.lowerBound),
            InspectorLayout.infoSplitBudgetRange.upperBound
        )
    }

    private var persistedMetadataSplitRatio: CGFloat? {
        if infoSplitRatioSetting.isFinite,
           infoSplitRatioSetting > 0,
           infoSplitRatioSetting < 1 {
            return CGFloat(infoSplitRatioSetting)
        }

        if let storedMetadata = sanitizedPersistedHeight(
            metadataSectionHeightSetting,
            range: InspectorLayout.metadataHeightRange
        ),
           let storedTOC = sanitizedPersistedHeight(
            tocSectionHeightSetting,
            range: InspectorLayout.tocHeightRange
           ) {
            let combined = storedMetadata + storedTOC
            guard combined > 0 else { return nil }
            return storedMetadata / combined
        }

        return nil
    }

    private var effectiveMetadataSplitRatio: CGFloat {
        persistedMetadataSplitRatio ?? InspectorLayout.defaultInfoSplitRatio
    }

    private var resolvedSplitHeights: InspectorInfoSectionSplitSizer.Result {
        let budget = infoSplitBudget
        guard budget.isFinite, budget > 0 else {
            return InspectorInfoSectionSplitSizer.Result(
                metadataHeight: InspectorLayout.metadataHeightRange.lowerBound,
                tocHeight: InspectorLayout.tocHeightRange.lowerBound
            )
        }

        let metadataMinRatio = InspectorLayout.metadataHeightRange.lowerBound / budget
        let metadataMaxRatio = 1 - (InspectorLayout.tocHeightRange.lowerBound / budget)
        let ratio = min(max(effectiveMetadataSplitRatio, metadataMinRatio), metadataMaxRatio)

        var metadataHeight = clampMetadataHeight(budget * ratio)
        var tocHeight = clampTOCHeight(budget - metadataHeight)

        var overflow = (metadataHeight + tocHeight) - budget
        if overflow > 0.001 {
            let metadataSlack = metadataHeight - InspectorLayout.metadataHeightRange.lowerBound
            let tocSlack = tocHeight - InspectorLayout.tocHeightRange.lowerBound
            if metadataSlack >= tocSlack, metadataSlack > 0 {
                let reduction = min(overflow, metadataSlack)
                metadataHeight -= reduction
                overflow -= reduction
            }
            if overflow > 0.001, tocSlack > 0 {
                let reduction = min(overflow, tocSlack)
                tocHeight -= reduction
                overflow -= reduction
            }
        }

        let remaining = budget - (metadataHeight + tocHeight)
        if remaining > 0.001 {
            let tocHeadroom = max(0, InspectorLayout.tocHeightRange.upperBound - tocHeight)
            let tocIncrease = min(remaining, tocHeadroom)
            tocHeight += tocIncrease

            let metadataHeadroom = max(0, InspectorLayout.metadataHeightRange.upperBound - metadataHeight)
            let metadataIncrease = min(remaining - tocIncrease, metadataHeadroom)
            metadataHeight += metadataIncrease
        }

        return InspectorInfoSectionSplitSizer.Result(
            metadataHeight: clampMetadataHeight(metadataHeight),
            tocHeight: clampTOCHeight(tocHeight)
        )
    }

    private var estimatedTableOfContentsSectionHeight: CGFloat {
        let rows = CGFloat(appState.currentArticleTableOfContents.count)
        let estimate = rows * 28 + 12
        return clampTOCHeight(estimate)
    }

    private var estimatedMetadataSectionHeight: CGFloat {
        let rowCount = CGFloat(appState.currentArticleMetadata.count)
        guard rowCount > 0 else { return InspectorLayout.metadataHeightRange.lowerBound }
        let estimate = (rowCount * 44) + 24
        return clampMetadataHeight(estimate)
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

    private var metadataSectionMaxHeight: CGFloat {
        tocPresentation == .liquidDock ? .infinity : metadataSectionHeight
    }

    private var metadataScrollBottomInset: CGFloat {
        guard tocPresentation == .liquidDock,
              appState.inspectorMode == .info,
              appState.currentArticle != nil,
              !appState.currentArticleTableOfContents.isEmpty else {
            return 0
        }
        return InspectorLayout.floatingTOCMetadataBottomInset
    }

    private var tocPresentationAnimation: Animation {
        .interactiveSpring(response: 0.32, dampingFraction: 0.89, blendDuration: 0.08)
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

    private var floatingTOCTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .bottom))
                .combined(with: .scale(scale: 0.97, anchor: .bottom)),
            removal: .opacity
                .combined(with: .move(edge: .bottom))
                .combined(with: .scale(scale: 0.97, anchor: .bottom))
        )
    }

    private var animatedTOCPresentationBinding: Binding<InspectorTableOfContentsPresentation> {
        Binding(
            get: { tocPresentation },
            set: { newValue in
                setTOCPresentation(newValue)
            }
        )
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

    /// Height for the top spacer that pushes the tab bar below the toolbar area.
    private var inspectorTopBarHeight: CGFloat {
        max(appState.windowTopObscuredHeight, ColumnChromeMetrics.topBarHeight)
    }

    private var inspectorTopSpacerHeight: CGFloat {
        max(0, inspectorTopBarHeight - ColumnChromeMetrics.topBarHeight)
    }

    private var inspectorChromeHeight: CGFloat {
        inspectorTopSpacerHeight + InspectorLayout.headerBarHeight
    }

    private var sectionFillOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.30
    }

    private var sectionStrokeOpacity: Double {
        colorScheme == .dark ? 0.10 : 0.08
    }

    var body: some View {
        VStack(spacing: 0) {
            // Spacer fills the toolbar/titlebar region
            if inspectorTopSpacerHeight > 0 {
                WindowDragHandle(minLength: 80)
                    .frame(height: inspectorTopSpacerHeight)
            }

            inspectorHeaderBar

            // Content area
            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, InspectorLayout.contentTopPadding)
        }
        .background(alignment: .top) {
            ColumnChromeBackground()
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                        .frame(height: 0.5)
                }
                .frame(height: inspectorChromeHeight)
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
    
    private var inspectorHeaderBar: some View {
        ZStack {
            WindowDragHandle(minLength: 80)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: InspectorLayout.headerRowSpacing) {
                inspectorHeaderIdentity

                HStack(spacing: 0) {
                    inspectorModeSelector
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, InspectorLayout.headerHorizontalPadding)
            .padding(.top, InspectorLayout.headerTopPadding)
            .padding(.bottom, InspectorLayout.headerBottomPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: InspectorLayout.headerBarHeight)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.90), value: appState.inspectorMode)
        .zIndex(1)
    }

    private var inspectorHeaderIdentity: some View {
        let title = appState.currentArticle?.title ?? appState.inspectorMode.rawValue

        return Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var inspectorModeSelector: some View {
        InspectorModeControl(
            selectedMode: inspectorModeSelection,
            modes: inspectorModeOrder,
            labelPointSize: InspectorLayout.modeSelectorLabelPointSize,
            useLiquidGlass: tabBarLiquidGlass
        )
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
                            articleSummaryHeader(article)

                            InspectorLabelSection(
                                article: article,
                                allLabels: allLabels
                            )

                            InspectorTagStatusBox(article: article, tags: cachedCurrentArticleTags, allTags: allTags)

                            if !appState.currentArticleMetadata.isEmpty {
                                metadataSection
                            }

                            if tocPresentation == .standard, !appState.currentArticleTableOfContents.isEmpty {
                                tableOfContentsSection
                                    .transition(standardTOCTransition)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 18)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: proxy.size.height,
                            alignment: .topLeading
                        )
                        .animation(.easeInOut(duration: 0.25), value: appState.currentArticleMetadata.isEmpty)
                    }
                    .scrollIndicators(.hidden)
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
        }
        .task(id: appState.currentArticle?.title) {
            await loadOrCreateArticleState()
        }
        .overlay(alignment: .bottom) {
            if tocPresentation == .liquidDock,
               appState.inspectorMode == .info,
               appState.currentArticle != nil,
               !appState.currentArticleTableOfContents.isEmpty {
                InspectorTableOfContentsDockView(
                    items: appState.currentArticleTableOfContents,
                    presentation: animatedTOCPresentationBinding
                )
                .padding(.horizontal, 16)
                .transition(floatingTOCTransition)
                .zIndex(2)
            }
        }
        .animation(tocPresentationAnimation, value: tocPresentation)
    }

    private var tableOfContentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Contents")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    setTOCPresentation(.liquidDock)
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.14), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(appState.currentArticleTableOfContents.enumerated()), id: \.offset) { index, item in
                            let isActive = appState.currentVisibleTableOfContentsSectionId == item.id
                            let indent = CGFloat(max(item.level - 2, 0)) * 14
                            Button {
                                appState.pendingTableOfContentsScrollTarget = item.id
                                appState.currentVisibleTableOfContentsSectionId = item.id
                            } label: {
                                HStack(spacing: 6) {
                                    if item.level > 2 {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }

                                    Text(item.title)
                                        .font(.caption)
                                        .fontWeight(isActive ? .medium : .regular)
                                        .foregroundStyle(isActive ? .primary : .secondary)
                                        .contentTransition(.interpolate)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, indent)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.accentColor.opacity(isActive ? 0.14 : 0))
                                )
                                .overlay(
                                    // Use modifier with opacity instead of conditional – maintains view identity
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.8)
                                        .opacity(isActive ? 1 : 0)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(.interactiveSpring(response: 0.15, dampingFraction: 0.8), value: isActive)
                            .id(index)
                        }
                    }
                }
                .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, newId in
                    guard let newId else { return }
                    guard let targetIndex = appState.currentArticleTableOfContents.firstIndex(where: { $0.id == newId }) else {
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.2)) {
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

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if tocPresentation == .standard {
                    metadataScrollContent
                        .frame(height: metadataSectionHeight, alignment: .top)
                } else {
                    metadataScrollContent
                        .frame(maxHeight: metadataSectionMaxHeight, alignment: .top)
                }
            }

            if usesSplitLayout {
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
                .padding(.top, InspectorLayout.resizeHandleTopPadding)
            }
        }
        .padding(12)
        .background {
            inspectorSectionBackground()
        }
    }

    private var metadataScrollContent: some View {
        ScrollView {
            MetadataView(items: appState.currentArticleMetadata)
                .padding(.bottom, metadataScrollBottomInset)
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

    private func setTOCPresentation(_ newValue: InspectorTableOfContentsPresentation) {
        guard tocPresentation != newValue else { return }
        withAnimation(tocPresentationAnimation) {
            tocPresentation = newValue
        }
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
        guard value.isFinite else {
            return InspectorLayout.tocHeightRange.lowerBound
        }
        return min(max(value, InspectorLayout.tocHeightRange.lowerBound), InspectorLayout.tocHeightRange.upperBound)
    }

    private func clampMetadataHeight(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return InspectorLayout.metadataHeightRange.lowerBound
        }
        return min(max(value, InspectorLayout.metadataHeightRange.lowerBound), InspectorLayout.metadataHeightRange.upperBound)
    }

    private func updateInfoViewportHeight(_ newHeight: CGFloat) {
        guard newHeight.isFinite else { return }
        guard newHeight > 0 else { return }
        guard abs(infoViewportHeight - newHeight) >= 0.5 else { return }
        infoViewportHeight = newHeight
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
        let budget = infoSplitBudget
        let minimumMetadata = InspectorLayout.metadataHeightRange.lowerBound
        let maximumMetadata = min(
            InspectorLayout.metadataHeightRange.upperBound,
            budget - InspectorLayout.tocHeightRange.lowerBound
        )
        guard maximumMetadata >= minimumMetadata else {
            return minimumMetadata
        }
        return min(max(candidate, minimumMetadata), maximumMetadata)
    }

    private func sanitizedPersistedHeight(
        _ storedValue: Double,
        range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        guard storedValue.isFinite, storedValue > 0 else {
            return nil
        }
        let value = CGFloat(storedValue)
        guard value.isFinite else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func sanitizePersistedSplitSettingsIfNeeded() {
        if !infoSplitRatioSetting.isFinite || infoSplitRatioSetting < 0 || infoSplitRatioSetting > 1 {
            infoSplitRatioSetting = 0
        }
        if !metadataSectionHeightSetting.isFinite || metadataSectionHeightSetting < 0 {
            metadataSectionHeightSetting = 0
        }
        if !tocSectionHeightSetting.isFinite || tocSectionHeightSetting < 0 {
            tocSectionHeightSetting = 0
        }
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
            try? modelContext.save()
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
        try? modelContext.save()
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

private struct InspectorModeControl: View {
    @Binding var selectedMode: InspectorMode
    let modes: [InspectorMode]
    let labelPointSize: CGFloat
    let useLiquidGlass: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredMode: InspectorMode?
    @Namespace private var activeModeNamespace

    private enum Metrics {
        static let minimumSegmentWidth: CGFloat = 50
        static let segmentHorizontalPadding: CGFloat = 10
        static let segmentVerticalPadding: CGFloat = 5
        static let pillSpacing: CGFloat = 3
        static let pillCornerRadius: CGFloat = 10
        static let railHorizontalPadding: CGFloat = 3
        static let railVerticalPadding: CGFloat = 2
        static let railHeight: CGFloat = 32
    }

    var body: some View {
        let darkMode = colorScheme == .dark

        HStack(spacing: Metrics.pillSpacing) {
            ForEach(modes, id: \.self) { mode in
                let isActive = selectedMode == mode
                let isHovered = hoveredMode == mode && !isActive

                Button {
                    if reduceMotion {
                        selectedMode = mode
                    } else {
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.90, blendDuration: 0.08)) {
                            selectedMode = mode
                        }
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: labelPointSize, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(foregroundColor(isActive: isActive, isHovered: isHovered, darkMode: darkMode))
                        .lineLimit(1)
                        .frame(minWidth: Metrics.minimumSegmentWidth)
                        .padding(.horizontal, Metrics.segmentHorizontalPadding)
                        .padding(.vertical, Metrics.segmentVerticalPadding)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if isActive {
                        activePillBackground(darkMode: darkMode)
                            .matchedGeometryEffect(id: "inspector-mode-active-pill", in: activeModeNamespace)
                    } else if isHovered {
                        hoverPillBackground(darkMode: darkMode)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous))
                .onHover { hovering in
                    if hovering {
                        hoveredMode = mode
                    } else if hoveredMode == mode {
                        hoveredMode = nil
                    }
                }
                .help(mode.rawValue)
                .accessibilityLabel(mode.rawValue)
            }
        }
        .padding(.horizontal, Metrics.railHorizontalPadding)
        .padding(.vertical, Metrics.railVerticalPadding)
        .frame(height: Metrics.railHeight)
        .background {
            railBackground(darkMode: darkMode)
        }
    }

    private func foregroundColor(isActive: Bool, isHovered: Bool, darkMode: Bool) -> Color {
        if isActive {
            return Color.primary.opacity(InspectorModePillStyle.foregroundSelectedOpacity(darkMode: darkMode))
        }
        if isHovered {
            return Color.primary.opacity(InspectorModePillStyle.foregroundHoverOpacity(darkMode: darkMode))
        }
        return Color.primary.opacity(InspectorModePillStyle.foregroundPrimaryOpacity(darkMode: darkMode))
    }

    @ViewBuilder
    private func railBackground(darkMode: Bool) -> some View {
        if useLiquidGlass {
            RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                        .fill(
                            Color(nsColor: .controlBackgroundColor)
                                .opacity(darkMode ? 0.20 : 0.12)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(
                                TopChromeControlSurface.borderOpacity(
                                    darkMode: darkMode,
                                    liquid: useLiquidGlass,
                                    compactAccessory: true
                                )
                            ),
                            lineWidth: 0.50
                        )
                }
        } else {
            RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.68 : 0.82))
        }
    }

    @ViewBuilder
    private func activePillBackground(darkMode: Bool) -> some View {
        if useLiquidGlass {
            RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(InspectorModePillStyle.activeFillOpacity(darkMode: darkMode)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.accentColor.opacity(InspectorModePillStyle.activeStrokeOpacity(darkMode: darkMode)),
                            lineWidth: 0.58
                        )
                }
        } else {
            RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(InspectorModePillStyle.activeFillOpacity(darkMode: darkMode)))
        }
    }

    private func hoverPillBackground(darkMode: Bool) -> some View {
        RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
            .fill(Color.primary.opacity(InspectorModePillStyle.hoverFillOpacity(darkMode: darkMode)))
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.pillCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(InspectorModePillStyle.hoverStrokeOpacity(darkMode: darkMode)),
                        lineWidth: 0.56
                    )
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
        .accessibilityHint("Drag up or down to resize. Double click to reset.")
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
