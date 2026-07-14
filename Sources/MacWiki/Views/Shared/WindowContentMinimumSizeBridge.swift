import AppKit
import SwiftUI

/// Keeps the native window's resizing contract in sync with the panes the
/// user has chosen to show by updating the `NSWindow` that backs the declared
/// SwiftUI scene.
struct WindowContentMinimumSizeBridge: NSViewRepresentable {
    let minimumSize: CGSize

    func makeNSView(context: Context) -> WindowContentMinimumSizeView {
        WindowContentMinimumSizeView(minimumSize: minimumSize)
    }

    func updateNSView(_ view: WindowContentMinimumSizeView, context: Context) {
        view.minimumSize = minimumSize
    }
}

final class WindowContentMinimumSizeView: NSView {
    var minimumSize: CGSize {
        didSet { applyMinimumSize() }
    }

    init(minimumSize: CGSize) {
        self.minimumSize = minimumSize
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyMinimumSize()
    }

    private func applyMinimumSize() {
        guard let window else { return }
        let resolvedSize = NSSize(
            width: max(minimumSize.width, 1),
            height: max(minimumSize.height, 1)
        )
        guard window.contentMinSize != resolvedSize else { return }
        window.contentMinSize = resolvedSize
    }
}
