import SwiftUI
import SwiftData

/// Floating toolbar that appears when text is selected in the article
struct HighlightToolbar: View {
    let selectionData: TextSelectionData
    let articleTitle: String
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedColor: HighlightColor = .yellow
    @State private var isHoveringColor: HighlightColor?

    var body: some View {
        VStack(spacing: 0) {
            colorPickerView
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
    }

    private var colorPickerView: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        selectedColor = color
                        createHighlight(color: color)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: 16, height: 16)

                            Circle()
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: selectedColor == color ? 1.5 : 0)
                                .frame(width: 18, height: 18)
                                .opacity(selectedColor == color ? 1 : 0)
                        }
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHoveringColor = hovering ? color : nil
                        }
                    }
                    .overlay {
                        Circle()
                            .stroke(color.swiftUIColor.opacity(0.4), lineWidth: 1)
                            .frame(width: 22, height: 22)
                            .opacity(isHoveringColor == color ? 1 : 0)
                    }
                    .help("Highlight \(color.rawValue.lowercased())")
                }
            }

            Divider()
                .frame(height: 18)

            Button {
                createHighlight(color: selectedColor, openNoteEditor: true)
            } label: {
                Image(systemName: "note.text")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Add note")

            Button {
                copyToClipboard()
                onDismiss()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Copy selection")

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    private func createHighlight(color: HighlightColor, openNoteEditor: Bool = false) {
        let highlight = Highlight(
            text: selectionData.text,
            articleTitle: articleTitle,
            elementPath: selectionData.elementPath,
            startOffset: selectionData.startOffset,
            length: selectionData.length,
            contextBefore: selectionData.contextBefore,
            contextAfter: selectionData.contextAfter,
            sectionTitle: selectionData.sectionTitle,
            color: color
        )

        modelContext.insert(highlight)

        do {
            try modelContext.save()
            // Signal WebView to immediately highlight current selection
            appState.pendingImmediateHighlight = AppState.ImmediateHighlightRequest(
                id: highlight.id,
                cssColor: color.cssColor
            )
            if openNoteEditor {
                appState.selectedHighlightId = highlight.id.uuidString
                appState.highlightTagFilterId = nil
                appState.inspectorMode = .notes
                appState.inspectorVisible = true
                appState.pendingHighlightNoteEditorRequest = AppState.HighlightNoteEditorRequest(
                    requestID: UUID(),
                    highlightID: highlight.id
                )
            }
        } catch {
            // Keep this silent in UI; save failures are non-fatal for interaction flow.
        }

        onDismiss()
    }

    private func copyToClipboard() {
        _ = SystemBridge.copyText(selectionData.text)
    }
}

/// Overlay view that shows the highlight toolbar positioned near the selection
struct HighlightToolbarOverlay: View {
    @Environment(AppState.self) private var appState
    let articleTitle: String

    // Track toolbar size for better positioning
    @State private var toolbarSize: CGSize = CGSize(width: 220, height: 48)

    var body: some View {
        GeometryReader { geometry in
            if let selection = appState.currentTextSelection {
                HighlightToolbar(
                    selectionData: selection,
                    articleTitle: articleTitle,
                    onDismiss: {
                        appState.currentTextSelection = nil
                    }
                )
                .background {
                    GeometryReader { toolbarGeometry in
                        Color.clear.onAppear {
                            toolbarSize = toolbarGeometry.size
                        }
                        .onChange(of: toolbarGeometry.size) { _, newSize in
                            toolbarSize = newSize
                        }
                    }
                }
                .position(toolbarPosition(for: selection, in: geometry))
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9)).combined(with: .offset(y: 8)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: appState.currentTextSelection != nil)
    }

    private func toolbarPosition(for selection: TextSelectionData, in geometry: GeometryProxy) -> CGPoint {
        let padding: CGFloat = 12

        // Center horizontally on the selection, clamped to viewport
        var x = selection.rect.midX
        x = max(toolbarSize.width / 2 + padding, min(x, geometry.size.width - toolbarSize.width / 2 - padding))

        // Try to position above the selection first
        var y = selection.rect.minY - toolbarSize.height / 2 - padding

        // If not enough room above, position below
        if y - toolbarSize.height / 2 < padding {
            y = selection.rect.maxY + toolbarSize.height / 2 + padding

            // If also not enough room below, center vertically
            if y + toolbarSize.height / 2 > geometry.size.height - padding {
                y = geometry.size.height / 2
            }
        }

        return CGPoint(x: x, y: y)
    }
}

#Preview("Color Picker") {
    VStack {
        HighlightToolbar(
            selectionData: TextSelectionData(
                text: "This is some selected text that the user highlighted in the article they were reading.",
                elementPath: "section[1]/p[2]",
                startOffset: 10,
                length: 50,
                contextBefore: "context before ",
                contextAfter: " context after",
                sectionTitle: "Introduction",
                rect: CGRect(x: 100, y: 100, width: 200, height: 20)
            ),
            articleTitle: "Test Article",
            onDismiss: {}
        )
    }
    .padding(40)
    .background(.gray.opacity(0.2))
}

#Preview("Note Input") {
    VStack {
        HighlightToolbar(
            selectionData: TextSelectionData(
                text: "This is some selected text that the user highlighted in the article they were reading.",
                elementPath: "section[1]/p[2]",
                startOffset: 10,
                length: 50,
                contextBefore: "context before ",
                contextAfter: " context after",
                sectionTitle: "Introduction",
                rect: CGRect(x: 100, y: 100, width: 200, height: 20)
            ),
            articleTitle: "Test Article",
            onDismiss: {}
        )
    }
    .padding(40)
    .background(.gray.opacity(0.2))
}
