import AppKit
import SwiftUI

enum WorkspaceCloseShortcutDisposition: Equatable {
    case closeTab
    case ignore
    case closeWindow

    static func resolve(hasActiveTab: Bool, navigationLocked: Bool) -> Self {
        guard hasActiveTab else { return .closeWindow }
        return navigationLocked ? .ignore : .closeTab
    }
}

/// Gives the tabbed workspace first refusal on its own Command-W event.
///
/// SwiftUI's `Window` scene keeps a native Close Window key equivalent even
/// when the visible File command group is replaced. This window-local bridge
/// consumes only an unmodified Command-W while a workspace tab owns the close
/// action; every other event continues through the native responder chain.
struct WorkspaceCloseShortcutBridge: NSViewRepresentable {
    let disposition: () -> WorkspaceCloseShortcutDisposition
    let closeTab: () -> Void

    func makeNSView(context: Context) -> WorkspaceCloseShortcutBridgeView {
        let view = WorkspaceCloseShortcutBridgeView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: WorkspaceCloseShortcutBridgeView, context: Context) {
        update(nsView)
    }

    private func update(_ view: WorkspaceCloseShortcutBridgeView) {
        view.disposition = disposition
        view.closeTab = closeTab
    }
}

final class WorkspaceCloseShortcutBridgeView: NSView {
    var disposition: () -> WorkspaceCloseShortcutDisposition = { .closeWindow }
    var closeTab: () -> Void = {}

    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installMonitorIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func installMonitorIfNeeded() {
        guard window != nil, eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  NSApp.keyWindow === self.window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "w" else {
                return event
            }

            switch self.disposition() {
            case .closeTab:
                self.closeTab()
                return nil
            case .ignore:
                return nil
            case .closeWindow:
                return event
            }
        }
    }

    private func removeMonitor() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }
}
