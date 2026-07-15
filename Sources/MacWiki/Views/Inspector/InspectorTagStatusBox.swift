import SwiftUI
import SwiftData

struct InspectorTagStatusBox: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    let article: Article
    let tags: [InspectorTagSnapshot]
    let allTags: [InspectorTagSnapshot]
    let highlightIDs: [UUID]

    @State private var newTagName = ""
    @State private var isExpanded = false
    @State private var tagMarkedForRemoval: UUID?
    @State private var editingTagID: UUID?
    @FocusState private var isFieldFocused: Bool

    private var editingTagSheetBinding: Binding<Bool> {
        Binding(
            get: { editingTagID != nil },
            set: { isPresented in
                if !isPresented {
                    editingTagID = nil
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.9))

                Text("Tags")
                    .font(MacWikiTypography.inspectorSectionLabel)
                    .foregroundStyle(.primary)

                Spacer()

                if !tags.isEmpty {
                    Text("\(tags.count)")
                        .font(MacWikiTypography.compactRowMetadata)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .readerInspectorCapsuleSurface(
                            material: .thin,
                            baseBorderOpacity: 0.08
                        )
                }

                Button(isExpanded ? "Collapse Tags" : "Add Tags", systemImage: "chevron.down") {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        isExpanded.toggle()
                        tagMarkedForRemoval = nil
                        if isExpanded {
                            isFieldFocused = true
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(isExpanded ? -180 : 0))
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
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                                if tagMarkedForRemoval == tag.id {
                                    // Second tap on marked tag → remove it
                                    removeTag(id: tag.id)
                                    tagMarkedForRemoval = nil
                                } else {
                                    // First tap → mark for removal (red + X)
                                    tagMarkedForRemoval = tag.id
                                }
                            }
                        }
                        .contextMenu {
                            Button {
                                editingTagID = tag.id
                            } label: {
                                SwiftUI.Label("Rename", systemImage: "pencil")
                            }

                            Divider()

                            Button(role: .destructive) {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                                    removeTag(id: tag.id)
                                }
                            } label: {
                                SwiftUI.Label("Remove \"\(tag.name)\"", systemImage: "minus.circle")
                            }
                        }
                    }
                }
            } else if !isExpanded {
                Text("No tags yet")
                    .font(MacWikiTypography.settingsHelp)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }

            // Inline tag editor
            if isExpanded {
                tagEditor
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                    )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tagModuleBackground)
        .onTapGesture {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                tagMarkedForRemoval = nil
            }
        }
        .onChange(of: InspectorArticleKey(article: article)) {
            // Collapse editor and reset state when navigating to a different article
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
                isExpanded = false
                newTagName = ""
                tagMarkedForRemoval = nil
                editingTagID = nil
            }
        }
        .sheet(isPresented: editingTagSheetBinding) {
            if let editingTagID,
               let tag = InspectorPersistentModelResolver.tag(
                    id: editingTagID,
                    in: modelContext
               ) {
                TagDetailSheet(
                    isPresented: editingTagSheetBinding,
                    tagToEdit: tag
                )
            } else {
                ContentUnavailableView(
                    "Tag No Longer Available",
                    systemImage: "tag.slash",
                    description: Text("The tag was removed in another window.")
                )
                .frame(width: 320, height: 180)
                .task {
                    editingTagID = nil
                }
            }
        }
    }

    // MARK: - Tag Editor

    private var tagEditor: some View {
        InspectorTagEditor(
            newTagName: $newTagName,
            isFieldFocused: $isFieldFocused,
            assignedTagIDs: Set(tags.map(\.id)),
            allTags: allTags,
            onCreateOrAssign: addOrAssignTag,
            onAssign: assignTag
        )
    }

    private var tagModuleBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        return shape
            .fill(.quaternary.opacity(colorScheme == .dark ? 0.22 : 0.30))
            .overlay {
                shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.08), lineWidth: 0.8)
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
        assignTagModel(newTag)
        newTagName = ""
    }

    private func assignTag(_ tag: InspectorTagSnapshot) {
        guard let model = InspectorPersistentModelResolver.tag(
            id: tag.id,
            in: modelContext
        ) else { return }
        assignTagModel(model)
    }

    private func assignTagModel(_ tag: Tag) {
        let state = ensureArticleState()
        guard let state else { return }
        if state.tags.contains(where: { $0.id == tag.id }) { return }
        state.tags.append(tag)
        state.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
    }

    private func removeTag(id tagID: UUID) {
        guard let state = ensureArticleState() else { return }
        state.tags.removeAll { $0.id == tagID }
        state.updatedAt = Date()

        for highlightID in highlightIDs {
            guard let highlight = InspectorPersistentModelResolver.highlight(
                id: highlightID,
                in: modelContext
            ), highlight.tags.contains(where: { $0.id == tagID }) else { continue }
            highlight.tags.removeAll { $0.id == tagID }
            highlight.updatedAt = Date()
        }

        if appState.highlightTagFilterId == tagID {
            appState.highlightTagFilterId = nil
        }

        modelContext.saveReportingFailure(operation: #function)
    }

    private func ensureArticleState() -> ArticleState? {
        ReadStateSync.ensureArticleState(for: article, in: modelContext)
    }
}
