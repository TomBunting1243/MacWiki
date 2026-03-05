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
                            try? modelContext.save()
                            articleForNewLabel = nil
                        }
                    }
                )
            }
            .sheet(item: $editingLabel) { label in
                LabelDetailSheet(
                    isPresented: Binding(get: { true }, set: { _ in editingLabel = nil }),
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
                        let urlString = "https://en.wikipedia.org/wiki/\(title.replacingOccurrences(of: " ", with: "_"))"
                        guard let url = URL(string: urlString) else { return }

                        let descriptor = FetchDescriptor<ArticleState>(
                            predicate: #Predicate { $0.articleURLString == url.absoluteString }
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

                        try? modelContext.save()
                        articleForNewTag = nil
                    }
                )
            }
    }
}
