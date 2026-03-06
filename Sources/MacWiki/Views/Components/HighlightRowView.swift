import SwiftUI
import SwiftData

struct HighlightRowView: View {
    let highlight: Highlight
    let allTags: [Tag]
    let onDelete: () -> Void
    let onTagSelected: ((Tag) -> Void)?

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("highlightMarkerStyle") private var highlightMarkerStyle: HighlightMarkerStyle = .dot
    @State private var isEditing = false
    @State private var editedNote = ""
    @State private var isHovered = false
    @State private var isExpanded = false
    @State private var showNewTagSheet = false
    @AppStorage("highlightHeaderWrap") private var highlightHeaderWrap = false
    @FocusState private var isNoteEditorFocused: Bool

    private var isSelected: Bool {
        guard let selectedId = appState.selectedHighlightId else { return false }
        return selectedId == highlight.id.uuidString
    }

    private var rowActivationHint: String {
        if isEditing {
            return "Select this highlight while editing."
        }
        return isExpanded ? "Collapse this highlight." : "Expand this highlight."
    }

    private var rowActivationActionName: Text {
        Text(isEditing ? "Select Highlight" : (isExpanded ? "Collapse Highlight" : "Expand Highlight"))
    }

    var body: some View {
        interactiveRow
            .contextMenu {
                contextMenuItems
            }
            .onChange(of: isEditing) { _, newValue in
                if newValue {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isNoteEditorFocused = true
                    }
                }
            }
            .task(id: appState.pendingHighlightNoteEditorRequest?.requestID) {
                consumePendingNoteEditorRequestIfNeeded()
            }
            .sheet(isPresented: $showNewTagSheet) {
                TagDetailSheet(isPresented: $showNewTagSheet, tagToEdit: nil) { tag in
                    if highlight.tags.contains(where: { $0.id == tag.id }) {
                        return
                    }
                    highlight.tags.append(tag)
                }
            }
    }

    private var interactiveRow: some View {
        styledRowContent
            .contentShape(Rectangle())
            .onTapGesture(perform: activateHighlightRow)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(rowActivationHint)
            .accessibilityAction(named: rowActivationActionName, activateHighlightRow)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
    }

    private var styledRowContent: some View {
        rowContent
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(rowBackgroundShape)
            .padding(.leading, highlightMarkerStyle == .bar ? 6 : 0)
            .overlay(alignment: .leading, content: leadingMarkerOverlay)
            .overlay(content: rowStrokeOverlay)
    }

    private var rowBackgroundShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(rowBackground)
    }

    @ViewBuilder
    private func leadingMarkerOverlay() -> some View {
        markerView
    }

    @ViewBuilder
    private func rowStrokeOverlay() -> some View {
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)

        if isSelected {
            RoundedRectangle(cornerRadius: 12)
                .stroke(selectionStrokeColor, lineWidth: selectionStrokeWidth)
        }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer(minLength: 8)
                    Text(shortRelativeAge)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.quaternary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if isExpanded {
                    Text(highlight.text)
                        .font(.callout)
                        .lineSpacing(2)
                        .foregroundStyle(.primary)
                        .layoutPriority(1)
                } else {
                    Text(highlight.text)
                        .font(.callout)
                        .lineLimit(3)
                        .lineSpacing(2)
                        .truncationMode(.tail)
                        .foregroundStyle(.primary)
                        .layoutPriority(1)
                }

                if let note = highlight.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 3)
                }

                if isExpanded, let context = contextText {
                    context
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }

                if isEditing {
                    noteEditor
                }

                if !sortedTags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 6) {
                        ForEach(sortedTags) { tag in
                            TagChipView(title: tag.name, isSelected: appState.highlightTagFilterId == tag.id) {
                                onTagSelected?(tag)
                            }
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headerTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(highlightHeaderWrap ? nil : 1)

                    Spacer(minLength: 8)

                    quickActionButtons
                }

                if highlight.isStale {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("Article updated — highlight may be out of date")
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12), in: Capsule())
                }

                if highlight.isArchived {
                    HStack(spacing: 6) {
                        Image(systemName: "archivebox.fill")
                            .font(.system(size: 9))
                        Text("Archived — hidden from article rendering")
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(colorScheme == .dark ? 0.18 : 0.10), in: Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if highlight.isArchived {
            Button {
                restoreHighlight()
            } label: {
                SwiftUI.Label("Restore Highlight", systemImage: "arrow.uturn.backward")
            }

            Divider()
        } else if highlight.isStale {
            Button {
                appState.pendingHighlightArticleRefresh = AppState.HighlightArticleRefreshRequest(
                    id: UUID(),
                    articleTitle: highlight.articleTitle
                )
            } label: {
                SwiftUI.Label("Refresh Article", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isHighlightArticleRefreshInProgress)

            Divider()
        }

        Button {
            editedNote = highlight.note ?? ""
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
                isEditing = true
            }
        } label: {
            SwiftUI.Label(highlight.note?.isEmpty ?? true ? "Add Note" : "Edit Note", systemImage: "pencil")
        }

        Divider()

        Menu {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        highlight.color = color
                        try? modelContext.save()
                        appState.pendingHighlightColorChange = AppState.HighlightColorChangeRequest(
                            id: highlight.id,
                            cssColor: color.cssColor
                        )
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 12, height: 12)
                        Text(color.rawValue)
                        Spacer()
                        if highlight.color == color {
                            Image(systemName: "checkmark")
                                .font(.caption)
                        }
                    }
                }
            }
        } label: {
            SwiftUI.Label("Change Color", systemImage: "paintpalette")
        }

        Divider()

        Menu {
            Button {
                showNewTagSheet = true
            } label: {
                SwiftUI.Label("New Tag", systemImage: "plus")
            }

            if !allTags.isEmpty {
                Divider()
            }

            if allTags.isEmpty {
                Text("No tags yet")
            } else {
                ForEach(allTags) { tag in
                    Button {
                        toggleTag(tag)
                    } label: {
                        HStack {
                            Text(tag.name)
                            Spacer()
                            if highlight.tags.contains(where: { $0.id == tag.id }) {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
        } label: {
            SwiftUI.Label("Tags", systemImage: "tag")
        }

        Divider()

        Button {
            _ = SystemBridge.copyText(highlight.text)
        } label: {
            SwiftUI.Label("Copy Text", systemImage: "doc.on.doc")
        }

        if let note = highlight.note, !note.isEmpty {
            Button {
                _ = SystemBridge.copyText(note)
            } label: {
                SwiftUI.Label("Copy Note", systemImage: "doc.on.doc.fill")
            }
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            SwiftUI.Label("Delete Highlight", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var markerView: some View {
        switch highlightMarkerStyle {
        case .dot:
            Circle()
                .fill(highlight.color.swiftUIColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .padding(.leading, 12)
        case .bar:
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(highlight.color.swiftUIColor)
                .frame(width: 4)
                .padding(.vertical, 8)
                .padding(.leading, 6)
        case .background:
            EmptyView()
        }
    }

    private var contextText: Text? {
        let beforeRaw = (highlight.contextBefore ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let afterRaw = (highlight.contextAfter ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !beforeRaw.isEmpty || !afterRaw.isEmpty else { return nil }

        let before = trimmedOverlapSuffix(beforeRaw, highlight.text)
        let after = trimmedOverlapPrefix(afterRaw, highlight.text)
        if before.isEmpty && after.isEmpty { return nil }

        let combined = "\(before) \(after)"
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.isEmpty { return nil }

        if highlight.text.localizedCaseInsensitiveContains(combined) {
            return nil
        }

        let prefix = before.isEmpty ? "" : "\(before) "
        let suffix = after.isEmpty ? "" : " \(after)"
        return Text("…") + Text(prefix) + Text(suffix) + Text("…")
    }

    private func jumpToHighlight() {
        appState.selectedHighlightId = highlight.id.uuidString
        appState.pendingHighlightScroll = highlight.id
    }

    private func activateHighlightRow() {
        appState.selectedHighlightId = highlight.id.uuidString
        guard !isEditing else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            isExpanded.toggle()
        }
    }

    private var quickActionButtons: some View {
        HStack(spacing: 6) {
            Button(
                highlight.note?.isEmpty ?? true ? "Add Note" : "Edit Note",
                systemImage: "note.text"
            ) {
                editedNote = highlight.note ?? ""
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                    isEditing = true
                }
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 20, height: 20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            }
            .buttonStyle(.plain)

            Button("Jump to Highlight", systemImage: "arrow.down.right") {
                jumpToHighlight()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 20, height: 20)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            }
            .buttonStyle(.plain)
            .disabled(highlight.isArchived)
        }
    }

    private var rowBackground: Color {
        if highlightMarkerStyle == .background {
            if isSelected {
                return highlight.color.swiftUIColor.opacity(colorScheme == .dark ? 0.26 : 0.18)
            }
            return highlight.color.swiftUIColor.opacity(colorScheme == .dark ? 0.16 : 0.10)
        }

        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12)
        }

        return Color.gray.opacity(isHovered ? 0.08 : 0.035)
    }

    private var selectionStrokeWidth: CGFloat {
        highlightMarkerStyle == .background ? 1.6 : 1.0
    }

    private var selectionStrokeColor: Color {
        if highlightMarkerStyle == .background {
            return highlight.color.swiftUIColor.opacity(0.6)
        }
        return Color.accentColor.opacity(0.6)
    }

    private var shortRelativeAge: String {
        let interval = max(0, Date().timeIntervalSince(highlight.createdAt))
        let minute = 60.0
        let hour = 60.0 * minute
        let day = 24.0 * hour
        let week = 7.0 * day
        let month = 30.0 * day
        let year = 365.0 * day

        switch interval {
        case 0..<minute:
            return "now"
        case minute..<hour:
            return "\(Int(interval / minute)) min"
        case hour..<day:
            return "\(Int(interval / hour)) hr"
        case day..<week:
            return "\(Int(interval / day)) d"
        case week..<month:
            return "\(Int(interval / week)) w"
        case month..<year:
            return "\(Int(interval / month)) mo"
        default:
            return "\(Int(interval / year)) yr"
        }
    }

    private var sortedTags: [Tag] {
        highlight.tags.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var headerTitle: String {
        if let section = highlight.sectionTitle,
           !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return section
        }
        return "Overview"
    }

    private func trimmedOverlapSuffix(_ text: String, _ highlightText: String) -> String {
        let maxOverlap = min(text.count, highlightText.count)
        guard maxOverlap > 0 else { return text }

        let highlightPrefix = Array(highlightText)
        let textChars = Array(text)

        for length in stride(from: maxOverlap, through: 1, by: -1) {
            let suffix = textChars.suffix(length)
            let prefix = highlightPrefix.prefix(length)
            if suffix.elementsEqual(prefix) {
                return String(textChars.dropLast(length)).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }

    private func trimmedOverlapPrefix(_ text: String, _ highlightText: String) -> String {
        let maxOverlap = min(text.count, highlightText.count)
        guard maxOverlap > 0 else { return text }

        let highlightSuffix = Array(highlightText)
        let textChars = Array(text)

        for length in stride(from: maxOverlap, through: 1, by: -1) {
            let prefix = textChars.prefix(length)
            let suffix = highlightSuffix.suffix(length)
            if prefix.elementsEqual(suffix) {
                return String(textChars.dropFirst(length)).trimmingCharacters(in: .whitespaces)
            }
        }
        return text
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(min(editedNote.count, 1000))/1000")
                    .font(.caption2)
                    .foregroundStyle(editedNote.count > 950 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                    .monospacedDigit()
            }

            ZStack(alignment: .topLeading) {
                if editedNote.isEmpty {
                    Text("Add a note…")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }

                TextEditor(text: $editedNote)
                    .font(.callout)
                    .focused($isNoteEditorFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
            }
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.55))
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isNoteEditorFocused ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 0.8)
            }
            .onChange(of: editedNote) { _, newValue in
                if newValue.count > 1000 {
                    editedNote = String(newValue.prefix(1000))
                }
            }

            HStack {
                Text("Tags")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button {
                        showNewTagSheet = true
                    } label: {
                        SwiftUI.Label("New Tag", systemImage: "plus")
                    }

                    if !allTags.isEmpty {
                        Divider()
                    }

                    if allTags.isEmpty {
                        Text("No tags yet")
                    } else {
                        ForEach(allTags) { tag in
                            Button {
                                toggleTag(tag)
                            } label: {
                                HStack {
                                    Text(tag.name)
                                    Spacer()
                                    if highlight.tags.contains(where: { $0.id == tag.id }) {
                                        Image(systemName: "checkmark")
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    SwiftUI.Label("Edit Tags", systemImage: "tag")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    editedNote = highlight.note ?? ""
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isEditing = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Save") {
                    highlight.note = editedNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : editedNote
                    highlight.updatedAt = Date()
                    try? modelContext.save()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isEditing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func toggleTag(_ tag: Tag) {
        if let index = highlight.tags.firstIndex(where: { $0.id == tag.id }) {
            highlight.tags.remove(at: index)
        } else {
            highlight.tags.append(tag)
        }
        try? modelContext.save()
    }

    private func restoreHighlight() {
        highlight.isArchived = false
        highlight.updatedAt = Date()
        try? modelContext.save()
    }

    private func consumePendingNoteEditorRequestIfNeeded() {
        guard let request = appState.pendingHighlightNoteEditorRequest else { return }
        guard request.highlightID == highlight.id else { return }

        appState.selectedHighlightId = highlight.id.uuidString
        editedNote = highlight.note ?? ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = true
            isEditing = true
        }

        if appState.pendingHighlightNoteEditorRequest?.requestID == request.requestID {
            appState.pendingHighlightNoteEditorRequest = nil
        }
    }
}
