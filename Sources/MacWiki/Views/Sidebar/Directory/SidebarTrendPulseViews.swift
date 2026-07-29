import Charts
import SwiftUI
struct TrendPulsePopoverView: View {
    let title: String
    let pulse: WikipediaService.TrendPulse
    @Binding var selectedRange: ViewsPopoverTimeRange
    let presentationContext: DiscoverPageViewsPresentationContext
    @State private var selectedIndex: Int?
    @State private var peakDays: [WikipediaService.PeakPageviewDay] = []
    @State private var isLoadingPeakDays = false
    @State private var hoveredRecentPointID: Int?
    @State private var hoveredPeakDayID: String?
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    private enum Layout {
        static let chartHeight: CGFloat = 156
        static let chartEdgePadding: CGFloat = 10
        static let popoverWidth: CGFloat = 372
    }
    private var fullPoints: [TrendPulsePoint] {
        let calendar = Calendar.current
        return pulse.points.enumerated().map { index, views in
            let date = calendar.date(byAdding: .day, value: index, to: pulse.windowStart) ?? pulse.windowStart
            return TrendPulsePoint(id: index, date: date, views: views)
        }
    }
    private var chartPoints: [TrendPulsePoint] {
        TrendPulseDownsampler.points(fullPoints, maximumCount: 220)
    }
    private var selectedPoint: TrendPulsePoint? {
        if let selectedIndex {
            return fullPoints.first(where: { $0.id == selectedIndex }) ?? selectionAnchorPoint
        }
        return selectionAnchorPoint
    }
    private var latestViewsCompact: String {
        abbreviatedViewCount(pulse.latestViews)
    }

    private var materialPolicy: MacWikiGlassRuntime.SurfacePolicy {
        MacWikiGlassRuntime.surfacePolicy(
            isEnabled: false,
            forceLegacyFallback: false,
            personalization: accessibilityPersonalization
        )
    }

