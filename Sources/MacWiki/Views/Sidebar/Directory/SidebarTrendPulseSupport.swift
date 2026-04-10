import SwiftUI

struct SidebarTrendPulseChip: View {
    let pulse: WikipediaService.TrendPulse
    var onChartRequested: (() -> Void)? = nil

    private var deltaFraction: Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return Double(pulse.latestViews - previous) / Double(previous)
    }

    private var trendSymbol: String {
        guard let deltaFraction else { return "chart.line.uptrend.xyaxis" }
        return deltaFraction < 0 ? "chart.line.downtrend.xyaxis" : "chart.line.uptrend.xyaxis"
    }

    private var deltaText: String {
        ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews,
            fallback: "Views"
        )
    }

    private var viewsText: String {
        "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    private var tint: Color {
        guard let deltaFraction else { return .secondary }
        if deltaFraction > 0 { return Color.green.opacity(0.9) }
        if deltaFraction < 0 { return Color.red.opacity(0.85) }
        return .secondary
    }

    private var chipLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: trendSymbol)
                .font(.system(size: 9, weight: .semibold))
            Text(deltaText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(viewsText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 0.7)
        }
        .contentShape(Capsule())
    }

    var body: some View {
        Group {
            if let onChartRequested {
                Button(action: onChartRequested) {
                    chipLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(deltaText), \(viewsText)")
                .accessibilityHint("Show recent pageview chart")
            } else {
                chipLabel
            }
        }
        .help("Views from recent daily pageviews")
    }
}

enum ViewsPopoverTimeRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365
    case fiveYears = 1825
    case max = -1

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .year: return "1Y"
        case .fiveYears: return "5Y"
        case .max: return "Max"
        }
    }

    func requestedDays(relativeTo referenceDate: Date) -> Int {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)

        let resolvedStartDate: Date
        switch self {
        case .week:
            resolvedStartDate = calendar.date(byAdding: .day, value: -6, to: endDate) ?? endDate
        case .month:
            resolvedStartDate = calendar.date(byAdding: .day, value: -29, to: endDate) ?? endDate
        case .quarter:
            resolvedStartDate = calendar.date(byAdding: .day, value: -89, to: endDate) ?? endDate
        case .year:
            resolvedStartDate = calendar.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .fiveYears:
            resolvedStartDate = calendar.date(byAdding: .year, value: -5, to: endDate) ?? endDate
        case .max:
            resolvedStartDate = calendar.date(from: DateComponents(year: 2015, month: 7, day: 1)) ?? endDate
        }

        let daySpan = (calendar.dateComponents([.day], from: resolvedStartDate, to: endDate).day ?? 0) + 1
        return Swift.max(3, daySpan)
    }

    static func matching(days: Int) -> ViewsPopoverTimeRange {
        if days <= 7 { return .week }
        if days <= 30 { return .month }
        if days <= 90 { return .quarter }
        if days <= 366 { return .year }
        if days <= 1827 { return .fiveYears }
        return .max
    }
}

func abbreviatedViewCount(_ value: Int) -> String {
    let absValue = abs(Double(value))
    let sign = value < 0 ? "-" : ""

    if absValue >= 1_000_000_000 {
        return "\(sign)\((absValue / 1_000_000_000).formatted(.number.precision(.fractionLength(0...1))))B"
    }
    if absValue >= 1_000_000 {
        return "\(sign)\((absValue / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M"
    }
    if absValue >= 1_000 {
        return "\(sign)\((absValue / 1_000).formatted(.number.precision(.fractionLength(0...1))))K"
    }
    return "\(value)"
}
