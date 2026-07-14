import OSLog
import SwiftUI
import SwiftData

private let highlightToolbarLogger = Logger(subsystem: "com.macwiki", category: "highlights")

/// Floating toolbar that appears when text is selected in the article
struct HighlightToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    let selectionData: TextSelectionData
    let articleTitle: String
    let onDismiss: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @State private var selectedColor: HighlightColor = .yellow
    @State private var isHoveringColor: HighlightColor?
    @State private var hoveredAction: HighlightToolbarAction?

    private enum Metrics {
        static let cornerRadius: CGFloat = 11
        static let groupCornerRadius: CGFloat = 8
        static let colorButtonSize: CGFloat = 22
        static let colorSwatchSize: CGFloat = 15
        static let actionButtonSize: CGFloat = 24
    }

    private enum HighlightToolbarAction {
        case addNote
        case copy
        case dismiss
    }

    var body: some View {
        colorPickerView
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(toolbarBackground)
            .shadow(
                color: .black.opacity(
                    accessibilityPersonalization.reduceTransparency
                        ? 0
                        : (colorScheme == .dark ? 0.32 : 0.16)
                ),
                radius: 16,
                x: 0,
                y: 8
            )
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
                                .fill(
                                    Color(nsColor: .windowBackgroundColor)
                                        .opacity(colorPlateOpacity(for: color))
                                )
                                .frame(width: Metrics.colorButtonSize, height: Metrics.colorButtonSize)

                            Circle()
                                .fill(color.swiftUIColor)
                                .frame(width: Metrics.colorSwatchSize, height: Metrics.colorSwatchSize)
                                .scaleEffect(isHoveringColor == color ? 1.08 : 1)
                                .shadow(
                                    color: color.swiftUIColor.opacity(isHoveringColor == color ? 0.34 : 0),
                                    radius: 4,
                                    x: 0,
                                    y: 1
                                )

                            Circle()
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: selectedColor == color ? 1.25 : 0)
                                .frame(width: Metrics.colorSwatchSize + 2, height: Metrics.colorSwatchSize + 2)
                                .opacity(selectedColor == color ? 1 : 0)
                        }
                        .frame(width: Metrics.colorButtonSize, height: Metrics.colorButtonSize)
                        .contentShape(Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(colorPlateStroke(for: color), lineWidth: 0.45)
                                .frame(width: Metrics.colorButtonSize, height: Metrics.colorButtonSize)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Highlight \(color.rawValue.lowercased())")
                    .accessibilityValue(selectedColor == color ? "Selected" : "")
                    .accessibilityHint("Creates a \(color.rawValue.lowercased()) highlight")
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            isHoveringColor = hovering ? color : nil
                        }
                    }
                    .help("Highlight \(color.rawValue.lowercased())")
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(controlGroupBackground)

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .frame(width: 0.5, height: 16)
                .padding(.horizontal, 2)

            actionGroup
        }
    }

    private var actionGroup: some View {
        HStack(spacing: 2) {
            toolbarActionButton(
                action: .addNote,
                systemImage: "pencil",
                helpText: "Add note"
            ) {
                createHighlight(color: selectedColor, openNoteEditor: true)
            }

            toolbarActionButton(
                action: .copy,
                systemImage: "doc.on.doc",
                helpText: "Copy selection"
            ) {
                copyToClipboard()
                onDismiss()
            }

            toolbarActionButton(
                action: .dismiss,
                systemImage: "xmark",
                helpText: "Dismiss",
                symbolWeight: .semibold,
                symbolSize: 11
            ) {
                onDismiss()
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(controlGroupBackground)
    }

    @ViewBuilder
    private var toolbarBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        if accessibilityPersonalization.reduceTransparency {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    shape.strokeBorder(
                        Color.primary.opacity(increasedContrast ? 0.34 : 0.14),
                        lineWidth: increasedContrast ? 1 : 0.6
                    )
                }
        } else if #available(macOS 26, *), usesNativeGlass {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cornerRadius))
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.022 : 0.014))
                }
                .overlay {
                    shape.strokeBorder(
                        Color.primary.opacity(
                            (colorScheme == .dark ? 0.070 : 0.046) + (increasedContrast ? 0.14 : 0)
                        ),
                        lineWidth: increasedContrast ? 1 : 0.52
                    )
                }
        } else {
            shape
                .fill(Color(nsColor: colorScheme == .dark ? .controlBackgroundColor : .windowBackgroundColor))
                .overlay {
                    shape.fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.02))
                }
                .overlay {
                    shape.strokeBorder(
                        Color.primary.opacity(
                            (colorScheme == .dark ? 0.18 : 0.10) + (increasedContrast ? 0.14 : 0)
                        ),
                        lineWidth: increasedContrast ? 1 : 0.7
                    )
                }
        }
    }

    private var usesNativeGlass: Bool {
        MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
        ) && !accessibilityPersonalization.reduceTransparency
    }

    private var increasedContrast: Bool {
        accessibilityPersonalization.colorSchemeContrast == .increased
    }

    private var controlGroupBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.groupCornerRadius, style: .continuous)
            .fill(
                Color(
                    nsColor: accessibilityPersonalization.reduceTransparency
                        ? .controlBackgroundColor
                        : (colorScheme == .dark ? .windowBackgroundColor : .controlBackgroundColor)
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.groupCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(
                            increasedContrast ? 0.24 : (colorScheme == .dark ? 0.18 : 0.10)
                        ),
                        lineWidth: increasedContrast ? 1 : 0.45
                    )
            }
    }

    private func colorPlateOpacity(for color: HighlightColor) -> Double {
        if selectedColor == color {
            return colorScheme == .dark ? 0.14 : 0.08
        }
        if isHoveringColor == color {
            return colorScheme == .dark ? 0.10 : 0.055
        }
        return 0
    }

    private func colorPlateStroke(for color: HighlightColor) -> Color {
        if selectedColor == color {
            return Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.045)
        }
        if isHoveringColor == color {
            return Color.primary.opacity(colorScheme == .dark ? 0.048 : 0.030)
        }
        return Color.clear
    }

    private func toolbarActionButton(
        action actionType: HighlightToolbarAction,
        systemImage: String,
        helpText: String,
        symbolWeight: Font.Weight = .medium,
        symbolSize: CGFloat = 13,
        perform action: @escaping () -> Void
    ) -> some View {
        Button(helpText, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityLabel(helpText)
            .font(.system(size: symbolSize, weight: symbolWeight))
            .foregroundStyle(hoveredAction == actionType ? .primary : .secondary)
            .frame(width: Metrics.actionButtonSize, height: Metrics.actionButtonSize)
            .background(actionBackground(for: actionType))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    hoveredAction = hovering ? actionType : (hoveredAction == actionType ? nil : hoveredAction)
                }
            }
    }

    private func actionBackground(for action: HighlightToolbarAction) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(hoveredAction == action ? (colorScheme == .dark ? 0.28 : 0.36) : 0)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        hoveredAction == action
                            ? Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12)
                            : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.055),
                        lineWidth: 0.45
                    )
            }
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
            highlightToolbarLogger.error("Failed to save highlight: \(error.localizedDescription, privacy: .public)")
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
