import SwiftUI

struct FindOnPageBarView: View {
    @Environment(AppState.self) private var appState
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

    @ViewBuilder
    private var statusChip: some View {
        Group {
            if let statusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary)
                    )
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Find in page", text: $appState.findOnPageQuery)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .frame(width: resolvedFieldWidth)
                .onSubmit {
                    findNext()
                }
                .onChange(of: appState.findOnPageQuery) { _, newValue in
                    scheduleFind(for: newValue)
                }

            Button {
                appState.findOnPageQuery = ""
                appState.findOnPageMatchFound = nil
                appState.findOnPageMatchCount = nil
                issueFind(query: "", backwards: false)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
            }
            .buttonStyle(.plain)
            .help("Clear")
            .opacity(hasQuery ? 1 : 0)
            .allowsHitTesting(hasQuery)
            .accessibilityHidden(!hasQuery)

            if !isCompactLayout {
                statusChip
            }

            Button {
                findPrevious()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: Metrics.symbolSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
            }
            .buttonStyle(.plain)
            .help("Previous")

            Button {
                findNext()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: Metrics.symbolSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
            }
            .buttonStyle(.plain)
            .help("Next")

            Divider()
                .frame(height: 16)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
            }
            .buttonStyle(.plain)
            .help("Done")
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 6)
        .frame(maxWidth: max(0, availableWidth), alignment: .trailing)
        .onAppear {
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
        .onExitCommand {
            dismiss()
        }
        .onDisappear {
            findTask?.cancel()
            findTask = nil
        }
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

    private func issueFind(query: String, backwards: Bool) {
        appState.pendingFindOnPageRequest = AppState.FindOnPageRequest(
            requestID: UUID(),
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

        appState.showFindOnPage = false
        appState.findOnPageQuery = ""
        appState.findOnPageMatchFound = nil
        appState.findOnPageMatchCount = nil
        issueFind(query: "", backwards: false)
    }
}
