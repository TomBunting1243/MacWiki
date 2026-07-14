import SwiftUI
import SwiftData

/// Native, compact list-membership editor for the current article.
struct SaveToListPopover: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var lists: [ReadingList]

    let article: Article

    @State private var showNewListField = false
    @State private var newListName = ""
    @State private var presentationOrder = ReadingListPresentationOrder()
    @FocusState private var isNewListFocused: Bool

    private var presentedLists: [ReadingList] {
        let listsByID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
        return presentationOrder.arrangedIDs(for: lists.map(\.id)).compactMap { listsByID[$0] }
    }

    private var normalizedArticleTitle: String {
        ReadStateSync.normalizedTitle(article.title)
    }

    private var trimmedNewListName: String {
        newListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)

            Divider()

            if lists.isEmpty {
                emptyState
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            } else {
                listMemberships
            }

            Divider()

            newListControls
                .padding(12)
        }
        .frame(width: 320)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            SwiftUI.Label("Save to List", systemImage: "bookmark")
                .font(.headline)

            Text(article.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            SwiftUI.Label("No Reading Lists", systemImage: "bookmark.slash")
        } description: {
            Text("Create a list to save this article.")
        }
    }

    private var listMemberships: some View {
        List {
            ForEach(presentedLists) { list in
                let isSaved = isArticleSaved(in: list)
                Toggle(
                    isOn: Binding(
                        get: { isArticleSaved(in: list) },
                        set: { setArticleSaved($0, in: list) }
                    )
                ) {
                    HStack(spacing: 8) {
                        Image(systemName: list.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 18)

                        Text(list.name)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(list.articles.count, format: .number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.checkbox)
                .accessibilityLabel(list.name)
                .accessibilityValue(isSaved ? "Saved" : "Not saved")
                .accessibilityHint("Toggles this article in the list")
            }
        }
        .listStyle(.inset)
        .frame(height: min(max(CGFloat(presentedLists.count) * 34, 112), 280))
    }

    @ViewBuilder
    private var newListControls: some View {
        if showNewListField {
            HStack(spacing: 8) {
                TextField("List Name", text: $newListName)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNewListFocused)
                    .onSubmit(createAndSaveToList)

                Button("Create", action: createAndSaveToList)
                    .disabled(trimmedNewListName.isEmpty)

                Button("Cancel") {
                    newListName = ""
                    showNewListField = false
                }
                .keyboardShortcut(.cancelAction)
            }
        } else {
            Button("New List", systemImage: "plus") {
                showNewListField = true
                Task { @MainActor in
                    isNewListFocused = true
                }
            }
        }
    }

    private func setArticleSaved(_ shouldSave: Bool, in list: ReadingList) {
        if shouldSave {
            ArticleLibraryActions.saveToList(article, list: list, modelContext: modelContext)
        } else {
            ArticleLibraryActions.removeAllFromList(
                withTitle: normalizedArticleTitle,
                list: list,
                modelContext: modelContext
            )
        }
    }

    private func isArticleSaved(in list: ReadingList) -> Bool {
        ArticleLibraryActions.containsArticle(withTitle: article.title, in: list)
    }

    private func createAndSaveToList() {
        guard let normalizedName = ReadingListNamePolicy.normalized(newListName) else { return }

        let newList = ReadingList(name: normalizedName)
        newList.sortOrder = SortOrderAllocator.next(for: lists.map(\.sortOrder))
        modelContext.insert(newList)
        ArticleLibraryActions.saveToList(article, list: newList, modelContext: modelContext)

        newListName = ""
        showNewListField = false
    }
}
