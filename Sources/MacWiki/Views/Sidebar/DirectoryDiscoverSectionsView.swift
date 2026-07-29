import SwiftData
import SwiftUI

struct DirectoryDiscoverLibrarySnapshot {
    let labels: [Label]
    let tags: [Tag]
    let lists: [ReadingList]
}

struct DirectoryDiscoverActions {
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void
    let openSearchResult: (WikipediaService.SearchResult, Bool?) -> Void
    let pageViewsPopoverBinding: (String) -> Binding<Bool>
    let presentPageViewsPopover: (
        _ title: String,
        _ rowKey: String,
        _ initialPulse: WikipediaService.TrendPulse?,
        _ referenceDate: Date
    ) -> Void
}

struct DirectoryDiscoverSectionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let feed: WikipediaService.DiscoverFeed
    let discoverTrendReferenceDate: Date
    let discoverTrendPulseStore: DiscoverTrendPulseStore
    let columnState: DirectoryColumnState
    let metadataHydrator: ArticleMetadataHydrator
    @Binding var pageViewsPresentation: SidebarPageViewsPresentationState
    let library: DirectoryDiscoverLibrarySnapshot
    let actions: DirectoryDiscoverActions

    private static let pageViewsPopoverDismissDelay: UInt64 = 700_000_000

    var body: some View {
        let mostReadSelection = SidebarDiscoverMostReadPolicy.selection(from: feed)

        Group {
            if let featured = feed.featuredArticle {
                Section {
                    discoverArticleRow(featured)
                } header: {
                    SidebarDiscoverSectionHeader(title: "Featured Article", count: 1)
                }
            }

            Section {
                if mostReadSelection.items.isEmpty {
                    Text("Most Read is temporarily unavailable for this date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(mostReadSelection.items) { result in
                        discoverArticleRow(result)
                    }
                }
            } header: {
                SidebarDiscoverSectionHeader(
                    title: mostReadSelection.sectionTitle,
                    count: mostReadSelection.items.count
                )
            }

            if !feed.newsStories.isEmpty {
                Section {
                    ForEach(feed.newsStories.prefix(8)) { story in
                        DiscoverStoryRow(story: story, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            actions.openSearchResult(article, inNewTab)
                        }
                    }
                } header: {
                    SidebarDiscoverSectionHeader(
                        title: "News Briefing",
                        count: min(feed.newsStories.count, 8)
                    )
                }
            }

            if !feed.inTheNews.isEmpty {
                Section {
                    ForEach(feed.inTheNews.prefix(12)) { result in
                        discoverArticleRow(result)
                    }
                } header: {
                    SidebarDiscoverSectionHeader(
                        title: "In the News",
                        count: min(feed.inTheNews.count, 12)
                    )
                }
            }

            let primaryTimeline = feed.onThisDaySelected.isEmpty ? feed.onThisDay : feed.onThisDaySelected
            if !primaryTimeline.isEmpty {
                Section {
                    ForEach(primaryTimeline.prefix(12)) { event in
                        DiscoverTimelineRow(event: event, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            actions.openSearchResult(article, inNewTab)
                        }
                    }
                } header: {
                    SidebarDiscoverSectionHeader(
                        title: "This Day in History",
                        count: min(primaryTimeline.count, 12)
                    )
                }
            }

            if !feed.onThisDayBirths.isEmpty {
                Section {
                    ForEach(feed.onThisDayBirths.prefix(8)) { event in
                        DiscoverTimelineRow(event: event, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            actions.openSearchResult(article, inNewTab)
                        }
                    }
                } header: {
                    SidebarDiscoverSectionHeader(
                        title: "Born on This Day",
                        count: min(feed.onThisDayBirths.count, 8)
                    )
                }
            }

            if !feed.onThisDayDeaths.isEmpty {
                Section {
                    ForEach(feed.onThisDayDeaths.prefix(8)) { event in
                        DiscoverTimelineRow(event: event, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            actions.openSearchResult(article, inNewTab)
                        }
                    }
                } header: {
                    SidebarDiscoverSectionHeader(
                        title: "Died on This Day",
                        count: min(feed.onThisDayDeaths.count, 8)
                    )
                }
            }

            if !feed.holidays.isEmpty {
                Section {
                    ForEach(feed.holidays.prefix(8)) { holiday in
                        DiscoverHolidayListRow(holiday: holiday, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            actions.openSearchResult(article, inNewTab)
                        }
                    }
                } header: {
                    SidebarDiscoverSectionHeader(
                        title: "Holidays & Observances",
                        count: min(feed.holidays.count, 8)
                    )
                }
            }

            if !feed.didYouKnow.isEmpty {
                Section {
                    ForEach(feed.didYouKnow.prefix(8)) { fact in
                        DiscoverFactRow(fact: fact, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            actions.openSearchResult(article, inNewTab)
                        }
                    }
                } header: {
                    SidebarDiscoverSectionHeader(
                        title: "Did You Know?",
                        count: min(feed.didYouKnow.count, 8)
                    )
                }
            }
        }
    }

    private func discoverArticleRow(_ result: WikipediaService.SearchResult) -> some View {
        let article = discoverArticle(from: result)
        let rowKey = DirectoryDiscoverRowInteractionPolicy.rowKey(
            articleID: result.id,
            title: article.title
        )
        let isRead = articleIndexes.effectiveReadState(
            for: article.title,
            fallback: article.isRead
        )
        let progress = articleIndexes.readingProgress(for: article.title, in: appState)
        let tags = articleIndexes.tagsForArticle(title: article.title)
        let trendPulse = discoverTrendPulseStore.pulse(for: article.title)

        return ArticleListItem(
            accessibilityTitle: article.title,
            isRead: isRead,
            progress: progress,
            isCurrent: articleIndexes.isCurrentArticle(article.title, in: appState),
            onTap: {
                let decision = DirectoryDiscoverRowInteractionPolicy.primaryTapDecision(
                    rowKey: rowKey,
                    pendingPageViewsRowKey: pageViewsPresentation.pendingRowKey
                )
                if decision == .suppressPageViewsTap {
                    pageViewsPresentation.pendingRowKey = nil
                    return
                }
                actions.openSearchResult(result, nil)
            }
        ) { isHovered, label in
            ArticleRowWithFetch(
                article: article,
                hydratedMetadata: metadataHydrator.snapshot(for: article.title),
                isHovered: isHovered,
                label: label,
                tags: tags,
                selectedTagId: columnState.localTagFilter?.id,
                trendPulse: trendPulse,
                pageViewsPresentation: SidebarPageViewsPopoverConfiguration(
                    title: article.title,
                    referenceDate: discoverTrendReferenceDate,
                    initialPulse: trendPulse,
                    style: .pulse,
                    isPresented: actions.pageViewsPopoverBinding(rowKey),
                    onRequestPresentation: {
                        pageViewsPresentation.pendingRowKey = rowKey
                        actions.presentPageViewsPopover(
                            article.title,
                            rowKey,
                            trendPulse,
                            discoverTrendReferenceDate
                        )
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: Self.pageViewsPopoverDismissDelay)
                            pageViewsPresentation.pendingRowKey =
                                DirectoryDiscoverRowInteractionPolicy.pendingRowKeyAfterTimeout(
                                    currentPendingRowKey: pageViewsPresentation.pendingRowKey,
                                    requestedRowKey: rowKey
                                )
                        }
                    },
                    onPulseLoaded: { pulse in
                        discoverTrendPulseStore.record(
                            pulse,
                            for: article.title,
                            referenceDate: discoverTrendReferenceDate
                        )
                    }
                ),
                onTagClick: { tag in
                    let nextTagID = DirectoryDiscoverRowInteractionPolicy.toggledTagFilterID(
                        currentTagID: columnState.localTagFilter?.id,
                        selectedTagID: tag.id
                    )
                    columnState.localTagFilter = nextTagID == nil ? nil : tag
                }
            )
        }
        .contextMenu {
            ArticleContextMenuContent(
                article: article,
                isRead: isRead,
                currentTags: tags,
                allLabels: library.labels,
                allTags: library.tags,
                allLists: library.lists,
                modelContext: modelContext,
                appState: appState,
                onNewLabel: { draft in
                    actions.onNewLabelWithArticle(draft)
                },
                onNewTag: { draftArticle in
                    actions.onNewTagWithArticle(draftArticle)
                },
                onShowPageViews: {
                    actions.presentPageViewsPopover(
                        article.title,
                        rowKey,
                        trendPulse,
                        discoverTrendReferenceDate
                    )
                }
            )
        }
        .discoverContentRowSpacing()
    }

    private var articleIndexes: DirectoryArticleIndexes {
        columnState.articleIndexesSnapshot
    }

    private func discoverArticle(from result: WikipediaService.SearchResult) -> Article {
        Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
    }
}
