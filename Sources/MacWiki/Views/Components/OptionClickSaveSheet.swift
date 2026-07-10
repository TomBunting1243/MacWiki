import SwiftData
import SwiftUI

/// Native macOS form for assigning a link to a list, tag, and label in one step.
struct OptionClickSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]

    let article: Article
    var onComplete: (() -> Void)? = nil

    @AppStorage(AppStorageKey.OptionClickSave.defaultListID) private var defaultListID = ""

    @State private var selectedListID: UUID?
    @State private var selectedTagID: UUID?
    @State private var selectedLabelID: UUID?
    @State private var newListName = ""
    @State private var isCreatingNewList = false
    @State private var isSaving = false
    @FocusState private var isNewListFocused: Bool

    private var trimmedNewListName: String {
        newListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedList: ReadingList? {
        guard let selectedListID else { return nil }
        return allLists.first(where: { $0.id == selectedListID })
    }

    private var selectedTag: Tag? {
        guard let selectedTagID else { return nil }
        return allTags.first(where: { $0.id == selectedTagID })
    }

    private var canSave: Bool {
        if isCreatingNewList || allLists.isEmpty {
            return !trimmedNewListName.isEmpty && !isSaving
        }
        return selectedList != nil && !isSaving
    }

    private var destinationSummaryText: String {
        let listText = isCreatingNewList
            ? (trimmedNewListName.isEmpty ? "new list" : "\"\(trimmedNewListName)\"")
            : "\"\(selectedList?.name ?? "list")\""
        let tagText = selectedTag?.name ?? "none"
        let labelText = allLabels.first(where: { $0.id == selectedLabelID })?.name ?? "none"
        return "Saving to \(listText) • Tag: \(tagText) • Label: \(labelText)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Article") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(article.title)
                            .font(.headline)
                            .textSelection(.enabled)

                        if let description = article.description, !description.isEmpty {
                            Text(description)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section("Destination") {
                    if isCreatingNewList || allLists.isEmpty {
                        TextField("List Name", text: $newListName)
                            .focused($isNewListFocused)
                            .onSubmit {
                                guard canSave else { return }
                                saveSelection()
                            }

                        if !allLists.isEmpty {
                            Button("Choose Existing List…", systemImage: "list.bullet") {
                                isCreatingNewList = false
                                seedSelectedListIfNeeded()
                            }
                        }
                    } else {
                        Picker("List", selection: $selectedListID) {
                            ForEach(allLists) { list in
                                SwiftUI.Label(list.name, systemImage: list.icon)
                                    .tag(Optional(list.id))
                            }
                        }

                        Button("Create New List…", systemImage: "plus") {
                            selectedListID = nil
                            isCreatingNewList = true
                            isNewListFocused = true
                        }
                    }

                    Picker("Label", selection: $selectedLabelID) {
                        Text("None").tag(UUID?.none)
                        ForEach(allLabels) { label in
                            SwiftUI.Label(label.name, systemImage: "tag")
                                .tag(Optional(label.id))
                        }
                    }

                    Picker("Tag", selection: $selectedTagID) {
                        Text("None").tag(UUID?.none)
                        ForEach(allTags) { tag in
                            SwiftUI.Label(tag.name, systemImage: "number")
                                .tag(Optional(tag.id))
                        }
                    }
                }

                Section("Summary") {
                    LabeledContent("Destination") {
                        Text(destinationSummaryText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Save Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: dismissSheet)
                        .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save", action: saveSelection)
                        .disabled(!canSave)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 420)
        .onAppear {
            selectedTagID = nil
            selectedLabelID = nil
            seedSelectedListIfNeeded()
            isNewListFocused = isCreatingNewList
        }
        .onChange(of: allLists.count) { _, _ in
            seedSelectedListIfNeeded()
        }
        .onChange(of: isCreatingNewList) { _, isCreating in
            guard isCreating else { return }
            isNewListFocused = true
        }
    }

    private func seedSelectedListIfNeeded() {
        if allLists.isEmpty {
            isCreatingNewList = true
            selectedListID = nil
            return
        }

        if isCreatingNewList {
            return
        }

        if let selectedListID,
           allLists.contains(where: { $0.id == selectedListID }) {
            return
        }

        if let rememberedID = UUID(uuidString: defaultListID),
           allLists.contains(where: { $0.id == rememberedID }) {
            selectedListID = rememberedID
            return
        }

        selectedListID = allLists.first?.id
    }

    private func saveSelection() {
        guard !isSaving else { return }
        isSaving = true

        let targetList: ReadingList?
        if !isCreatingNewList, let selectedList {
            targetList = selectedList
        } else {
            guard let name = ReadingListNamePolicy.normalized(newListName) else {
                isSaving = false
                return
            }
            let newList = ReadingList(name: name)
            newList.sortOrder = SortOrderAllocator.next(for: allLists.map(\.sortOrder))
            modelContext.insert(newList)
            targetList = newList
        }

        guard let targetList else {
            isSaving = false
            return
        }

        let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        let existing = targetList.articles.first {
            ReadStateSync.normalizedTitle($0.title) == normalizedTitle
        }

        let savedArticle: SavedArticle
        let createdNewArticle: Bool

        if let existing {
            savedArticle = existing
            createdNewArticle = false
        } else {
            savedArticle = SavedArticle(
                title: article.title,
                description: article.description,
                extract: article.extract,
                thumbnailURL: article.thumbnailURL,
                list: targetList,
                wordCount: article.wordCount
            )
            savedArticle.isRead = ReadStateSync.resolveReadState(for: article, in: modelContext)
            targetList.articles.append(savedArticle)
            createdNewArticle = true
        }

        savedArticle.labelId = selectedLabelID

        if let selectedTag {
            applyTag(selectedTag, to: article.title)
        }

        targetList.updatedAt = Date()
        defaultListID = targetList.id.uuidString

        modelContext.saveReportingFailure(operation: #function)

        if createdNewArticle {
            SavedArticleSummaryBackfill.enqueueIfNeeded(savedArticle, modelContext: modelContext)
        }

        isSaving = false
        dismissSheet()
    }

    private func applyTag(_ tag: Tag, to articleTitle: String) {
        let urlString = ReadStateSync.urlString(for: articleTitle)
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate { $0.articleURLString == urlString }
        )

        let state: ArticleState
        if let existing = try? modelContext.fetch(descriptor).first {
            state = existing
        } else {
            guard let url = URL(string: urlString) else { return }
            let created = ArticleState(articleTitle: articleTitle, articleURL: url)
            modelContext.insert(created)
            state = created
        }

        if !state.tags.contains(where: { $0.id == tag.id }) {
            state.tags.append(tag)
            state.updatedAt = Date()
        }
    }

    private func dismissSheet() {
        dismiss()
        onComplete?()
    }
}
