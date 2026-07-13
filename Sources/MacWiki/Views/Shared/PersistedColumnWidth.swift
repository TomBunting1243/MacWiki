import SwiftUI

enum MainWindowColumnWidth {
    static let sidebarRange: ClosedRange<CGFloat> = 176...260
    static let directoryRange: ClosedRange<CGFloat> = 260...420
    static let inspectorRange: ClosedRange<CGFloat> = 260...460

    static func clampedStorageValue(
        _ width: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> Double? {
        guard width.isFinite, width > 0 else { return nil }
        let clamped = min(max(width, range.lowerBound), range.upperBound)
        return Double(clamped)
    }
}

enum MainWindowResponsiveLayout {
    struct Input: Equatable {
        let windowWidth: CGFloat
        let sidebarVisible: Bool
        let directoryVisible: Bool
        let hasArticle: Bool
        let sidebarWidth: CGFloat
        let directoryWidth: CGFloat
        let inspectorWidth: CGFloat
    }

    /// A readable article should remain the dominant surface when auxiliary
    /// columns compete for space.
    static let minimumReaderWidth: CGFloat = 520
    private static let splitDividerWidth: CGFloat = 1

    static func canPresentInspector(for input: Input) -> Bool {
        guard input.hasArticle, input.windowWidth.isFinite else { return false }

        let sidebarWidth = input.sidebarVisible
            ? resolved(input.sidebarWidth, in: MainWindowColumnWidth.sidebarRange)
            : 0
        let directoryWidth = input.directoryVisible
            ? resolved(input.directoryWidth, in: MainWindowColumnWidth.directoryRange)
            : 0
        let inspectorWidth = resolved(input.inspectorWidth, in: MainWindowColumnWidth.inspectorRange)
        let visibleAuxiliaryColumns = [input.sidebarVisible, input.directoryVisible, true]
            .filter { $0 }
            .count
        let dividerBudget = CGFloat(visibleAuxiliaryColumns) * splitDividerWidth
        let requiredWidth = sidebarWidth
            + directoryWidth
            + inspectorWidth
            + minimumReaderWidth
            + dividerBudget

        return input.windowWidth >= requiredWidth
    }

    private static func resolved(_ value: CGFloat, in range: ClosedRange<CGFloat>) -> CGFloat {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct PersistedColumnWidthModifier: ViewModifier {
    let key: String
    let range: ClosedRange<CGFloat>
    let tolerance: Double

    @State private var lastMeasuredWidth: Double?

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            persist(proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            persist(newWidth)
                        }
                }
            }
    }

    private func persist(_ width: CGFloat) {
        guard let value = MainWindowColumnWidth.clampedStorageValue(width, range: range) else { return }
        guard lastMeasuredWidth.map({ abs($0 - value) >= tolerance }) ?? true else { return }

        let defaults = MacWikiDefaults.current
        let stored = defaults.object(forKey: key) as? Double
        if stored.map({ abs($0 - value) >= tolerance }) ?? true {
            defaults.set(value, forKey: key)
        }
        lastMeasuredWidth = value
    }
}

extension View {
    func persistedColumnWidth(
        key: String,
        range: ClosedRange<CGFloat>,
        tolerance: Double = 1.0
    ) -> some View {
        modifier(PersistedColumnWidthModifier(key: key, range: range, tolerance: tolerance))
    }
}
