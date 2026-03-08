import SwiftUI
import AppKit

struct WindowToolbarTrackingSeparators: NSViewRepresentable {
    let sidebarVisible: Bool
    let inspectorVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.sidebarVisible = sidebarVisible
        context.coordinator.inspectorVisible = inspectorVisible
        context.coordinator.configure(for: nsView.window)
    }

    final class TrackingView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.configure(for: window)
        }
    }

    @MainActor
    final class Coordinator {
        private enum ToolbarAnchor {
            static let sidebar = NSToolbarItem.Identifier("sidebar")
            static let inspectorBoundary = NSToolbarItem.Identifier("inspector-boundary")
        }

        var sidebarVisible = true
        var inspectorVisible = true

        func configure(for window: NSWindow?) {
            guard let window, let toolbar = window.toolbar else { return }

            window.styleMask.insert(.fullSizeContentView)

            synchronize(
                toolbar: toolbar,
                identifier: .sidebarTrackingSeparator,
                after: ToolbarAnchor.sidebar,
                isEnabled: sidebarVisible
            )

            synchronize(
                toolbar: toolbar,
                identifier: .inspectorTrackingSeparator,
                after: ToolbarAnchor.inspectorBoundary,
                isEnabled: inspectorVisible
            )
        }

        private func synchronize(
            toolbar: NSToolbar,
            identifier: NSToolbarItem.Identifier,
            after anchor: NSToolbarItem.Identifier,
            isEnabled: Bool
        ) {
            let existingIndex = toolbar.items.firstIndex { $0.itemIdentifier == identifier }
            guard isEnabled,
                  let anchorIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == anchor }) else {
                if let existingIndex {
                    toolbar.removeItem(at: existingIndex)
                }
                return
            }

            let desiredIndex = anchorIndex + 1

            if let existingIndex {
                guard existingIndex != desiredIndex else { return }
                toolbar.removeItem(at: existingIndex)
                let adjustedIndex = min(
                    max(0, existingIndex < desiredIndex ? desiredIndex - 1 : desiredIndex),
                    toolbar.items.count
                )
                toolbar.insertItem(withItemIdentifier: identifier, at: adjustedIndex)
            } else {
                toolbar.insertItem(
                    withItemIdentifier: identifier,
                    at: min(desiredIndex, toolbar.items.count)
                )
            }
        }
    }
}
