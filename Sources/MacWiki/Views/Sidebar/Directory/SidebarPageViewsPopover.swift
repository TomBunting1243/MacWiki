import SwiftUI

struct SidebarPageViewsPopoverPayload {
    let rowKey: String
    let title: String
    let initialPulse: WikipediaService.TrendPulse?
    let referenceDate: Date
}

struct SidebarPageViewsPopoverContent: View {
    let title: String
    let referenceDate: Date
    let initialPulse: WikipediaService.TrendPulse?

    @State private var pulse: WikipediaService.TrendPulse?
    @State private var isLoading = false
    @State private var didFailLoad = false
    @State private var selectedRange: ViewsPopoverTimeRange

    init(
        title: String,
        referenceDate: Date,
        initialPulse: WikipediaService.TrendPulse? = nil
    ) {
        self.title = title
        self.referenceDate = referenceDate
        self.initialPulse = initialPulse
        _pulse = State(initialValue: initialPulse)
        _selectedRange = State(initialValue: ViewsPopoverTimeRange.matching(days: initialPulse?.points.count ?? 30))
    }

    private var requestedDays: Int {
        presentationContext.requestedDays
    }

    private var presentationContext: DiscoverPageViewsPresentationContext {
        DiscoverPageViewsPresentationContext(
            selectedDate: referenceDate,
            selectedRange: selectedRange
        )
    }

    private var loadKey: String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endStamp = Int(presentationContext.historyEndDate.timeIntervalSinceReferenceDate)
        return "\(normalizedTitle)|\(endStamp)|\(selectedRange.rawValue)|\(requestedDays)"
    }

    var body: some View {
        Group {
            if let pulse {
                TrendPulsePopoverView(
                    title: title,
                    pulse: pulse,
                    selectedRange: $selectedRange,
                    presentationContext: presentationContext
                )
            } else if isLoading {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Views")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    AppLoadingInlineLabel(
                        text: "Loading page views…",
                        tone: .accent,
                        font: .system(size: 12, weight: .medium)
                    )
                }
                .padding(14)
                .frame(width: 300, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Views")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    Text(didFailLoad ? "Page views are unavailable for this article right now." : "No pageview data yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task {
                            await loadPulse()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(width: 300, alignment: .leading)
            }
        }
        .task(id: loadKey) {
            await loadPulseIfNeeded()
        }
    }

    @MainActor
    private func loadPulseIfNeeded() async {
        await loadPulse()
    }

    @MainActor
    private func loadPulse() async {
        isLoading = true
        didFailLoad = false
        defer { isLoading = false }

        do {
            let fetched = try await WikipediaService.shared.fetchTrendPulse(
                for: title,
                referenceDate: presentationContext.historyEndDate,
                days: requestedDays
            )
            guard !Task.isCancelled else { return }
            pulse = fetched
        } catch {
            guard !Task.isCancelled else { return }
            didFailLoad = true
        }
    }
}
