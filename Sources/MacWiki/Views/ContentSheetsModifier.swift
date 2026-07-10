import SwiftUI
import SwiftData

extension View {
    func contentSheets(
        editingLabel: Binding<Label?>,
        showNewLabelSheet: Binding<Bool>,
        articleForNewLabel: Binding<SavedArticle?>,
        showNewTagSheet: Binding<Bool>,
        articleForNewTag: Binding<Article?>
    ) -> some View {
        modifier(ContentSheetsModifier(
            editingLabel: editingLabel,
            showNewLabelSheet: showNewLabelSheet,
            articleForNewLabel: articleForNewLabel,
            showNewTagSheet: showNewTagSheet,
            articleForNewTag: articleForNewTag
        ))
    }
}

struct ContentSheetsModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var readingLists: [ReadingList]

    @Binding var editingLabel: Label?
    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?
    @Binding var showNewTagSheet: Bool
    @Binding var articleForNewTag: Article?

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { appState.showAddToList },
                set: { appState.showAddToList = $0 }
            )) {
                AddToListSheet(article: appState.currentArticle)
            }
            .sheet(item: Binding(
                get: { appState.optionClickSaveRequest },
                set: { appState.optionClickSaveRequest = $0 }
            )) { request in
                OptionClickSaveSheet(article: request.article) {
                    appState.dismissOptionClickSavePrompt()
                }
            }
            .sheet(isPresented: $showNewLabelSheet) {
                LabelDetailSheet(
                    isPresented: $showNewLabelSheet,
                    labelToEdit: nil,
                    onSave: { newLabel in
                        if let article = articleForNewLabel {
                            article.labelId = newLabel.id
                            attachPendingLabelArticleIfNeeded(article)
                            modelContext.saveReportingFailure(operation: #function)
                            articleForNewLabel = nil
                        }
                    }
                )
            }
            .sheet(item: $editingLabel) { label in
                LabelDetailSheet(
                    isPresented: editingLabelSheetBinding,
                    labelToEdit: label
                )
            }
            .sheet(isPresented: $showNewTagSheet) {
                TagDetailSheet(
                    isPresented: $showNewTagSheet,
                    tagToEdit: nil,
                    onSave: { newTag in
                        guard let article = articleForNewTag else { return }
                        let title = article.title
                        let urlString = ReadStateSync.urlString(for: title)
                        guard let url = URL(string: urlString) else { return }

                        let descriptor = FetchDescriptor<ArticleState>(
                            predicate: #Predicate { $0.articleURLString == urlString }
                        )

                        if let state = try? modelContext.fetch(descriptor).first {
                            if !state.tags.contains(where: { $0.id == newTag.id }) {
                                state.tags.append(newTag)
                                state.updatedAt = Date()
                            }
                        } else {
                            let newState = ArticleState(articleTitle: title, articleURL: url)
                            newState.tags.append(newTag)
                            modelContext.insert(newState)
                        }

                        modelContext.saveReportingFailure(operation: #function)
                        articleForNewTag = nil
                    }
                )
            }
            .onChange(of: showNewLabelSheet) { _, isPresented in
                guard !isPresented else { return }
                cleanupPendingLabelDraftIfNeeded()
            }
    }

    private var defaultReadingList: ReadingList? {
        readingLists.first(where: { $0.name == "Inbox" }) ?? readingLists.first
    }

    private var editingLabelSheetBinding: Binding<Bool> {
        Binding(
            get: { editingLabel != nil },
            set: { isPresented in
                guard !isPresented else { return }
                editingLabel = nil
            }
        )
    }

    private func attachPendingLabelArticleIfNeeded(_ article: SavedArticle) {
        guard article.readingList == nil, let list = defaultReadingList else { return }
        guard !list.articles.contains(where: { $0.id == article.id }) else { return }

        list.articles.append(article)
        list.updatedAt = Date()
        SavedArticleSummaryBackfill.enqueueIfNeeded(article, modelContext: modelContext)
    }

    private func cleanupPendingLabelDraftIfNeeded() {
        guard let article = articleForNewLabel else { return }
        defer { articleForNewLabel = nil }

        guard article.readingList == nil, article.labelId == nil else { return }
        modelContext.delete(article)
        modelContext.saveReportingFailure(operation: #function)
    }
}
