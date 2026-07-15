import SwiftUI

enum MainWindowColumnWidth {
    static let sidebarRange: ClosedRange<CGFloat> = 176...260
    static let directoryRange: ClosedRange<CGFloat> = 260...420
    static let inspectorRange: ClosedRange<CGFloat> = 270...460

    static func clampedStorageValue(
        _ width: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> Double? {
        guard width.isFinite, width > 0 else { return nil }
        let clamped = min(max(width, range.lowerBound), range.upperBound)
        return Double(clamped)
    }
}

enum MainWindowLayout {
    /// A readable article should remain the dominant surface when auxiliary
    /// columns compete for space.
    static let minimumReaderWidth: CGFloat = 520
    /// A stable minimum avoids resizing the window when auxiliary panes open.
    /// Native split and inspector containers adapt their own columns above it.
    static let minimumWindowWidth: CGFloat = 720
    static let minimumContentHeight: CGFloat = 520
    static let dividerThickness: CGFloat = 1

    static func minimumContentWidth(
        listsSidebarVisible: Bool,
        directoryVisible: Bool,
        inspectorVisible: Bool
    ) -> CGFloat {
        let visibleAuxiliaryWidths = [
            listsSidebarVisible ? MainWindowColumnWidth.sidebarRange.lowerBound : 0,
            directoryVisible ? MainWindowColumnWidth.directoryRange.lowerBound : 0,
            inspectorVisible ? MainWindowColumnWidth.inspectorRange.lowerBound : 0
        ]
        let visibleAuxiliaryCount = [
            listsSidebarVisible,
            directoryVisible,
            inspectorVisible
        ].filter { $0 }.count

        return minimumReaderWidth
            + visibleAuxiliaryWidths.reduce(0, +)
            + (CGFloat(visibleAuxiliaryCount) * dividerThickness)
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
                        .task(id: proxy.size.width) {
                            try? await Task.sleep(for: .milliseconds(200))
                            guard !Task.isCancelled else { return }
                            persist(proxy.size.width)
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
        modifier(PersistedColumnWidthModifier(
            key: key,
            range: range,
            tolerance: tolerance
        ))
    }
}
