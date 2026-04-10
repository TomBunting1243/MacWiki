import SwiftUI

struct ReaderChromeMetrics: Equatable {
    var topObscuredHeight: CGFloat
    var topChromeVisible: Bool
    var titlebarTabStripVisible: Bool
    var titlebarTabStripHeight: CGFloat

    static let hidden = ReaderChromeMetrics(
        topObscuredHeight: 0,
        topChromeVisible: false,
        titlebarTabStripVisible: false,
        titlebarTabStripHeight: 0
    )
}

private struct ReaderChromeMetricsKey: EnvironmentKey {
    static let defaultValue = ReaderChromeMetrics.hidden
}

extension EnvironmentValues {
    var readerChromeMetrics: ReaderChromeMetrics {
        get { self[ReaderChromeMetricsKey.self] }
        set { self[ReaderChromeMetricsKey.self] = newValue }
    }
}
