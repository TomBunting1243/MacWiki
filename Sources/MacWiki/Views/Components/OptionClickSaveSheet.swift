import SwiftUI
import SwiftData

/// Unified option-click save flow for assigning list, tag, and label in one place.
struct OptionClickSaveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]

    let article: Article
    var onComplete: (() -> Void)? = nil

    @AppStorage("optionClickSave.defaultListID") private var defaultListID: String = ""

    @State private var selectedListID: UUID?
    @State private var selectedTagID: UUID?
    @State private var selectedLabelID: UUID?
    @State private var newListName = ""
    @State private var isCreatingNewList = false
    @State private var isTagsExpanded = false
    @State private var isSaving = false
    @FocusState private var isNewListFocused: Bool

    private enum Metrics {
        static let controlCornerRadius: CGFloat = 10
        static let sectionCornerRadius: CGFloat = 12
        static let controlHeight: CGFloat = 34
    }

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

    private var selectedLabel: Label? {
        guard let selectedLabelID else { return nil }
        return allLabels.first(where: { $0.id == selectedLabelID })
    }

    private var rememberedDefaultList: ReadingList? {
        guard let rememberedID = UUID(uuidString: defaultListID) else { return nil }
        return allLists.first(where: { $0.id == rememberedID })
    }

    private var canSave: Bool {
        if isCreatingNewList || allLists.isEmpty {
            return !trimmedNewListName.isEmpty && !isSaving
        }
        return selectedList != nil && !isSaving
    }

    private var listDisplayText: String {
        if isCreatingNewList || allLists.isEmpty {
            return trimmedNewListName.isEmpty ? "New List" : trimmedNewListName
        }
        return selectedList?.name ?? "Select List"
    }

    private var labelDisplayText: String {
        selectedLabel?.name ?? "Add Label"
    }

    private var destinationSummaryText: String {
        let listText = isCreatingNewList
            ? (trimmedNewListName.isEmpty ? "new list" : "\"\(trimmedNewListName)\"")
            : "\"\(selectedList?.name ?? "list")\""
        let tagText = selectedTag?.name ?? "none"
        let labelText = selectedLabel?.name ?? "none"
        return "Saving to \(listText) • Tag: \(tagText) • Label: \(labelText)"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                articleHeader
                Divider()
                    .padding(.top, 10)
                    .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 12) {
                    listSelector

                    if isCreatingNewList || allLists.isEmpty {
                        newListEditor
                    }

                    labelSelector
                    tagsSection
                    footerSummary
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Save Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismissSheet()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving..." : "Save") {
                        saveSelection()
                    }
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 430)
        .onAppear {
            selectedTagID = nil
            selectedLabelID = nil
            seedSelectedListIfNeeded()
            if isCreatingNewList {
                isNewListFocused = true
            }
        }
        .onChange(of: allLists.count) { _, _ in
            seedSelectedListIfNeeded()
        }
    }

    private var articleHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(article.title)
                .font(.title3.weight(.bold))
                .lineLimit(3)
                .textSelection(.enabled)

            if let description = article.description, !description.isEmpty {
                Text(description)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var listSelector: some View {
        Menu {
            listMenuItems
        } label: {
            selectorCapsule(
                valueText: listDisplayText,
                fallbackText: "Select List",
                hasValue: !listDisplayText.isEmpty,
                tint: .accentColor
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private var listMenuItems: some View {
        if let rememberedDefaultList {
            Button {
                selectedListID = rememberedDefaultList.id
                isCreatingNewList = false
            } label: {
                SwiftUI.Label("Remembered Default: \(rememberedDefaultList.name)", systemImage: "clock.arrow.circlepath")
            }
        }

        if let mostRecent = allLists.first {
            Button {
                selectedListID = mostRecent.id
                isCreatingNewList = false
            } label: {
                SwiftUI.Label("Most Recent: \(mostRecent.name)", systemImage: "clock")
            }
        }

        if !allLists.isEmpty {
            Divider()
            ForEach(allLists) { list in
                Button {
                    selectedListID = list.id
                    isCreatingNewList = false
                } label: {
                    SwiftUI.Label {
                        Text(list.name)
                    } icon: {
                        Image(systemName: selectedListID == list.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedListID == list.id ? Color.accentColor : Color.secondary)
                    }
                }
            }
        }

        Divider()
        Button {
            isCreatingNewList = true
            selectedListID = nil
            newListName = ""
            DispatchQueue.main.async {
                isNewListFocused = true
            }
        } label: {
            SwiftUI.Label("New List…", systemImage: "plus")
        }

        if isCreatingNewList && !allLists.isEmpty {
            Button {
                isCreatingNewList = false
                seedSelectedListIfNeeded()
            } label: {
                SwiftUI.Label("Use Existing List", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var newListEditor: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("New list name", text: $newListName)
                .textFieldStyle(.plain)
                .focused($isNewListFocused)
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.controlHeight)
        .background(controlSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                .strokeBorder(controlStrokeColor, lineWidth: 0.55)
        }
    }

    private var labelSelector: some View {
        Menu {
            Button {
                selectedLabelID = nil
            } label: {
                SwiftUI.Label("None", systemImage: selectedLabelID == nil ? "checkmark.circle.fill" : "circle")
            }

            if !allLabels.isEmpty {
                Divider()
                ForEach(allLabels) { label in
                    Button {
                        selectedLabelID = label.id
                    } label: {
                        SwiftUI.Label {
                            Text(label.name)
                        } icon: {
                            Image(systemName: selectedLabelID == label.id ? "checkmark.circle.fill" : "circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(
                                    selectedLabelID == label.id ? Color.white : label.color.swiftUIColor,
                                    label.color.swiftUIColor
                                )
                        }
                    }
                }
            }
        } label: {
            selectorCapsule(
                valueText: labelDisplayText,
                fallbackText: "Add Label",
                hasValue: selectedLabel != nil,
                tint: selectedLabel?.color.swiftUIColor ?? .secondary
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isTagsExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isTagsExpanded ? -180 : 0))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            if isTagsExpanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        tagSelectionRow(id: nil, name: "None")
                        ForEach(allTags) { tag in
                            tagSelectionRow(id: tag.id, name: tag.name)
                        }
                    }
                }
                .frame(maxHeight: 150)
            } else {
                Text(selectedTag?.name ?? "No tags yet")
                    .font(.subheadline)
                    .foregroundStyle(selectedTag == nil ? .tertiary : .secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.sectionCornerRadius, style: .continuous)
                .strokeBorder(controlStrokeColor, lineWidth: 0.55)
        }
    }

    private func tagSelectionRow(id: UUID?, name: String) -> some View {
        Button {
            selectedTagID = id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedTagID == id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selectedTagID == id ? Color.accentColor : Color.secondary)
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(tagRowBackground(isSelected: selectedTagID == id))
        }
        .buttonStyle(.plain)
    }

    private func selectorCapsule(
        valueText: String,
        fallbackText: String,
        hasValue: Bool,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(hasValue ? tint.opacity(colorScheme == .dark ? 0.82 : 0.74) : Color.clear)
                .overlay {
                    if !hasValue {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.2)
                    }
                }
                .frame(width: 10, height: 10)

            Text(hasValue ? valueText : fallbackText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasValue ? .primary : .secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if !hasValue {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.controlHeight)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous))
        .background(controlSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                .strokeBorder(
                    hasValue
                        ? tint.opacity(colorScheme == .dark ? 0.22 : 0.16)
                        : controlStrokeColor,
                    lineWidth: 0.55
                )
        }
    }

    private var footerSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(destinationSummaryText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(controlSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                .strokeBorder(controlStrokeColor, lineWidth: 0.5)
        }
    }

    private var controlSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
            .fill(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.56 : 0.84)
            )
    }

    private var sectionSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.sectionCornerRadius, style: .continuous)
            .fill(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.42 : 0.68)
            )
    }

    private var controlStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.085 : 0.055)
    }

    private func tagRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(isSelected ? (colorScheme == .dark ? 0.16 : 0.09) : 0)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06)
                            : Color.clear,
                        lineWidth: 0.45
                    )
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
            let name = trimmedNewListName
            guard !name.isEmpty else {
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

        try? modelContext.save()

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
