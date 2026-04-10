import Foundation
import SwiftUI

struct DiscoverPageViewsPopoverPayload {
    let rowKey: String
    let title: String
    let initialPulse: WikipediaService.TrendPulse?
    let referenceDate: Date
}

struct DiscoverPageViewsPopoverContent: View {
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
        selectedRange.requestedDays(relativeTo: referenceDate)
    }

    private var loadKey: String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endStamp = Int(referenceDate.timeIntervalSinceReferenceDate)
        return "\(normalizedTitle)|\(endStamp)|\(selectedRange.rawValue)|\(requestedDays)"
    }

    var body: some View {
        Group {
            if let pulse {
                TrendPulsePopoverView(title: title, pulse: pulse, selectedRange: $selectedRange)
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
                referenceDate: referenceDate,
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

struct DiscoverSparkline: View {
    let points: [Int]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let minValue = CGFloat(points.min() ?? 0)
            let maxValue = CGFloat(points.max() ?? 1)
            let range = max(maxValue - minValue, 1)
            let count = max(points.count, 2)

            let chartPoints: [CGPoint] = points.enumerated().map { index, value in
                let x = (CGFloat(index) / CGFloat(count - 1)) * width
                let normalizedY = (CGFloat(value) - minValue) / range
                let y = height - (normalizedY * height)
                return CGPoint(x: x, y: y)
            }

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    path.addLine(to: CGPoint(x: width, y: height))
                }
                .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1))

                if chartPoints.count >= 2 {
                    Path { path in
                        path.move(to: chartPoints[0])
                        for point in chartPoints.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }

                if let last = chartPoints.last {
                    Circle()
                        .fill(tint)
                        .frame(width: 3.5, height: 3.5)
                        .position(last)
                }
            }
        }
    }
}
