import SwiftUI

struct FindOnPageBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    let tabID: UUID
    let availableWidth: CGFloat

    @FocusState private var isFieldFocused: Bool
    @State private var findTask: Task<Void, Never>?

    private enum Metrics {
        static let cornerRadius: CGFloat = 12
        static let regularFieldWidth: CGFloat = 240
        static let compactFieldWidth: CGFloat = 170
        static let minimumFieldWidth: CGFloat = 96
        static let compactLayoutThreshold: CGFloat = 560
        static let compactReservedWidth: CGFloat = 190
        static let statusChipWidth: CGFloat = 70
        static let statusChipHeight: CGFloat = 20
        static let buttonSize: CGFloat = 26
        static let symbolSize: CGFloat = 12
        static let groupCornerRadius: CGFloat = 9
        static let fieldCornerRadius: CGFloat = 8
        static let horizontalPadding: CGFloat = 10
        static let verticalPadding: CGFloat = 8
        static let debounceMs: UInt64 = 120
    }

    private var trimmedQuery: String {
        appState.findOnPageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasQuery: Bool {
        !trimmedQuery.isEmpty
    }

    private var isCompactLayout: Bool {
        availableWidth < Metrics.compactLayoutThreshold
    }

    private var resolvedFieldWidth: CGFloat {
        if isCompactLayout {
            let compactWidth = min(
                Metrics.compactFieldWidth,
                max(Metrics.minimumFieldWidth, availableWidth - Metrics.compactReservedWidth)
            )
            return compactWidth
        }
        return Metrics.regularFieldWidth
    }

    private var statusText: String? {
        guard hasQuery else { return nil }
        if let found = appState.findOnPageMatchFound, !found {
            return "No match"
        }
        if let matchCount = appState.findOnPageMatchCount {
            return "\(matchCount)"
        }
        return nil
    }

    private var findQueryBinding: Binding<String> {
        Binding(
            get: { appState.findOnPageQuery },
            set: { appState.findOnPageQuery = $0 }
        )
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

    private var isKeyWindow: Bool {
        appearsActive
    }

    @ViewBuilder
    private var statusChip: some View {
        Group {
            if let statusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(statusChipForegroundStyle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(statusChipBackground)
                    .frame(width: Metrics.statusChipWidth, height: Metrics.statusChipHeight)
            } else {
                Color.clear
                    .frame(width: Metrics.statusChipWidth, height: Metrics.statusChipHeight)
            }
        }
    }

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 8) {
            searchFieldGroup

            if !isCompactLayout {
                statusChip
            }

            actionGroup
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .background(findBarBackground)
        .shadow(
            color: .black.opacity(
                isKeyWindow && !accessibilityPersonalization.reduceTransparency
                    ? (colorScheme == .dark ? 0.16 : 0.06)
                    : 0
            ),
            radius: 10,
            x: 0,
            y: 4
        )
        .frame(maxWidth: max(0, availableWidth), alignment: .trailing)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            isFieldFocused = true
        }
        .onChange(of: appState.findOnPageFocusRequestID) { _, requestID in
            guard requestID != nil else { return }
            isFieldFocused = true
        }
        .onExitCommand {
            dismiss()
        }
        .onDisappear {
            findTask?.cancel()
            findTask = nil
        }
    }

    private var searchFieldGroup: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Find in page", text: findQueryBinding)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .frame(width: resolvedFieldWidth)
                .onSubmit {
                    findNext()
                }
                .onChange(of: appState.findOnPageQuery) { _, newValue in
                    scheduleFind(for: newValue)
                }

            Button("Clear", systemImage: "xmark.circle.fill", action: clearQuery)
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .buttonStyle(.plain)
                .help("Clear")
                .opacity(hasQuery ? 1 : 0)
                .allowsHitTesting(hasQuery)
                .accessibilityHidden(!hasQuery)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(searchFieldBackground)
    }

    private var actionGroup: some View {
        HStack(spacing: 2) {
            Button("Previous", systemImage: "chevron.up", action: findPrevious)
                .labelStyle(.iconOnly)
                .font(.system(size: Metrics.symbolSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .buttonStyle(.plain)
                .help("Previous")

            Button("Next", systemImage: "chevron.down", action: findNext)
                .labelStyle(.iconOnly)
                .font(.system(size: Metrics.symbolSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .buttonStyle(.plain)
                .help("Next")

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                .frame(width: 0.5, height: 16)
                .padding(.horizontal, 2)

            Button("Done", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                .buttonStyle(.plain)
                .help("Done")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background(actionGroupBackground)
    }

    @ViewBuilder
    private var findBarBackground: some View {
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
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.10 : 0.06))
                }
                .overlay {
                    shape.strokeBorder(
                        Color.primary.opacity(
                            (colorScheme == .dark ? 0.09 : 0.055) + (increasedContrast ? 0.14 : 0)
                        ),
                        lineWidth: increasedContrast ? 1 : 0.52
                    )
                }
        }
    }

    private var searchFieldBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.fieldCornerRadius, style: .continuous)
            .fill(
                Color(nsColor: accessibilityPersonalization.reduceTransparency ? .controlBackgroundColor : .windowBackgroundColor)
                    .opacity(accessibilityPersonalization.reduceTransparency ? 1 : (colorScheme == .dark ? 0.12 : 0.065))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.fieldCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(increasedContrast ? 0.24 : (colorScheme == .dark ? 0.050 : 0.032)),
                        lineWidth: increasedContrast ? 1 : 0.45
                    )
            }
    }

    private var actionGroupBackground: some View {
        RoundedRectangle(cornerRadius: Metrics.groupCornerRadius, style: .continuous)
            .fill(
                Color(nsColor: accessibilityPersonalization.reduceTransparency ? .controlBackgroundColor : .windowBackgroundColor)
                    .opacity(accessibilityPersonalization.reduceTransparency ? 1 : (colorScheme == .dark ? 0.10 : 0.055))
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.groupCornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(increasedContrast ? 0.24 : (colorScheme == .dark ? 0.048 : 0.030)),
                        lineWidth: increasedContrast ? 1 : 0.45
                    )
            }
    }

    private var statusChipForegroundStyle: Color {
        if let found = appState.findOnPageMatchFound, !found {
            return .primary.opacity(colorScheme == .dark ? 0.84 : 0.72)
        }
        return .secondary
    }

    private var statusChipBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(statusChipFillOpacity)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        statusChipStrokeColor,
                        lineWidth: increasedContrast ? 1 : 0.45
                    )
            }
    }

    private var statusChipFillOpacity: Double {
        if let found = appState.findOnPageMatchFound, !found {
            return colorScheme == .dark ? 0.16 : 0.10
        }
        return colorScheme == .dark ? 0.10 : 0.055
    }

    private var statusChipStrokeColor: Color {
        if let found = appState.findOnPageMatchFound, !found {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.10)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.048 : 0.030)
    }

    private func scheduleFind(for query: String) {
        findTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appState.findOnPageMatchFound = nil
            appState.findOnPageMatchCount = nil
            issueFind(query: "", backwards: false)
            return
        }

        appState.findOnPageMatchFound = nil
        appState.findOnPageMatchCount = nil
        findTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Metrics.debounceMs * 1_000_000)
            guard !Task.isCancelled else { return }
            issueFind(query: trimmed, backwards: false)
        }
    }

    private func clearQuery() {
        appState.findOnPageQuery = ""
        appState.clearFindOnPageResults()
        issueFind(query: "", backwards: false)
    }

    private func issueFind(query: String, backwards: Bool) {
        appState.issueFindOnPageRequest(
            tabID: tabID,
            query: query,
            backwards: backwards
        )
    }

    private func findNext() {
        let trimmed = appState.findOnPageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.findOnPageMatchFound = nil
        issueFind(query: trimmed, backwards: false)
    }

    private func findPrevious() {
        let trimmed = appState.findOnPageQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.findOnPageMatchFound = nil
        issueFind(query: trimmed, backwards: true)
    }

    private func dismiss() {
        findTask?.cancel()
        findTask = nil

        appState.dismissFindOnPage(activeTabID: tabID, clearsWebSelection: true)
    }
}
