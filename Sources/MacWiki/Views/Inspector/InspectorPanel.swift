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
    @State private var isContentsExpanded = true

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

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            InspectorHeaderBar(selection: $appState.inspectorMode)

            inspectorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                ScrollViewReader { proxy in
                    Form {
                        Section("Article") {
                            articleSummaryHeader(article)
                        }

                        Section("Organization") {
                            LabeledContent("Label") {
                                InspectorLabelSection(
                                    article: article,
                                    allLabels: allLabels.map(InspectorLabelSnapshot.init)
                                )
                            }

                            InspectorTagStatusBox(
                                article: article,
                                tags: displayedArticleSnapshot.tags,
                                allTags: allTags.map(InspectorTagSnapshot.init),
                                highlightIDs: displayedArticleSnapshot.highlights.map(\.id)
                            )
                        }

                        if !appState.currentArticleMetadata.isEmpty {
                            Section("Metadata") {
                                metadataContent
                            }
                        }

                        if !appState.currentArticleTableOfContents.isEmpty {
                            Section {
                                DisclosureGroup("Contents", isExpanded: $isContentsExpanded) {
                                    ForEach(appState.currentArticleTableOfContents, id: \.id) { item in
                                        tableOfContentsRow(item: item)
                                    }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, newID in
                        guard let newID else { return }
                        isContentsExpanded = true
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
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

    private func tableOfContentsRow(item: ArticleTableOfContentsItem) -> some View {
        let isActive = appState.currentVisibleTableOfContentsSectionId == item.id
        let indent = CGFloat(max(item.level - 2, 0)) * 14

        return Button {
            appState.pendingTableOfContentsScrollTarget = item.id
            appState.currentVisibleTableOfContentsSectionId = item.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "circle.fill" : "circle")
                    .imageScale(.small)
                    .foregroundStyle(
                        isActive
                            ? AnyShapeStyle(.tint)
                            : AnyShapeStyle(.tertiary)
                    )

                Text(item.title)
                    .font(isActive ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, indent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(item.id)
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
