import SwiftUI
import SwiftData

struct ReaderTabContextMenuContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let tab: ArticleTab
    let lists: [ReadingList]
    let allLabels: [Label]
    let matchingSavedArticle: SavedArticle?
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onClose: () -> Void

    @State private var saveScheduler = DebouncedActionScheduler()

    private var recentList: ReadingList? {
        lists.first
    }

    var body: some View {
        contextMenuContent
            .onDisappear {
                flushScheduledModelContextSave()
            }
    }

    private func requestModelContextSave() {
        saveScheduler.schedule { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
    }

    private func flushScheduledModelContextSave() {
        saveScheduler.flush { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        // Open actions
        Button {
            duplicateTab()
        } label: {
            SwiftUI.Label("Duplicate Tab", systemImage: "plus.square.on.square")
        }
        .disabled(tab.isPlaceholder)

        Divider()

        // Quick save to recent list
        if let recent = recentList {
            Button {
                saveToList(recent)
            } label: {
                SwiftUI.Label("Save to \"\(recent.name)\"", systemImage: recent.icon)
            }
        }

        // Full list submenu
        if !lists.isEmpty {
            Menu {
                ForEach(lists) { list in
                    Button {
                        saveToList(list)
                    } label: {
                        SwiftUI.Label(list.name, systemImage: list.icon)
                    }
                }
            } label: {
                SwiftUI.Label("Save to List", systemImage: "bookmark")
            }
        }

        Divider()

        ArticleQuickActionsMenuContent(title: tab.title)

        Divider()

        // Label management
        if let savedArticle = matchingSavedArticle {
            if !allLabels.isEmpty {
                Menu {
                    Button {
                        savedArticle.labelId = nil
                        requestModelContextSave()
                    } label: {
                        SwiftUI.Label(
                            "None",
                            systemImage: savedArticle.labelId == nil ? "checkmark.circle" : "circle"
                        )
                    }

                    Divider()

                    ForEach(allLabels) { label in
                        Button {
                            savedArticle.labelId = label.id
                            requestModelContextSave()
                        } label: {
                            SwiftUI.Label {
                                Text(label.name)
                            } icon: {
                                Image(systemName: savedArticle.labelId == label.id ? "checkmark.circle.fill" : "circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(savedArticle.labelId == label.id ? Color.white : label.color.swiftUIColor, label.color.swiftUIColor)
                            }
                        }
                    }

                    Divider()

                    Button {
                        onNewLabelWithArticle(savedArticle)
                    } label: {
                        SwiftUI.Label("New Label...", systemImage: "plus")
                    }
                } label: {
                    SwiftUI.Label("Set Label", systemImage: "tag")
                }

                Divider()
            }
        }

        Divider()

        Button {
            closeOtherTabs()
        } label: {
            SwiftUI.Label("Close Other Tabs", systemImage: "xmark.square")
        }

        Button("Close Tab", role: .destructive, action: onClose)
    }

    private func saveToList(_ list: ReadingList) {
        guard let sourceArticle = tab.currentArticle else { return }
        let normalized = ReadStateSync.normalizedTitle(sourceArticle.title)
        if list.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalized }) {
            return
        }

        let article = SavedArticle(
            title: sourceArticle.title,
            description: sourceArticle.description,
            extract: sourceArticle.extract,
            thumbnailURL: sourceArticle.thumbnailURL,
            list: list,
            wordCount: sourceArticle.wordCount
        )
        article.isRead = ReadStateSync.resolveReadState(for: sourceArticle, in: modelContext)
        list.articles.append(article)
        list.updatedAt = Date()

        modelContext.saveReportingFailure(operation: #function)
        SavedArticleSummaryBackfill.enqueueIfNeeded(article, modelContext: modelContext)
    }

    private func duplicateTab() {
        appState.tabSessionStore.duplicateTab(id: tab.id)
    }

    private func closeOtherTabs() {
        appState.closeOtherTabs(keeping: tab.id)
    }
}
