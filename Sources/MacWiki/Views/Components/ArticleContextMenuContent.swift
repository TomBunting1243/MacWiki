import SwiftUI
import SwiftData

/// Unified context menu content for articles across all views.
/// Ensures exact parity for Tags, Labels, Regular Lists, Tab History, and Recents.
struct ArticleContextMenuContent: View {
    // Article info
    let title: String
    let description: String?
    let extract: String?
    let thumbnailURL: URL?
    
    // State
    let isRead: Bool
    let currentLabelId: UUID?
    let currentTags: [Tag]
    let savedArticle: SavedArticle?
    let currentList: ReadingList?
    
    // Data
    let allLabels: [Label]
    let allTags: [Tag]
    let allLists: [ReadingList]
    
    // Callbacks
    let onToggleRead: () -> Void
    let onSetLabel: (UUID?) -> Void
    let onNewLabel: () -> Void
    let onToggleTag: (Tag) -> Void
    let onNewTag: () -> Void
    var onOpen: (() -> Void)? = nil
    let onOpenInNewTab: () -> Void
    var onShowPageViews: (() -> Void)? = nil
    let onMoveToList: ((ReadingList) -> Void)?
    let onAddToList: ((ReadingList) -> Void)?
    var onNewList: (() -> Void)? = {
        NotificationCenter.default.post(name: .macWikiRequestNewReadingList, object: nil)
    }
    let onRemove: (() -> Void)?
    let onCopyTitle: () -> Void
    let onCopyLink: () -> Void

    private var currentTagIDs: Set<UUID> {
        Set(currentTags.map(\.id))
    }

    private var addToListMenuTitle: String {
        savedArticle == nil && currentList == nil ? "Save to List" : "Add to List"
    }

    private var addToListMenuSymbol: String {
        savedArticle == nil && currentList == nil ? "bookmark" : "plus"
    }

    private var showsAddToListMenu: Bool {
        onAddToList != nil || onNewList != nil
    }
    
