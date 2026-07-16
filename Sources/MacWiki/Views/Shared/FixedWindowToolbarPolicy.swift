import AppKit
import SwiftUI

/// SwiftUI does not expose every macOS window-toolbar primitive. This narrow
/// platform boundary leaves Reader item creation and placement in SwiftUI,
/// disables editing for the fixed layout, and can install AppKit's standard
/// Inspector toggle followed by its tracking separator. That native ordering
/// keeps the collapse control at the Reader's trailing edge while the Inspector
/// owns the full-height section beyond the divider.
struct FixedWindowToolbarPolicy: NSViewRepresentable {
    var installsInspectorSection = true

    func makeNSView(context: Context) -> FixedWindowToolbarPolicyView {
        FixedWindowToolbarPolicyView(installsInspectorSection: installsInspectorSection)
    }

    func updateNSView(_ nsView: FixedWindowToolbarPolicyView, context: Context) {
        nsView.installsInspectorSection = installsInspectorSection
        nsView.enforcePolicy()
    }
}

final class FixedWindowToolbarPolicyView: NSView {
    var installsInspectorSection: Bool
    private var isEnforcingPolicy = false

    init(installsInspectorSection: Bool) {
        self.installsInspectorSection = installsInspectorSection
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

        if installsInspectorSection {
            installStandardInspectorSection(in: toolbar)
        }
    }

    private func installStandardInspectorSection(in toolbar: NSToolbar) {
        let separator = NSToolbarItem.Identifier.inspectorTrackingSeparator
        let toggle = NSToolbarItem.Identifier.toggleInspector
        let identifiers = toolbar.items.map(\.itemIdentifier)

        if identifiers.suffix(2) == [toggle, separator] {
            return
        }

        if let separatorIndex = toolbar.items.firstIndex(where: {
            $0.itemIdentifier == separator
        }) {
            toolbar.removeItem(at: separatorIndex)
        }
        if let toggleIndex = toolbar.items.firstIndex(where: {
            $0.itemIdentifier == toggle
        }) {
            toolbar.removeItem(at: toggleIndex)
        }

        toolbar.insertItem(withItemIdentifier: toggle, at: toolbar.items.count)
        toolbar.insertItem(withItemIdentifier: separator, at: toolbar.items.count)
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        enforcePolicy()
    }
}
