import SwiftUI
import SwiftData

struct HighlightRowView: View {
    let highlight: Highlight
    let onDelete: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var isEditing = false
    @State private var editedNote = ""
    @State private var isHovered = false
    @State private var isExpanded = false
    @AppStorage(AppStorageKey.Highlights.headerWrap) private var highlightHeaderWrap = false
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
    }

    private var interactiveRow: some View {
        styledRowContent
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
            .overlay(content: rowStrokeOverlay)
    }

    private var rowBackgroundShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(rowBackground)
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
        VStack(alignment: .leading, spacing: 10) {
            Button(action: activateHighlightRow) {
                rowSummary
            }
            .buttonStyle(.plain)
            .accessibilityHint(rowActivationHint)

            if isEditing {
                noteEditor
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            labelRow

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
                    .font(MacWikiTypography.settingsHelp)
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 3)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var labelRow: some View {
        HStack(spacing: 6) {
            Text(headerTitle)
                .font(MacWikiTypography.metadataLabel)
                .foregroundStyle(.secondary)
                .lineLimit(highlightHeaderWrap ? nil : 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(colorScheme == .dark ? 0.16 : 0.12), in: Capsule())

            Spacer(minLength: 4)

            Text(shortRelativeAge)
                .font(MacWikiTypography.compactRowMetadata)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            quickActionButtons

            Spacer(minLength: 0)
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
                requestHighlightRehydrate()
            } label: {
                SwiftUI.Label("Retry Highlight", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(appState.isHighlightRehydrateInProgress)

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

        Section("Change Color") {
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        highlight.color = color
                        highlight.updatedAt = Date()
                        modelContext.saveReportingFailure(operation: #function)
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
                systemImage: "pencil"
            ) {
                editedNote = highlight.note ?? ""
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                    isEditing = true
                }
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 22, height: 22)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
            }
            .buttonStyle(.plain)

            Button("Jump to Highlight", systemImage: "arrow.down.left") {
                jumpToHighlight()
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 22, height: 22)
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
        if isSelected {
            return highlight.color.swiftUIColor.opacity(colorScheme == .dark ? 0.28 : 0.20)
        }

        if isHovered {
            return highlight.color.swiftUIColor.opacity(colorScheme == .dark ? 0.20 : 0.14)
        }

        return highlight.color.swiftUIColor.opacity(colorScheme == .dark ? 0.13 : 0.08)
    }

    private var selectionStrokeWidth: CGFloat {
        1.4
    }

    private var selectionStrokeColor: Color {
        highlight.color.accentColor.opacity(0.68)
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

    private var headerTitle: String {
        if let section = highlight.sectionTitle,
           !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return section
        }
        return "Overview"
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Note")
                    .font(MacWikiTypography.metadataLabel)
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
                    .accessibilityLabel("Highlight note")
                    .accessibilityIdentifier("highlight-note-editor")
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
                    modelContext.saveReportingFailure(operation: #function)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isEditing = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func restoreHighlight() {
        highlight.isArchived = false
        highlight.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
    }

    private func requestHighlightRehydrate() {
        appState.pendingHighlightRehydrate = AppState.HighlightRehydrateRequest(highlight: highlight)
        appState.lastHighlightRehydrateResult = nil
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
