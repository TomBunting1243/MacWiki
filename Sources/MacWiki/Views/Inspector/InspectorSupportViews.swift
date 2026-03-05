import SwiftUI
import SwiftData

// MARK: - Label Section

struct InspectorLabelSection: View {
    @Environment(\.modelContext) private var modelContext

    let article: Article
    let allLabels: [Label]

    @State private var showNewLabelSheet = false
    @State private var pendingNewLabel: Label?
    @State private var isHovered = false

    private var savedArticles: [SavedArticle] {
        fetchSavedArticlesMatchingActiveTitle()
    }

    private var selectedLabelId: UUID? {
        let ids = Set(savedArticles.compactMap { $0.labelId })
        if !savedArticles.isEmpty {
            if ids.count == 1 { return ids.first }
            return ids.isEmpty ? articleState?.labelId : nil
        }
        return articleState?.labelId
    }

    private var currentLabel: Label? {
        guard let id = selectedLabelId else { return nil }
        if let modelLabel = allLabels.first(where: { $0.id == id }) {
            return modelLabel
        }
        if let pending = pendingNewLabel, pending.id == id {
            return pending
        }
        return nil
    }

    var body: some View {
        Menu {
            labelMenuItems
        } label: {
            labelMenuButton
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: selectedLabelId)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .sheet(isPresented: $showNewLabelSheet) {
            LabelDetailSheet(isPresented: $showNewLabelSheet, labelToEdit: nil) { label in
                pendingNewLabel = label
                applyLabel(label)
            }
        }
        .onChange(of: selectedLabelId) { _, newValue in
            if pendingNewLabel?.id != newValue {
                pendingNewLabel = nil
            }
        }
    }

    // MARK: - Menu Button

    private var labelMenuButton: some View {
        let color = currentLabel?.color.swiftUIColor
        let hasLabel = currentLabel != nil

        return HStack(spacing: 8) {
            Circle()
                .fill(color ?? Color.clear)
                .overlay {
                    if color == nil {
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1.2)
                    }
                }
                .frame(width: 10, height: 10)

            Text(currentLabel?.name ?? "Add Label")
                .font(.caption.weight(.semibold))
                .foregroundStyle(hasLabel ? (color ?? .primary) : .secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if !hasLabel {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 29)
        .contentShape(Capsule())
        .background(
            Capsule()
                .fill(color?.opacity(0.09) ?? Color.secondary.opacity(0.05))
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    color?.opacity(isHovered ? 0.36 : 0.22) ?? Color.primary.opacity(isHovered ? 0.16 : 0.08),
                    lineWidth: isHovered ? 1.0 : 0.8
                )
        }
    }

    // MARK: - Menu Items

    @ViewBuilder
    private var labelMenuItems: some View {
        Button {
            applyLabel(nil)
        } label: {
            SwiftUI.Label {
                Text("None")
            } icon: {
                Image(systemName: selectedLabelId == nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.secondary)
            }
        }

        if !allLabels.isEmpty {
            Divider()

            ForEach(allLabels) { label in
                Button {
                    applyLabel(label)
                } label: {
                    SwiftUI.Label {
                        Text(label.name)
                    } icon: {
                        Image(systemName: selectedLabelId == label.id ? "checkmark.circle.fill" : "circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                selectedLabelId == label.id ? Color.white : label.color.swiftUIColor,
                                label.color.swiftUIColor
                            )
                    }
                }
            }
        }

        Divider()

        Button {
            showNewLabelSheet = true
        } label: {
            SwiftUI.Label("New Label…", systemImage: "plus")
        }
    }

    // MARK: - Actions

    private func applyLabel(_ label: Label?) {
        ensureArticleState()?.labelId = label?.id
        for saved in fetchSavedArticlesMatchingActiveTitle() {
            saved.labelId = label?.id
        }
        try? modelContext.save()
    }

    private func fetchSavedArticlesMatchingActiveTitle() -> [SavedArticle] {
        let normalizedActiveTitle = ReadStateSync.normalizedTitle(article.title)
        let variants = Set([
            article.title,
            article.title.replacingOccurrences(of: "_", with: " "),
            article.title.replacingOccurrences(of: " ", with: "_")
        ])

        var matches: [SavedArticle] = []
        var seen = Set<UUID>()

        for variant in variants {
            let descriptor = FetchDescriptor<SavedArticle>(
                predicate: #Predicate { $0.title == variant }
            )
            let rows = (try? modelContext.fetch(descriptor)) ?? []
            for row in rows {
                guard !seen.contains(row.id) else { continue }
                guard ReadStateSync.normalizedTitle(row.title) == normalizedActiveTitle else { continue }
                seen.insert(row.id)
                matches.append(row)
            }
        }

        return matches
    }

    private var articleState: ArticleState? {
        ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext)
    }

    @discardableResult
    private func ensureArticleState() -> ArticleState? {
        ReadStateSync.ensureArticleState(for: article, in: modelContext)
    }
}

// MARK: - Tag Section