    private var selectedPointAccessibilityValue: String {
        guard let selectedPoint else { return "No page-view data" }
        let views = NumberFormatter.localizedString(
            from: NSNumber(value: selectedPoint.views),
            number: .decimal
        )
        return "\(selectedPoint.date.formatted(date: .long, time: .omitted)), \(views) views"
    }
    private var deltaText: String {
        ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews,
            fallback: "No previous-day delta",
            suffix: "vs previous day"
        )
    }
    private var deltaBadgeText: String {
        ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews
        )
    }
    private var deltaTint: Color {
        guard let previous = pulse.previousViews, previous > 0 else { return .secondary }
        let deltaFraction = Double(pulse.latestViews - previous) / Double(previous)
        if deltaFraction > 0 { return Color.green.opacity(0.9) }
        if deltaFraction < 0 { return Color.red.opacity(0.85) }
        return .secondary
    }
    private var windowLabel: String {
        "\(pulse.windowStart.formatted(date: .abbreviated, time: .omitted)) - \(pulse.windowEnd.formatted(date: .abbreviated, time: .omitted))"
    }
    private var xAxisDateFormat: Date.FormatStyle {
        switch selectedRange {
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.month(.abbreviated).day()
        case .quarter, .year:
            return .dateTime.month(.abbreviated)
        case .fiveYears, .max:
            return .dateTime.year()
        }
    }
    private var xAxisTickDates: [Date] {
        switch selectedRange {
        case .week:
            return generatedAxisTickDates(component: .day, step: 2)
        case .month:
            return generatedAxisTickDates(component: .day, step: 7)
        case .quarter:
            return generatedAxisTickDates(component: .month, step: 1)
        case .year:
            return generatedAxisTickDates(component: .month, step: 2)
        case .fiveYears:
            return generatedAxisTickDates(component: .year, step: 1)
        case .max:
            return generatedAxisTickDates(component: .year, step: maxAxisYearStride)
        }
    }
    private var maxAxisYearStride: Int {
        let calendar = Calendar.current
        let yearSpan = max(1, calendar.dateComponents([.year], from: pulse.windowStart, to: pulse.windowEnd).year ?? 1)
        switch yearSpan {
        case 1...8: return 1
        case 9...16: return 2
        case 17...30: return 5
        default: return 10
        }
    }
    private func generatedAxisTickDates(component: Calendar.Component, step: Int) -> [Date] {
        guard step > 0 else { return [pulse.windowStart, pulse.windowEnd] }
        let calendar = Calendar.current
        let start = pulse.windowStart
        let end = pulse.windowEnd
        guard start < end else { return [start] }
        var ticks: [Date] = [start]
        var cursor = start
        while let next = calendar.date(byAdding: component, value: step, to: cursor), next < end {
            ticks.append(next)
            cursor = next
        }
        if !calendar.isDate(ticks.last ?? start, inSameDayAs: end) {
            ticks.append(end)
        }
        return ticks
    }
    private var recentPoints: [TrendPulsePoint] {
        Array(fullPoints.suffix(5).reversed())
    }

    private var selectionAnchorPoint: TrendPulsePoint? {
        nearestPoint(to: presentationContext.selectionAnchorDate) ?? fullPoints.last
    }

    private var peakDaysTaskKey: String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endStamp = Int(presentationContext.allTimeHighDaysEndDate.timeIntervalSinceReferenceDate)
        return "\(normalizedTitle)|\(endStamp)"
    }

    private func pointIndex(matching date: Date) -> Int? {
        let calendar = Calendar.current
        return fullPoints.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.id
    }

    private func resetSelectionToAnchor() {
        selectedIndex = selectionAnchorPoint?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Views")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(selectedRange.shortLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Range", selection: $selectedRange) {
                ForEach(ViewsPopoverTimeRange.allCases) { option in
                    Text(option.shortLabel)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latestViewsCompact)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))

                Text("views")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(deltaBadgeText)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(deltaTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(deltaTint.opacity(0.1), in: Capsule())
            }

            Text(deltaText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Views", point.views)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Views", point.views)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("Date", selectedPoint.date))
                            .foregroundStyle(Color.primary.opacity(0.16))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

                        PointMark(
                            x: .value("Date", selectedPoint.date),
                            y: .value("Views", selectedPoint.views)
                        )
                        .symbolSize(24)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(height: Layout.chartHeight)
                .chartXScale(range: .plotDimension(startPadding: Layout.chartEdgePadding, endPadding: Layout.chartEdgePadding))
                .chartXAxis {
                    AxisMarks(values: xAxisTickDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(Color.primary.opacity(0.10))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(xAxisDateFormat))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(abbreviatedViewCount(intValue))
                            } else if let doubleValue = value.as(Double.self) {
                                Text(abbreviatedViewCount(Int(doubleValue.rounded())))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    updateSelection(location: location, proxy: proxy, geometry: geometry)
                                case .ended:
                                    resetSelectionToAnchor()
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateSelection(location: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
                .focusable()
                .onKeyPress(.leftArrow, phases: .down) { _ in
                    moveSelection(.previous)
                    return .handled
                }
                .onKeyPress(.rightArrow, phases: .down) { _ in
                    moveSelection(.next)
                    return .handled
                }
                .accessibilityLabel("Page views over time")
                .accessibilityValue(selectedPointAccessibilityValue)
                .accessibilityHint("Use Left and Right Arrow keys, or adjust the chart, to inspect each day.")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .decrement:
                        moveSelection(.previous)
                    case .increment:
                        moveSelection(.next)
                    @unknown default:
                        break
                    }
                }
                .background(chartBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(
                                accessibilityPersonalization.colorSchemeContrast == .increased ? 0.34 : 0.08
                            ),
                            lineWidth: accessibilityPersonalization.colorSchemeContrast == .increased ? 1 : 0.8
                        )
                }

                Text(windowLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let selectedPoint {
                HStack {
                    Text(selectedPoint.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer(minLength: 0)
                    Text("\(NumberFormatter.localizedString(from: NSNumber(value: selectedPoint.views), number: .decimal)) views")
                        .monospacedDigit()
                }
                .font(.system(size: 11.5, weight: .semibold))
            }

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 6) {
                Text(presentationContext.recencySectionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(recentPoints) { point in
                    let isHovered = hoveredRecentPointID == point.id
                    HStack(spacing: 8) {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(abbreviatedViewCount(point.views))
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isHovered ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onHover { hovering in
                        if hovering {
                            hoveredRecentPointID = point.id
                            hoveredPeakDayID = nil
                            selectedIndex = point.id
                        } else if hoveredRecentPointID == point.id {
                            hoveredRecentPointID = nil
                            resetSelectionToAnchor()
                        }
                    }
                }
            }

            if isLoadingPeakDays {
                Divider().opacity(0.45)
                AppLoadingInlineLabel(
                    text: "Loading all-time highs…",
                    tone: .accent,
                    font: .system(size: 10.5, weight: .medium)
                )
            } else if !peakDays.isEmpty {
                Divider().opacity(0.45)
                VStack(alignment: .leading, spacing: 6) {
                    Text("All-Time High Days")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(peakDays.enumerated()), id: \.offset) { index, peak in
                        let isHovered = hoveredPeakDayID == peak.id
                        HStack(spacing: 8) {
                            Text("#\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .leading)
                            Text(peak.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(abbreviatedViewCount(peak.views))
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(isHovered ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 0.8)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .onHover { hovering in
                            if hovering {
                                hoveredPeakDayID = peak.id
                                hoveredRecentPointID = nil
                                if let index = pointIndex(matching: peak.date) {
                                    selectedIndex = index
                                }
                            } else if hoveredPeakDayID == peak.id {
                                hoveredPeakDayID = nil
                                resetSelectionToAnchor()
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: Layout.popoverWidth)
        .task(id: peakDaysTaskKey) {
            await loadPeakDays()
        }
        .onChange(of: selectedRange) { _, _ in
            selectedIndex = nil
        }
        .onChange(of: pulse) { _, _ in
            selectedIndex = nil
        }
    }

    private func updateSelection(location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotRect = geometry[plotFrame]
        let xPosition = location.x - plotRect.origin.x
        guard xPosition >= 0, xPosition <= plotRect.width else { return }
        guard let hoveredDate: Date = proxy.value(atX: xPosition) else { return }

        if let nearest = fullPoints.min(by: { lhs, rhs in
            abs(lhs.date.timeIntervalSince(hoveredDate)) < abs(rhs.date.timeIntervalSince(hoveredDate))
        }) {
            selectedIndex = nearest.id
        }
    }

    private func moveSelection(_ direction: TrendPulseSelectionPolicy.Direction) {
        selectedIndex = TrendPulseSelectionPolicy.selection(
            from: selectedIndex,
            anchorID: selectionAnchorPoint?.id,
            in: fullPoints,
            moving: direction
        )
    }

    @ViewBuilder
    private var chartBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if materialPolicy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else {
            shape.fill(.regularMaterial)
        }
    }

    private func loadPeakDays() async {
        isLoadingPeakDays = true
        defer { isLoadingPeakDays = false }

        do {
            let result = try await WikipediaService.shared.fetchPeakPageviewDays(
                for: title,
                endingAt: presentationContext.allTimeHighDaysEndDate,
                top: 5
            )
            guard !Task.isCancelled else { return }
            peakDays = result
        } catch {
            guard !Task.isCancelled else { return }
            peakDays = []
        }
    }

    private func nearestPoint(to targetDate: Date) -> TrendPulsePoint? {
        fullPoints.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(targetDate)) < abs(rhs.date.timeIntervalSince(targetDate))
        }
    }
}
