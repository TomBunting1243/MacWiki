import SwiftUI
import SwiftData

/// Popover for saving an article to a reading list
/// HIG-compliant: Immediate action, no decorative animations
struct SaveToListPopover: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var lists: [ReadingList]
    
    let articleTitle: String
    let articleDescription: String?
    let articleExtract: String?
    let thumbnailURL: URL?
    let articleWordCount: Int?
    
    @State private var showNewListField = false
    @State private var newListName = ""
    @FocusState private var isNewListFocused: Bool

    private var normalizedArticleTitle: String {
        ReadStateSync.normalizedTitle(articleTitle)
    }

    private var trimmedNewListName: String {
        newListName.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Save to List")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            if lists.isEmpty && !showNewListField {
                Text("No lists")
                    .foregroundStyle(.tertiary)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                
                Button("New List") {
                    showNewListField = true
                    isNewListFocused = true
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(lists) { list in
                            let isSaved = isArticleSaved(in: list)
                            Button {
                                toggleSave(in: list)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: list.icon)
                                        .foregroundStyle(.secondary)

                                    Text(list.name)
                                        .lineLimit(1)

                                    Spacer()

                                    if !list.articles.isEmpty {
                                        Text("\(list.articles.count)")
                                            .foregroundStyle(.tertiary)
                                            .monospacedDigit()
                                    }

                                    Image(systemName: isSaved ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSaved ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(list.name)
                            .accessibilityValue(isSaved ? "Saved" : "Not saved")
                            .accessibilityHint("Toggles this article in the list")
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(maxHeight: 280)
                
                Divider()
                
                // New list input or button
                if showNewListField {
                    HStack {
                        TextField("Name", text: $newListName)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .focused($isNewListFocused)
                            .onSubmit {
                                createAndSaveToList()
                            }
                        
                        Button("Add") {
                            createAndSaveToList()
                        }
                        .controlSize(.small)
                        .disabled(trimmedNewListName.isEmpty)
                    }
                } else {
                    Button {
                        showNewListField = true
                        isNewListFocused = true
                    } label: {
                        SwiftUI.Label("New List", systemImage: "plus")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(width: 240)
    }
    
    private func toggleSave(in list: ReadingList) {
        if isArticleSaved(in: list) {
            list.articles.removeAll {
                ReadStateSync.normalizedTitle($0.title) == normalizedArticleTitle
            }
            list.updatedAt = Date()
            modelContext.saveReportingFailure(operation: #function)
            dismiss()
            return
        }

        saveToList(list)
    }

    private func saveToList(_ list: ReadingList) {
        guard !isArticleSaved(in: list) else {
            dismiss()
            return
        }

        let article = SavedArticle(
            title: articleTitle,
            description: articleDescription,
            extract: articleExtract,
            thumbnailURL: thumbnailURL,
            list: list,
            wordCount: articleWordCount
        )
        article.isRead = ReadStateSync.resolveReadState(for: articleTitle, in: modelContext)
        list.articles.append(article)
        list.updatedAt = Date()
        
        modelContext.saveReportingFailure(operation: #function)
        SavedArticleSummaryBackfill.enqueueIfNeeded(article, modelContext: modelContext)
        dismiss()
    }

    private func isArticleSaved(in list: ReadingList) -> Bool {
        list.articles.contains {
            ReadStateSync.normalizedTitle($0.title) == normalizedArticleTitle
        }
    }
    
    private func createAndSaveToList() {
        guard let normalizedName = ReadingListNamePolicy.normalized(newListName) else { return }
        
        let newList = ReadingList(name: normalizedName)
        newList.sortOrder = SortOrderAllocator.next(for: lists.map(\.sortOrder))
        modelContext.insert(newList)
        
        saveToList(newList)
    }
}
