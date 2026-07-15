import SwiftUI
import SwiftData

/// Inspector panel with grouped, context-sensitive modes.
struct InspectorPanel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var currentArticleHighlights: [Highlight]
    @Query private var currentArticleStates: [ArticleState]

    @State private var rehydrateToast: HighlightRehydrateToast?
    @State private var articleSnapshot = InspectorArticleSnapshot.empty
    @State private var showStaleHighlights = true
    @State private var showArchivedHighlights = false
    @State private var selectedReferenceIDs: Set<String> = []

    init(
        currentArticle: Article?
    ) {
        let scopedTitle = currentArticle?.title ?? ""
        let scopedURLString = currentArticle?.url.absoluteString ?? ""
        _currentArticleHighlights = Query(
            filter: #Predicate<Highlight> { highlight in
                highlight.articleTitle == scopedTitle
            },
            sort: \Highlight.createdAt,
            order: .reverse
        )
        _currentArticleStates = Query(
            filter: #Predicate<ArticleState> { state in
                state.articleURLString == scopedURLString
            }
        )
    }

    private enum InspectorLayout {
        static let contentTopPadding: CGFloat = 8
        static let sectionSpacing: CGFloat = 14
        static let sectionCornerRadius: CGFloat = 12
        static let metadataTransitionAnimation = Animation.easeOut(duration: 0.22)
        static let detailsMinimumHeight: CGFloat = 220
        static let contentsMinimumHeight: CGFloat = 150
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

    private var currentArticleKey: InspectorArticleKey? {
        appState.currentArticle.map(InspectorArticleKey.init)
    }

    private var displayedArticleSnapshot: InspectorArticleSnapshot {
        guard articleSnapshot.articleKey == currentArticleKey else {
            return .empty(for: currentArticleKey)
        }
        return articleSnapshot
    }

    private var derivedArticleDataRefreshKey: InspectorArticleSnapshotRefreshKey {
        InspectorArticleSnapshotRefreshKey(
            articleKey: currentArticleKey,
            highlights: currentArticleHighlights,
            articleStates: currentArticleStates,
            tags: allTags
        )
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
            await refreshArticleSnapshot()
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
                highlights: displayedArticleSnapshot.highlights,
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
                VSplitView {
                    infoDetails(article)
                        .frame(minHeight: InspectorLayout.detailsMinimumHeight)

                    tableOfContentsPane
                        .frame(minHeight: InspectorLayout.contentsMinimumHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func infoDetails(_ article: Article) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
                infoTopModules(article)

                if !appState.currentArticleMetadata.isEmpty {
                    metadataSection
                        .transition(metadataSectionTransition)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .animation(
            reduceMotion ? nil : InspectorLayout.metadataTransitionAnimation,
            value: appState.currentArticleMetadata.isEmpty
        )
        .accessibilityLabel("Article details")
    }

    private func infoTopModules(_ article: Article) -> some View {
        VStack(alignment: .leading, spacing: InspectorLayout.sectionSpacing) {
            articleSummaryHeader(article)

            InspectorLabelSection(
                article: article,
                allLabels: allLabels.map(InspectorLabelSnapshot.init)
            )

            InspectorTagStatusBox(
                article: article,
                tags: displayedArticleSnapshot.tags,
                allTags: allTags.map(InspectorTagSnapshot.init),
                highlightIDs: displayedArticleSnapshot.highlights.map(\.id)
            )
        }
    }

    private var tableOfContentsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents")
                .font(MacWikiTypography.inspectorSectionLabel)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            if appState.currentArticleTableOfContents.isEmpty {
                ContentUnavailableView(
                    "No Contents",
                    systemImage: "list.bullet.indent",
                    description: Text("This article has no section headings.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: tableOfContentsSelection) {
                    ForEach(appState.currentArticleTableOfContents, id: \.id) { item in
                        tableOfContentsRow(item: item)
                            .tag(item.id)
                    }
                }
                .listStyle(.sidebar)
                .accessibilityLabel("Article contents")
            }
        }
    }

    private var tableOfContentsSelection: Binding<String?> {
        Binding(
            get: { appState.currentVisibleTableOfContentsSectionId },
            set: { newID in
                guard let newID else { return }
                appState.pendingTableOfContentsScrollTarget = newID
                appState.currentVisibleTableOfContentsSectionId = newID
            }
        )
    }

    private func tableOfContentsRow(item: ArticleTableOfContentsItem) -> some View {
        HStack(spacing: 6) {
            if item.level > 2 {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Text(item.title)
                .font(MacWikiTypography.inspectorTOCItem)
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(max(item.level - 2, 0)) * 12)
        .accessibilityLabel(item.title)
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

    @MainActor
    private func refreshArticleSnapshot() async {
        guard let article = appState.currentArticle else {
            articleSnapshot = .empty
            return
        }
        let requestedKey = InspectorArticleKey(article: article)
        // Native inspectors may reconstruct their content whenever they are
        // hidden and shown. Snapshot refreshes must therefore remain read-only:
        // state creation and synchronization belong to the Reader lifecycle or
        // explicit inspector mutations such as assigning a label or tag.
        let state = currentArticleStates.first
        guard !Task.isCancelled, currentArticleKey == requestedKey else { return }

        let refreshed = InspectorArticleSnapshot.make(
            article: article,
            articleState: state,
            highlights: currentArticleHighlights
        )
        if articleSnapshot != refreshed {
            articleSnapshot = refreshed
        }
    }

}
