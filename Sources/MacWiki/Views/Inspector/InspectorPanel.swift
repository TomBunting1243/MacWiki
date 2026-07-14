import SwiftUI
import SwiftData

/// Inspector panel with grouped, context-sensitive modes.
struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var currentArticleHighlights: [Highlight]

    @State private var rehydrateToast: HighlightRehydrateToast?
    @State private var currentArticleState: ArticleState?
    @State private var cachedCurrentArticleHighlights: [Highlight] = []
    @State private var cachedCurrentArticleTags: [Tag] = []
    @State private var showStaleHighlights = true
    @State private var showArchivedHighlights = false
    @State private var selectedReferenceIDs: Set<String> = []

    init(
        currentArticleTitle: String?
    ) {
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
        static let metadataTransitionAnimation = Animation.easeOut(duration: 0.22)
    }

    private var standardTOCTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
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

    private var toastTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.98))
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

    private var sectionFillOpacity: Double {
        colorScheme == .dark ? 0.22 : 0.30
    }

    private var sectionStrokeOpacity: Double {
        colorScheme == .dark ? 0.10 : 0.08
    }

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            InspectorHeaderBar(selection: $appState.inspectorMode)

            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, InspectorLayout.contentTopPadding)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .overlay(alignment: .bottom) {
            if appState.isHighlightRehydrateInProgress {
                HighlightToastView(toast: HighlightRehydrateToast(message: "Rehydrating…", isSuccess: true), showsSpinner: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(toastTransition)
            } else if let toast = rehydrateToast {
                HighlightToastView(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(toastTransition)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: appState.isHighlightRehydrateInProgress)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: rehydrateToast)
        .onChange(of: appState.lastHighlightRehydrateResult) { _, newValue in
            guard let result = newValue else { return }
            let toast = HighlightRehydrateToast(
                message: result.success ? "Rehydrate succeeded" : "Rehydrate failed",
                isSuccess: result.success
            )
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                rehydrateToast = toast
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
                    if rehydrateToast?.id == toast.id {
                        rehydrateToast = nil
                    }
                }
            }
        }
        .task(id: derivedArticleDataRefreshKey) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            refreshCachedArticleDerivedData()
        }
        .task(id: appState.currentArticle?.title) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            await loadOrCreateArticleState()
        }
        .onChange(of: appState.currentArticle?.id) {
            selectedReferenceIDs.removeAll()
        }
    }

    @ViewBuilder
    private var inspectorContent: some View {
        switch appState.inspectorMode {
        case .info:
            infoContent
        case .notes:
            InspectorNotesModeView(
                highlights: cachedCurrentArticleHighlights,
                showStaleHighlights: $showStaleHighlights,
                showArchivedHighlights: $showArchivedHighlights
            )
        case .references:
            InspectorReferencesModeView(
                sections: appState.currentArticleReferences,
                selectedReferenceIDs: $selectedReferenceIDs
            )
        }
    }
    
    private var infoContent: some View {
        Group {
            if let article = appState.currentArticle {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
                            infoTopModules(article)

                            if !appState.currentArticleMetadata.isEmpty {
                                metadataSection
                                    .transition(metadataSectionTransition)
                            }

                            if !appState.currentArticleTableOfContents.isEmpty {
                                tableOfContentsSection
                                    .transition(standardTOCTransition)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 14)
                    }
                    .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, newID in
                        guard let newID else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    }

    private var tableOfContentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Contents")
                    .font(MacWikiTypography.inspectorSectionLabel)
                    .foregroundStyle(.primary)
            }

            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(appState.currentArticleTableOfContents, id: \.id) { item in
                    tableOfContentsRow(item: item)
                }
            }
        }
        .padding(12)
        .background {
            inspectorSectionBackground()
        }
    }

    private func tableOfContentsRow(item: ArticleTableOfContentsItem) -> some View {
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
            .scaleEffect(reduceMotion ? 1 : (isActive ? 1.015 : 1), anchor: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(
            reduceMotion
                ? nil
                : .interactiveSpring(
                    response: 0.22,
                    dampingFraction: 0.74,
                    blendDuration: 0.06
                ),
            value: isActive
        )
        .id(item.id)
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(MacWikiTypography.inspectorSectionLabel)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            metadataContent
        }
        .padding(12)
        .background {
            inspectorSectionBackground()
        }
    }

    private var metadataContent: some View {
        MetadataView(items: appState.currentArticleMetadata)
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

    private func refreshCachedArticleDerivedData() {
        guard appState.currentArticle != nil else {
            if !cachedCurrentArticleHighlights.isEmpty {
                cachedCurrentArticleHighlights = []
            }
            if !cachedCurrentArticleTags.isEmpty {
                cachedCurrentArticleTags = []
            }
            return
        }

        let matchingHighlights = currentArticleHighlights
        if cachedCurrentArticleHighlights.map(\.id) != matchingHighlights.map(\.id) {
            cachedCurrentArticleHighlights = matchingHighlights
        }

        var seen = Set<UUID>()
        let articleTags = currentArticleState?.tags ?? []
        let highlightTags = matchingHighlights.flatMap { $0.tags }
        let mergedTags = (articleTags + highlightTags).filter { tag in
            if seen.contains(tag.id) { return false }
            seen.insert(tag.id)
            return true
        }
        let sortedTags = mergedTags.sorted { $0.sortOrder < $1.sortOrder }
        if cachedCurrentArticleTags.map(\.id) != sortedTags.map(\.id) {
            cachedCurrentArticleTags = sortedTags
        }
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
            if currentArticleState?.id != existing.id {
                currentArticleState = existing
            }
            let didChangeSavedArticles = ReadStateSync.syncSavedArticles(
                title: article.title,
                isRead: existing.isRead,
                in: modelContext
            )
            appState.updateReadState(forTitle: article.title, isRead: existing.isRead)
            if didChangeSavedArticles {
                modelContext.saveReportingFailure(operation: #function)
            }
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

}
