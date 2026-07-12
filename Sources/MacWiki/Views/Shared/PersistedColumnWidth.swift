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
