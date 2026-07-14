import SwiftUI
import SwiftData

/// Native list chooser for adding the current article to a reading list (⌘L).
struct AddToListSheet: View {
    let article: Article?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var lists: [ReadingList]
    
    @State private var searchText = ""
    @State private var showNewListSheet = false
    @State private var presentationOrder = ReadingListPresentationOrder()

    private var presentedLists: [ReadingList] {
        let listsByID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        return presentationOrder.arrangedIDs(for: lists.map(\.id)).compactMap { listsByID[$0] }
    }
    
    private var filteredLists: [ReadingList] {
        if searchText.isEmpty {
            return presentedLists
        }
        return presentedLists.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let article {
                    Section("Article") {
                        Text(article.title)
                            .font(.headline)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }

                Section("Destination") {
                    if filteredLists.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredLists) { list in
                            let isSaved = article.map {
                                ArticleLibraryActions.containsArticle(withTitle: $0.title, in: list)
                            } ?? false

                            Button {
                                saveToList(list)
                            } label: {
                                HStack(spacing: 10) {
                                    SwiftUI.Label(list.name, systemImage: list.icon)
                                        .lineLimit(1)

                                    Spacer(minLength: 12)

                                    Text(list.articles.count, format: .number)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.tertiary)

                                    if isSaved {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .disabled(article == nil || isSaved)
                            .accessibilityLabel(list.name)
                            .accessibilityValue(isSaved ? "Already saved" : "\(list.articles.count) articles")
                        }
                    }

                    Button("Create New List…", systemImage: "plus") {
                        showNewListSheet = true
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search Lists")
            .navigationTitle("Add to List")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 460)
        .sheet(isPresented: $showNewListSheet) {
            NewListSheet(isPresented: $showNewListSheet)
        }
        .onAppear {
            presentationOrder.reconcile(with: lists.map(\.id))
        }
        .onChange(of: lists.map(\.id)) { _, ids in
            presentationOrder.reconcile(with: ids)
        }
        .onDisappear {
            presentationOrder.reset()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            SwiftUI.Label(
                lists.isEmpty ? "No Reading Lists" : "No Matching Lists",
                systemImage: lists.isEmpty ? "bookmark.slash" : "magnifyingglass"
            )
        } description: {
            Text(lists.isEmpty ? "Create a list to organize this article." : "Try a different search term.")
        }
    }

    private func saveToList(_ list: ReadingList) {
        guard let article = article else {
            dismiss()
            return
        }
        
        if ArticleLibraryActions.containsArticle(withTitle: article.title, in: list) {
            dismiss()
            return
        }

        ArticleLibraryActions.saveToList(article, list: list, modelContext: modelContext)
        dismiss()
    }
}