    var body: some View {
        Button {
            onToggleRead()
        } label: {
            SwiftUI.Label(
                isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: isRead ? "circle" : "checkmark.circle"
            )
        }
        
        Divider()
        
        Menu {
            Button {
                onSetLabel(nil)
            } label: {
                SwiftUI.Label(
                    "None",
                    systemImage: currentLabelId == nil ? "checkmark.circle.fill" : "circle"
                )
            }

            if !allLabels.isEmpty {
                Divider()
                ForEach(allLabels) { label in
                    Button {
                        onSetLabel(label.id)
                    } label: {
                        SwiftUI.Label {
                            Text(label.name)
                        } icon: {
                            Image(systemName: currentLabelId == label.id ? "checkmark.circle.fill" : "circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    currentLabelId == label.id ? Color.white : label.color.swiftUIColor,
                                    label.color.swiftUIColor
                                )
                        }
                    }
                }
            }

            Divider()

            Button {
                onNewLabel()
            } label: {
                SwiftUI.Label("New Label…", systemImage: "plus")
            }
        } label: {
            SwiftUI.Label("Set Label", systemImage: "tag")
        }

        Menu {
            if allTags.isEmpty {
                Button { } label: {
                    SwiftUI.Label("No Tags Yet", systemImage: "number")
                }
                .disabled(true)
            } else {
                ForEach(allTags) { tag in
                    Button {
                        onToggleTag(tag)
                    } label: {
                        SwiftUI.Label {
                            Text(tag.name)
                        } icon: {
                            Image(systemName: currentTagIDs.contains(tag.id) ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }

                Divider()
            }

            Button {
                onNewTag()
            } label: {
                SwiftUI.Label("New Tag…", systemImage: "plus")
            }
        } label: {
            SwiftUI.Label("Set Tags", systemImage: "number")
        }
        
        Divider()

        if let onOpen {
            Button {
                onOpen()
            } label: {
                SwiftUI.Label("Open", systemImage: "doc.text")
            }
        }

        Button {
            onOpenInNewTab()
        } label: {
            SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
        }

        if let onShowPageViews {
            Button {
                onShowPageViews()
            } label: {
                SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
            }
        }
        
        Divider()

        if let onMove = onMoveToList, let currentList = currentList, allLists.count > 1 {
            Menu {
                ForEach(allLists.filter { $0.id != currentList.id }) { targetList in
                    Button {
                        onMove(targetList)
                    } label: {
                        SwiftUI.Label(targetList.name, systemImage: targetList.icon)
                    }
                }
            } label: {
                SwiftUI.Label("Move to List", systemImage: "folder")
            }
        }

        if showsAddToListMenu {
            Menu {
                if let onAdd = onAddToList, !allLists.isEmpty {
                    ForEach(allLists) { list in
                        Button {
                            onAdd(list)
                        } label: {
                            SwiftUI.Label(list.name, systemImage: list.icon)
                        }
                    }

                    if onNewList != nil {
                        Divider()
                    }
                }

                if let onNewList {
                    Button {
                        onNewList()
                    } label: {
                        SwiftUI.Label("New List…", systemImage: "plus")
                    }
                }
            } label: {
                SwiftUI.Label(addToListMenuTitle, systemImage: addToListMenuSymbol)
            }
        }
        
        if let onRemove = onRemove {
            Button(role: .destructive) {
                onRemove()
            } label: {
                if savedArticle != nil && currentList != nil {
                    SwiftUI.Label("Remove from List", systemImage: "trash")
                } else {
                    SwiftUI.Label("Remove from Recent", systemImage: "trash")
                }
            }
        }
        
        Divider()

        Button {
            onCopyTitle()
        } label: {
            SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
        }
        
        Button {
            onCopyLink()
        } label: {
            SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
        }
    }
}

// MARK: - Convenience Initializer for Article
extension ArticleContextMenuContent {
    /// Creates menu content for an unsaved Article
    init(
        article: Article,
        isRead: Bool,
        currentTags: [Tag],
        allLabels: [Label],
        allTags: [Tag],
        allLists: [ReadingList],
        modelContext: ModelContext,
        appState: AppState,
        onNewLabel: @escaping (SavedArticle) -> Void,
        onNewTag: @escaping (Article) -> Void,
        onOpen: (() -> Void)? = nil,
        onOpenInNewTab: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil,
        onShowPageViews: (() -> Void)? = nil
    ) {
        let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        let existingState = ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext)

        func existingSavedArticle() -> SavedArticle? {
            for list in allLists {
                if let existing = list.articles.first(where: {
                    ReadStateSync.normalizedTitle($0.title) == normalizedTitle
                }) {
                    return existing
                }
            }
            return nil
        }

        let resolvedSavedArticle = existingSavedArticle()
        let resolvedLabelId = resolvedSavedArticle?.labelId ?? existingState?.labelId
        let resolvedTags: [Tag]
        if currentTags.isEmpty {
            resolvedTags = (existingState?.tags ?? []).sorted { $0.sortOrder < $1.sortOrder }
        } else {
            resolvedTags = currentTags
        }

        self.title = article.title
        self.description = article.description
        self.extract = article.extract
        self.thumbnailURL = article.thumbnailURL
        self.isRead = isRead
        self.currentLabelId = resolvedLabelId
        self.currentTags = resolvedTags
        self.savedArticle = nil
        self.currentList = nil
        self.allLabels = allLabels
        self.allTags = allTags
        self.allLists = allLists
        
        self.onToggleRead = {
            appState.updateReadState(forTitle: article.title, isRead: !isRead)
        }
        
        self.onSetLabel = { labelId in
            let state = ReadStateSync.ensureArticleState(for: article, in: modelContext, fallbackReadState: isRead)
            state.labelId = labelId
            state.updatedAt = Date()

            if let existing = existingSavedArticle() {
                existing.labelId = labelId
                try? modelContext.save()
                return
            }

            guard let labelId else {
                try? modelContext.save()
                return
            }

            let saved = SavedArticle(
                title: article.title,
                description: article.description,
                extract: article.extract,
                thumbnailURL: article.thumbnailURL
            )
            saved.labelId = labelId
            if let list = allLists.first(where: { $0.name == "Inbox" }) ?? allLists.first {
                list.articles.append(saved)
                list.updatedAt = Date()
            } else {
                modelContext.insert(saved)
            }
            try? modelContext.save()
            SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
        }
        
        self.onNewLabel = {
            if let existing = existingSavedArticle() {
                onNewLabel(existing)
                return
            }

            let draft = SavedArticle(
                title: article.title,
                description: article.description,
                extract: article.extract,
                thumbnailURL: article.thumbnailURL
            )
            draft.isRead = isRead
            modelContext.insert(draft)
            onNewLabel(draft)
        }
        
        self.onToggleTag = { tag in
            // Get or create ArticleState
            let urlString = ReadStateSync.urlString(for: article.title)
            let descriptor = FetchDescriptor<ArticleState>(predicate: #Predicate { $0.articleURLString == urlString })
            let existingState = try? modelContext.fetch(descriptor).first
            
            let state: ArticleState
            if let existing = existingState {
                state = existing
            } else {
                guard let url = URL(string: urlString) else { return }
                state = ArticleState(articleTitle: article.title, articleURL: url)
                modelContext.insert(state)
            }
            
            if let index = state.tags.firstIndex(where: { $0.id == tag.id }) {
                state.tags.remove(at: index)
            } else {
                state.tags.append(tag)
            }
            state.updatedAt = Date()
            try? modelContext.save()
        }
        
        self.onNewTag = {
            onNewTag(article)
        }

        self.onOpen = onOpen
        
        self.onOpenInNewTab = onOpenInNewTab ?? {
            appState.openArticleInNewTab(article)
        }

        self.onShowPageViews = onShowPageViews
        
        self.onMoveToList = nil
        
        self.onAddToList = { list in
            if list.articles.contains(where: {
                ReadStateSync.normalizedTitle($0.title) == normalizedTitle
            }) {
                return
            }

            let saved = SavedArticle(
                title: article.title,
                description: article.description,
                extract: article.extract,
                thumbnailURL: article.thumbnailURL,
                list: list
            )
            list.articles.append(saved)
            list.updatedAt = Date()
            try? modelContext.save()
            SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
        }
        
        self.onRemove = onRemove
        
        self.onCopyTitle = {
            _ = SystemBridge.copyText(article.title)
        }
        
        self.onCopyLink = {
            _ = SystemBridge.copyText(WikipediaURLBuilder.articleURLString(forTitle: article.title))
        }
    }
}
