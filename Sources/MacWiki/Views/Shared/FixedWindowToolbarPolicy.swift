import AppKit
import SwiftUI

/// SwiftUI owns every toolbar item. This narrow AppKit boundary only disables
/// toolbar editing for the fixed internal-beta layout; it never inserts,
/// removes, reorders, or tracks an item.
struct FixedWindowToolbarPolicy: NSViewRepresentable {
    func makeNSView(context: Context) -> FixedWindowToolbarPolicyView {
        FixedWindowToolbarPolicyView()
    }

    func updateNSView(_ nsView: FixedWindowToolbarPolicyView, context: Context) {
        nsView.schedulePolicyApplication()
    }
}

final class FixedWindowToolbarPolicyView: NSView {
    private weak var configuredToolbar: NSToolbar?
    private var pendingApplication: Task<Void, Never>?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if configuredToolbar !== window?.toolbar {
            configuredToolbar = nil
        }
        schedulePolicyApplication()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            pendingApplication?.cancel()
            pendingApplication = nil
            configuredToolbar = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    deinit {
        pendingApplication?.cancel()
    }

    func schedulePolicyApplication() {
        guard configuredToolbar !== window?.toolbar,
              pendingApplication == nil else {
            return
        }

        pendingApplication = Task { @MainActor [weak self] in
            defer { self?.pendingApplication = nil }
            await Task.yield()
            self?.enforcePolicy()
        }
    }

    func enforcePolicy() {
        guard let toolbar = window?.toolbar,
              configuredToolbar !== toolbar else {
            return
        }

        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.allowsDisplayModeCustomization = false
        configuredToolbar = toolbar
    }
}
