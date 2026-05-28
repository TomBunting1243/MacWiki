import AppKit
import SwiftUI

struct WindowChromeConfigurator: NSViewRepresentable {
    var removesSystemSidebarToggle = true

    func makeNSView(context: Context) -> WindowChromeConfiguratorView {
        let view = WindowChromeConfiguratorView()
        view.removesSystemSidebarToggle = removesSystemSidebarToggle
        return view
    }

    func updateNSView(_ nsView: WindowChromeConfiguratorView, context: Context) {
        nsView.removesSystemSidebarToggle = removesSystemSidebarToggle
        nsView.scheduleWindowConfiguration()
    }
}

final class WindowChromeConfiguratorView: NSView {
    var removesSystemSidebarToggle = true

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleWindowConfiguration()
    }

    func scheduleWindowConfiguration() {
        let delays: [TimeInterval] = [0, 0.1, 0.35]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.configureWindowIfNeeded()
            }
        }
    }

    private func configureWindowIfNeeded() {
        guard removesSystemSidebarToggle, let toolbar = window?.toolbar else { return }

        for index in toolbar.items.indices.reversed()
            where shouldRemoveToolbarItem(toolbar.items[index]) {
            toolbar.removeItem(at: index)
        }
    }

    private func shouldRemoveToolbarItem(_ item: NSToolbarItem) -> Bool {
        let identifier = item.itemIdentifier.rawValue
        return item.itemIdentifier == .toggleSidebar
            || identifier.contains("navigationSplitView.toggleSidebar")
            || identifier.contains("SwiftUI.splitViewSeparator")
    }
}

extension View {
    func configuredMacWikiWindowChrome() -> some View {
        background(WindowChromeConfigurator().frame(width: 0, height: 0))
    }
}
