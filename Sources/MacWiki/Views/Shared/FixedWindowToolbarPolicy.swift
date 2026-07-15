import AppKit
import SwiftUI

/// SwiftUI does not expose every macOS window-toolbar primitive. This narrow
/// platform boundary leaves Reader item creation and placement in SwiftUI,
/// disables editing for the fixed layout, and installs AppKit's standard
/// Inspector separator/toggle so the Inspector owns its titlebar section.
struct FixedWindowToolbarPolicy: NSViewRepresentable {
    func makeNSView(context: Context) -> FixedWindowToolbarPolicyView {
        FixedWindowToolbarPolicyView()
    }

    func updateNSView(_ nsView: FixedWindowToolbarPolicyView, context: Context) {
        nsView.enforcePolicy()
    }
}

final class FixedWindowToolbarPolicyView: NSView {
    private var isEnforcingPolicy = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didUpdateNotification,
            object: nil
        )

        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
        }

        enforcePolicy()
    }

    override func layout() {
        super.layout()
        enforcePolicy()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    fileprivate func enforcePolicy() {
        guard !isEnforcingPolicy, let toolbar = window?.toolbar else { return }
        isEnforcingPolicy = true
        defer { isEnforcingPolicy = false }

        if toolbar.allowsUserCustomization {
            toolbar.allowsUserCustomization = false
        }
        if toolbar.autosavesConfiguration {
            toolbar.autosavesConfiguration = false
        }
        if toolbar.allowsDisplayModeCustomization {
            toolbar.allowsDisplayModeCustomization = false
        }

        installStandardInspectorSection(in: toolbar)
    }

    private func installStandardInspectorSection(in toolbar: NSToolbar) {
        let separator = NSToolbarItem.Identifier.inspectorTrackingSeparator
        let toggle = NSToolbarItem.Identifier.toggleInspector

        if !toolbar.items.contains(where: { $0.itemIdentifier == toggle }) {
            toolbar.insertItem(withItemIdentifier: toggle, at: toolbar.items.count)
        }

        guard let toggleIndex = toolbar.items.firstIndex(where: {
            $0.itemIdentifier == toggle
        }) else {
            return
        }

        if !toolbar.items.contains(where: { $0.itemIdentifier == separator }) {
            toolbar.insertItem(withItemIdentifier: separator, at: toggleIndex)
        }
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        enforcePolicy()
    }
}
