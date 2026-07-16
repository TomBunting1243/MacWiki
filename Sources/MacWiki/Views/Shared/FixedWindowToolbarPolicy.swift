import AppKit
import SwiftUI

@MainActor
enum WorkspaceSplitControllerRegistry {
    private final class WeakEntry {
        weak var window: NSWindow?
        weak var controller: AppKitWorkspaceNavigationController?

        init(window: NSWindow, controller: AppKitWorkspaceNavigationController) {
            self.window = window
            self.controller = controller
        }
    }

    private static var entries: [ObjectIdentifier: WeakEntry] = [:]

    static func register(
        _ controller: AppKitWorkspaceNavigationController,
        in window: NSWindow
    ) {
        entries[ObjectIdentifier(window)] = WeakEntry(window: window, controller: controller)
    }

    static func controller(in window: NSWindow) -> AppKitWorkspaceNavigationController? {
        let key = ObjectIdentifier(window)
        guard let entry = entries[key],
              entry.window === window,
              let controller = entry.controller else {
            entries.removeValue(forKey: key)
            return nil
        }
        return controller
    }

    static func unregister(
        _ controller: AppKitWorkspaceNavigationController,
        from window: NSWindow
    ) {
        let key = ObjectIdentifier(window)
        guard entries[key]?.window === window,
              entries[key]?.controller === controller else { return }
        entries.removeValue(forKey: key)
    }
}

final class WorkspaceInspectorResponder: NSResponder, NSUserInterfaceValidations {
    private(set) weak var controller: AppKitWorkspaceNavigationController?

    init(controller: AppKitWorkspaceNavigationController) {
        self.controller = controller
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(controller: AppKitWorkspaceNavigationController) {
        self.controller = controller
    }

    @objc func toggleInspector(_ sender: Any?) {
        controller?.toggleInspector(sender)
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        item.action == #selector(toggleInspector(_:)) && controller != nil
    }
}

/// SwiftUI does not expose every macOS window-toolbar primitive. This narrow
/// platform boundary leaves Reader item creation and placement in SwiftUI,
/// disables editing for the fixed layout, and can install AppKit's standard
/// Inspector toggle followed by its tracking separator. That native ordering
/// keeps the collapse control at the Reader's trailing edge while the Inspector
/// owns the full-height section beyond the divider.
struct FixedWindowToolbarPolicy: NSViewRepresentable {
    var installsInspectorSection = true
    var relaysNestedWorkspaceInspector = false

    func makeNSView(context: Context) -> FixedWindowToolbarPolicyView {
        FixedWindowToolbarPolicyView(
            installsInspectorSection: installsInspectorSection,
            relaysNestedWorkspaceInspector: relaysNestedWorkspaceInspector
        )
    }

    func updateNSView(_ nsView: FixedWindowToolbarPolicyView, context: Context) {
        nsView.installsInspectorSection = installsInspectorSection
        nsView.relaysNestedWorkspaceInspector = relaysNestedWorkspaceInspector
        nsView.enforcePolicy()
    }
}

final class FixedWindowToolbarPolicyView: NSView {
    var installsInspectorSection: Bool
    var relaysNestedWorkspaceInspector: Bool
    private var isEnforcingPolicy = false
    private weak var workspaceController: AppKitWorkspaceNavigationController?
    private weak var responderWindow: NSWindow?
    private var inspectorResponder: WorkspaceInspectorResponder?

    init(
        installsInspectorSection: Bool,
        relaysNestedWorkspaceInspector: Bool = false
    ) {
        self.installsInspectorSection = installsInspectorSection
        self.relaysNestedWorkspaceInspector = relaysNestedWorkspaceInspector
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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            detachInspectorResponder()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func layout() {
        super.layout()
        enforcePolicy()
    }

    isolated deinit {
        detachInspectorResponder()
        NotificationCenter.default.removeObserver(self)
    }

    func enforcePolicy() {
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
        if !toolbar.items.contains(where: { $0.itemIdentifier == toggle }) {
            let insertionIndex = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == separator
            }) ?? toolbar.items.count
            toolbar.insertItem(withItemIdentifier: toggle, at: insertionIndex)
        }
        if !toolbar.items.contains(where: { $0.itemIdentifier == separator }) {
            let insertionIndex = toolbar.items.firstIndex(where: {
                $0.itemIdentifier == toggle
            }).map { $0 + 1 } ?? toolbar.items.count
            toolbar.insertItem(withItemIdentifier: separator, at: insertionIndex)
        }

