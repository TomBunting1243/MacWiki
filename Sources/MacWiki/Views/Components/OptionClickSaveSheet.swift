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

    @AppStorage(AppStorageKey.OptionClickSave.defaultListID) private var defaultListID: String = ""

    @State private var selectedListID: UUID?
    @State private var selectedTagID: UUID?
    @State private var selectedLabelID: UUID?
    @State private var newListName = ""
    @State private var isCreatingNewList = false
    @State private var isTagsExpanded = false
    @State private var isSaving = false
    @FocusState private var isNewListFocused: Bool

    private enum Metrics {
        static let controlCornerRadius: CGFloat = 8
        static let sectionCornerRadius: CGFloat = 12
        static let controlHeight: CGFloat = 30
        static let rowHorizontalPadding: CGFloat = 14
        static let rowVerticalPadding: CGFloat = 11
        static let fieldLabelWidth: CGFloat = 54
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
            VStack(alignment: .leading, spacing: 16) {
                articleHeader
                primaryFieldsGroup
                tagsSection
                footerSummary
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(minWidth: 540, minHeight: 360)
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
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()
                .padding(.top, 4)
        }
    }

    private var primaryFieldsGroup: some View {
        VStack(spacing: 0) {
            fieldRow(title: "List") {
                listSelector
            }

            if isCreatingNewList || allLists.isEmpty {
                Divider().padding(.leading, Metrics.rowHorizontalPadding)
                fieldRow(title: "") {
                    newListEditor
                }
            }

            Divider().padding(.leading, Metrics.rowHorizontalPadding)
            fieldRow(title: "Label") {
                labelSelector
            }
        }
        .background(groupSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.sectionCornerRadius, style: .continuous)
                .strokeBorder(groupStrokeColor, lineWidth: 0.65)
        }
    }

    private var listSelector: some View {
        Menu {
            listMenuItems
        } label: {
            selectorButton(
                valueText: listDisplayText,
                fallbackText: "Select List",
                hasValue: !listDisplayText.isEmpty,
                tint: .accentColor
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.horizontal, 10)
        .frame(height: Metrics.controlHeight)
        .background(fieldSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                .strokeBorder(fieldStrokeColor, lineWidth: 0.6)
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
            selectorButton(
                valueText: labelDisplayText,
                fallbackText: "Add Label",
                hasValue: selectedLabel != nil,
                tint: selectedLabel?.color.swiftUIColor ?? .secondary
            )
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagsSection: some View {
        VStack(spacing: 0) {
            fieldRow(title: "Tags") {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isTagsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedTag?.name ?? "None")
                            .font(MacWikiTypography.controlValue)
                            .foregroundStyle(selectedTag == nil ? .secondary : .primary)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isTagsExpanded ? -180 : 0))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: Metrics.controlHeight)
                    .background(fieldSurfaceBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                            .strokeBorder(fieldStrokeColor, lineWidth: 0.6)
                    }
                }
                .buttonStyle(.plain)
            }

            if isTagsExpanded {
                Divider().padding(.leading, Metrics.rowHorizontalPadding)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        tagSelectionRow(id: nil, name: "None")
                        ForEach(allTags) { tag in
                            tagSelectionRow(id: tag.id, name: tag.name)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 168)
            }
        }
        .background(groupSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.sectionCornerRadius, style: .continuous)
                .strokeBorder(groupStrokeColor, lineWidth: 0.65)
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
                    .font(MacWikiTypography.controlValue)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(tagRowBackground(isSelected: selectedTagID == id))
        }
        .buttonStyle(.plain)
    }

    private func fieldRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if title.isEmpty {
                Color.clear
                    .frame(width: Metrics.fieldLabelWidth, height: 1)
            } else {
                Text(title)
                    .font(MacWikiTypography.controlValue)
                    .foregroundStyle(.secondary)
                    .frame(width: Metrics.fieldLabelWidth, alignment: .leading)
            }

            content()
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .padding(.vertical, Metrics.rowVerticalPadding)
    }

    private func selectorButton(
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
                .font(MacWikiTypography.controlValue)
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
        .padding(.horizontal, 10)
        .frame(height: Metrics.controlHeight)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous))
        .background(fieldSurfaceBackground)
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
                .strokeBorder(
                    hasValue
                        ? tint.opacity(colorScheme == .dark ? 0.28 : 0.20)
                        : fieldStrokeColor,
                    lineWidth: 0.65
                )
        }
    }

    private var footerSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(destinationSummaryText)
                .font(MacWikiTypography.settingsHelp)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private var groupSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.sectionCornerRadius, style: .continuous)
            .fill(
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.48 : 0.64)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.sectionCornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.06 : 0.20))
            }
    }

    private var fieldSurfaceBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.controlCornerRadius, style: .continuous)
            .fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.30 : 0.72)
            )
    }

    private var groupStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.075)
    }

    private var fieldStrokeColor: Color {
        Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.085)
    }

    private func tagRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(isSelected ? (colorScheme == .dark ? 0.18 : 0.16) : 0)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.10)
                            : Color.clear,
                        lineWidth: 0.55
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
