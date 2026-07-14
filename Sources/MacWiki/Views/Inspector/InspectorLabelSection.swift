import SwiftUI
import SwiftData

struct InspectorLabelSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query private var matchingSavedArticles: [SavedArticle]
    @Query private var matchingArticleStates: [ArticleState]

    let article: Article
    let allLabels: [Label]

    @State private var showNewLabelSheet = false
    @State private var pendingNewLabel: Label?
    @State private var isHovered = false
    @State private var assignment: InspectorLabelAssignment?

    init(article: Article, allLabels: [Label]) {
        self.article = article
        self.allLabels = allLabels

        let titleVariants = InspectorLabelArticleKey(article: article).titleVariants
        let primaryTitle = titleVariants.first ?? article.title
        let secondaryTitle = titleVariants.dropFirst().first ?? primaryTitle
        let tertiaryTitle = titleVariants.dropFirst(2).first ?? secondaryTitle
        let urlString = article.url.absoluteString
        _matchingSavedArticles = Query(
            filter: #Predicate<SavedArticle> { saved in
                saved.title == primaryTitle
                    || saved.title == secondaryTitle
                    || saved.title == tertiaryTitle
            }
        )
        _matchingArticleStates = Query(
            filter: #Predicate<ArticleState> { state in
                state.articleURLString == urlString
            }
        )
    }

    private var articleKey: InspectorLabelArticleKey {
        InspectorLabelArticleKey(article: article)
    }

    private var currentAssignment: InspectorLabelAssignment? {
        guard assignment?.articleKey == articleKey else { return nil }
        return assignment
    }

    private var assignmentRefreshKey: InspectorLabelAssignmentRefreshKey {
        InspectorLabelAssignmentRefreshKey(
            articleKey: articleKey,
            savedArticles: matchingSavedArticles,
            articleStates: matchingArticleStates
        )
    }

    private var selectedLabelId: UUID? {
        currentAssignment?.selectedLabelID
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
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.82), value: selectedLabelId)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .task(id: assignmentRefreshKey) {
            await refreshAssignment(for: articleKey)
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
                .font(MacWikiTypography.controlAuxiliary)
                .foregroundStyle(hasLabel ? (color ?? .primary) : .secondary)
                .lineLimit(1)
                .contentTransition(.interpolate)

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
        .padding(.horizontal, 11)
        .frame(height: 27)
        .contentShape(Capsule())
        .background(
            Capsule()
                .fill(color?.opacity(0.06) ?? Color.secondary.opacity(0.032))
        )
        .overlay {
            Capsule()
                .strokeBorder(
                    color?.opacity(isHovered ? 0.28 : 0.16) ?? Color.primary.opacity(isHovered ? 0.11 : 0.055),
                    lineWidth: isHovered ? 1.0 : 0.8
                )
        }
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: selectedLabelId)
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
        let resolvedAssignment = assignmentForMutation()
        let state = resolvedAssignment.articleState ?? ensureArticleState()
        state?.labelId = label?.id
        state?.updatedAt = Date()

        var savedArticles = resolvedAssignment.savedArticles
        for saved in savedArticles {
            saved.labelId = label?.id
        }

        if let label, savedArticles.isEmpty {
            let saved = SavedArticle(
                title: article.title,
                description: article.description,
                extract: article.extract,
                thumbnailURL: article.thumbnailURL,
                wordCount: article.wordCount
            )
            saved.labelId = label.id
            saved.isRead = state?.isRead ?? false

            if let list = allLists.first(where: { $0.name == "Inbox" }) ?? allLists.first {
                list.articles.append(saved)
                list.updatedAt = Date()
            } else {
                modelContext.insert(saved)
            }

            savedArticles.append(saved)

            SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
        }

        assignment = InspectorLabelAssignment(
            articleKey: articleKey,
            savedArticles: savedArticles,
            articleState: state
        )
        modelContext.saveReportingFailure(operation: #function)
    }

    private func refreshAssignment(for key: InspectorLabelArticleKey) async {
        // Keep SwiftData work out of body evaluation while preserving ModelContext's
        // main-actor confinement. The task is cancelled automatically on navigation.
        await Task.yield()
        guard !Task.isCancelled else { return }

        let refreshed = InspectorLabelAssignmentLoader.load(for: key, in: modelContext)
        guard !Task.isCancelled, articleKey == key else { return }
        assignment = refreshed
    }

    private func assignmentForMutation() -> InspectorLabelAssignment {
        // Mutations deliberately refresh once so an article saved elsewhere after
        // this section loaded still receives the label. This user-action fetch does
        // not run during view evaluation.
        return InspectorLabelAssignmentLoader.load(for: articleKey, in: modelContext)
    }

    @discardableResult
    private func ensureArticleState() -> ArticleState? {
        ReadStateSync.ensureArticleState(for: article, in: modelContext)
    }
}