        if relaysNestedWorkspaceInspector {
            configureWorkspaceInspectorItems(in: toolbar)
        } else {
            workspaceController = nil
            detachInspectorResponder()
        }
    }

    private func configureWorkspaceInspectorItems(in toolbar: NSToolbar) {
        guard let controller = workspaceControllerInWindow() else { return }
        guard let toggleItem = toolbar.items.first(where: {
            $0.itemIdentifier == .toggleInspector
        }) else {
            return
        }

        if !toggleItem.autovalidates {
            toggleItem.autovalidates = true
        }
        installInspectorResponder(for: controller)

        guard let inspectorIndex = controller.splitViewItems.firstIndex(where: {
            $0.behavior == .inspector
        }), inspectorIndex > 0,
        let trackingItem = toolbar.items.first(where: {
            $0.itemIdentifier == .inspectorTrackingSeparator
        }) as? NSTrackingSeparatorToolbarItem else {
            return
        }

        if trackingItem.splitView !== controller.splitView {
            trackingItem.splitView = controller.splitView
        }
        let dividerIndex = inspectorIndex - 1
        if trackingItem.dividerIndex != dividerIndex {
            trackingItem.dividerIndex = dividerIndex
        }
    }

    private func installInspectorResponder(
        for controller: AppKitWorkspaceNavigationController
    ) {
        guard let window else { return }

        if let inspectorResponder, responderWindow === window {
            inspectorResponder.update(controller: controller)
            if !Self.responderChain(startingAt: window, contains: inspectorResponder) {
                inspectorResponder.nextResponder = window.nextResponder
                window.nextResponder = inspectorResponder
            }
            return
        }

        detachInspectorResponder()
        let responder = WorkspaceInspectorResponder(controller: controller)
        responder.nextResponder = window.nextResponder
        window.nextResponder = responder
        responderWindow = window
        inspectorResponder = responder
    }

    private func detachInspectorResponder() {
        guard let inspectorResponder else { return }
        if let responderWindow {
            var predecessor: NSResponder = responderWindow
            var visited = Set<ObjectIdentifier>()
            while let next = predecessor.nextResponder {
                let identifier = ObjectIdentifier(next)
                guard visited.insert(identifier).inserted else { break }
                if next === inspectorResponder {
                    predecessor.nextResponder = inspectorResponder.nextResponder
                    break
                }
                predecessor = next
            }
        }
        inspectorResponder.nextResponder = nil
        self.inspectorResponder = nil
        responderWindow = nil
    }

    private static func responderChain(
        startingAt responder: NSResponder,
        contains target: NSResponder
    ) -> Bool {
        var current: NSResponder? = responder
        var visited = Set<ObjectIdentifier>()
        while let responder = current {
            let identifier = ObjectIdentifier(responder)
            guard visited.insert(identifier).inserted else { return false }
            if responder === target { return true }
            current = responder.nextResponder
        }
        return false
    }

    private func workspaceControllerInWindow() -> AppKitWorkspaceNavigationController? {
        if let workspaceController,
           workspaceController.view.window === window {
            return workspaceController
        }
        guard let window else { return nil }

        if let controller = WorkspaceSplitControllerRegistry.controller(in: window) {
            workspaceController = controller
            return controller
        }

        if let contentController = window.contentViewController,
           let controller = Self.workspaceController(in: contentController) {
            workspaceController = controller
            return controller
        }
        if let contentView = window.contentView,
           let controller = Self.workspaceController(in: contentView) {
            workspaceController = controller
            return controller
        }
        return nil
    }

    private static func workspaceController(
        in root: NSViewController
    ) -> AppKitWorkspaceNavigationController? {
        if let controller = root as? AppKitWorkspaceNavigationController {
            return controller
        }
        for child in root.children {
            if let controller = workspaceController(in: child) {
                return controller
            }
        }
        return nil
    }

    private static func workspaceController(
        in root: NSView
    ) -> AppKitWorkspaceNavigationController? {
        var pending = [root]
        while let view = pending.popLast() {
            if let controller = view.nextResponder as? AppKitWorkspaceNavigationController {
                return controller
            }
            pending.append(contentsOf: view.subviews.reversed())
        }
        return nil
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        enforcePolicy()
    }
}