struct InspectorTagStatusBox: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let article: Article
    let tags: [Tag]
    let allTags: [Tag]

    @State private var articleState: ArticleState?
    @State private var newTagName = ""
    @State private var isExpanded = false
    @State private var tagMarkedForRemoval: UUID?
    @State private var editingTag: Tag?
    @FocusState private var isFieldFocused: Bool

    /// Unassigned tags matching the current search filter
    private var suggestedTags: [Tag] {
        let assignedIds = Set(tags.map(\.id))
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            return allTags.filter { !assignedIds.contains($0.id) }
        }

        return allTags.filter { tag in
            !assignedIds.contains(tag.id) &&
            tag.name.localizedStandardContains(trimmed)
        }
    }

    /// Whether the typed text is a genuinely new tag name
    private var typedNameIsNew: Bool {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = trimmed.lowercased()
        return !allTags.contains { $0.name.lowercased() == normalized }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                        tagMarkedForRemoval = nil
                        if isExpanded {
                            isFieldFocused = true
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .rotationEffect(.degrees(isExpanded ? -180 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Add Tags")
            }

            // Assigned tag chips
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags) { tag in
                        TagChipView(
                            title: tag.name,
                            isSelected: appState.highlightTagFilterId == tag.id,
                            isMarkedForRemoval: tagMarkedForRemoval == tag.id,
                            showsIcon: true
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if tagMarkedForRemoval == tag.id {
                                    // Second tap on marked tag → remove it
                                    removeTag(tag)
                                    tagMarkedForRemoval = nil
                                } else {
                                    // First tap → mark for removal (red + X)
                                    tagMarkedForRemoval = tag.id
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                editingTag = tag
                            } label: {
                                SwiftUI.Label("Rename", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    removeTag(tag)
                                }
                            } label: {
                                SwiftUI.Label("Remove \"\(tag.name)\"", systemImage: "minus.circle")
                            }
                        }
                    }
                }
            } else if !isExpanded {
                Text("No tags yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Inline tag editor
            if isExpanded {
                tagEditor
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                tagMarkedForRemoval = nil
            }
        }
        .onAppear {
            articleState = ReadStateSync.fetchArticleState(
                forURLString: article.url.absoluteString, in: modelContext
            )
        }
        .onChange(of: article.title) {
            // Collapse editor and reset state when navigating to a different article
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded = false
                newTagName = ""
                tagMarkedForRemoval = nil
            }
            articleState = ReadStateSync.fetchArticleState(
                forURLString: article.url.absoluteString, in: modelContext
            )
        }
        .sheet(item: $editingTag) { tag in
            TagDetailSheet(
                isPresented: Binding(
                    get: { true },
                    set: { _ in editingTag = nil }
                ),
                tagToEdit: tag
            )
        }
    }

    // MARK: - Tag Editor

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search / create field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)

                TextField("Add or search tags", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .focused($isFieldFocused)
                    .onSubmit {
                        addOrAssignTag()
                    }

                if !newTagName.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            newTagName = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.quaternary.opacity(0.32))
            )
            .overlay {
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
            }

            // "Create" row for new tag names
            if typedNameIsNew {
                let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)

                Button {
                    addOrAssignTag()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text("Create \"\(trimmed)\"")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Color.accentColor.opacity(0.08),
                        in: Capsule()
                    )
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 0.8)
                    }
                }
                .buttonStyle(.plain)
            }

            // Suggested unassigned tags
            if !suggestedTags.isEmpty {
                ScrollView {
                    FlowLayout(spacing: 6) {
                        ForEach(suggestedTags) { tag in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    assignTag(tag)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 8, weight: .bold))
                                    Text(tag.name)
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Color.gray.opacity(0.05),
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollClipDisabled()
                .frame(maxHeight: 120)
            } else if allTags.isEmpty && newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Type a name to create your first tag.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Tag Actions

    private func addOrAssignTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let normalized = trimmed.lowercased()
        if let existing = allTags.first(where: { $0.name.lowercased() == normalized }) {
            assignTag(existing)
            newTagName = ""
            return
        }

        let newTag = Tag(name: trimmed)
        newTag.sortOrder = SortOrderAllocator.next(for: allTags.map(\.sortOrder))
        modelContext.insert(newTag)
        assignTag(newTag)
        newTagName = ""
    }

    private func assignTag(_ tag: Tag) {
        let state = ensureArticleState()
        guard let state else { return }
        if state.tags.contains(where: { $0.id == tag.id }) { return }
        state.tags.append(tag)
        state.updatedAt = Date()
        try? modelContext.save()
    }

    private func removeTag(_ tag: Tag) {
        guard let state = ensureArticleState() else { return }
        state.tags.removeAll { $0.id == tag.id }
        state.updatedAt = Date()
        try? modelContext.save()
    }

    private func ensureArticleState() -> ArticleState? {
        if let state = articleState { return state }
        let state = ReadStateSync.ensureArticleState(for: article, in: modelContext)
        articleState = state
        return state
    }
}
