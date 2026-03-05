import SwiftUI
import SwiftData

/// Sheet for adding current article to a reading list (⌘L)
struct AddToListSheet: View {
    let article: Article?
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var lists: [ReadingList]
    
    @State private var searchText = ""
    @State private var showNewListSheet = false
    
    private var filteredLists: [ReadingList] {
        if searchText.isEmpty {
            return lists
        }
        return lists.filter { $0.name.localizedStandardContains(searchText) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if let article = article {
                    Text("Add \"\(article.title)\" to list...")
                        .font(.headline)
                        .lineLimit(1)
                } else {
                    Text("Add to List")
                        .font(.headline)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search lists...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
            
            // Lists
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if filteredLists.isEmpty {
                        if lists.isEmpty {
                            Text("No lists yet")
                                .foregroundStyle(.secondary)
                                .padding()
                        } else {
                            Text("No matching lists")
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                    } else {
                        ForEach(filteredLists) { list in
                            Button {
                                saveToList(list)
                            } label: {
                                HStack {
                                    Image(systemName: list.icon)
                                        .frame(width: 24)
                                    Text(list.name)
                                    Spacer()
                                    Text("\(list.articles.count)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Create new list
                    Button {
                        showNewListSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                                .frame(width: 24)
                            Text("Create New List")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 320, height: 400)
        .sheet(isPresented: $showNewListSheet) {
            NewListSheet(isPresented: $showNewListSheet)
        }
    }
    
    private func saveToList(_ list: ReadingList) {
        guard let article = article else {
            dismiss()
            return
        }
        
        // Check if already in list
        let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        if list.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalizedTitle }) {
            dismiss()
            return
        }
        
        let saved = SavedArticle(
            title: article.title,
            description: article.description,
            extract: article.extract,
            thumbnailURL: article.thumbnailURL,
            list: list,
            wordCount: article.wordCount
        )
        saved.isRead = ReadStateSync.resolveReadState(for: article, in: modelContext)
        list.articles.append(saved)
        list.updatedAt = Date()
        try? modelContext.save()
        SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
        
        dismiss()
    }
}
