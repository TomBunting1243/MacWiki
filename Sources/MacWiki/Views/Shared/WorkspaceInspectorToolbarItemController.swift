import AppKit

/// Owns the native Inspector mode control and its target/action bridge.
/// `WorkspaceToolbarController` remains responsible for placement, validation,
/// and snapshot refreshes; this helper keeps tab-role construction isolated.
@MainActor
final class WorkspaceInspectorToolbarItemController: NSObject {
    private weak var appState: AppState?
    private weak var toolbarItem: NSToolbarItemGroup?
    private(set) var isPlaneVisible: Bool

    init(appState: AppState, isPlaneVisible: Bool) {
        self.appState = appState
        self.isPlaneVisible = isPlaneVisible
        super.init()
    }

    func update(appState: AppState) {
        self.appState = appState
    }

    func makeItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItemGroup {
        let titles = InspectorMode.allCases.map(\.rawValue)
        let item = NSToolbarItemGroup(
            itemIdentifier: identifier,
            titles: titles,
            selectionMode: .selectOne,
            labels: titles,
            target: self,
            action: #selector(selectInspectorMode(_:))
        )
        item.label = "Inspector Views"
        item.paletteLabel = "Inspector Views"
        item.toolTip = "Choose Inspector View"
        item.controlRepresentation = .expanded
        item.visibilityPriority = .high
        // Xcode 26's macOS SDK cannot resolve this macOS 27 symbol even behind
        // a runtime availability check. Keep the richer role when compiling
        // with the Swift 6.3 / macOS 27 toolchain while retaining Xcode 26 CI.
        #if compiler(>=6.3)
        if #available(macOS 27, *) {
            item.role = .tabs
        }
        #endif
        toolbarItem = item
        return item
    }

    func updateSelection(
        of item: NSToolbarItem,
        to mode: InspectorMode
    ) {
        guard let group = item as? NSToolbarItemGroup,
              let selectedIndex = InspectorMode.allCases.firstIndex(of: mode) else {
            return
        }
        guard group.selectedIndex != selectedIndex else { return }
        group.selectedIndex = selectedIndex
    }

    func updateSelection(to mode: InspectorMode) {
        guard let toolbarItem else { return }
        updateSelection(of: toolbarItem, to: mode)
    }

    func setPlaneVisible(_ isVisible: Bool, in toolbar: NSToolbar?) {
        isPlaneVisible = isVisible
        guard let toolbar else { return }

        if !isVisible,
           let boundaryIndex = toolbar.items.firstIndex(where: {
               $0.itemIdentifier == .inspectorTrackingSeparator
           }) {
            toolbar.removeItem(at: boundaryIndex)
        }

        toolbar.items.filter {
            $0.itemIdentifier == .workspaceInspectorModes
        }.forEach { item in
            let shouldHide = !isVisible
            if item.isHidden != shouldHide {
                item.isHidden = shouldHide
            }
            if item.itemIdentifier == .workspaceInspectorModes {
                if item.isEnabled != isVisible {
                    item.isEnabled = isVisible
                }
            }
        }

        if isVisible,
           !toolbar.items.contains(where: {
               $0.itemIdentifier == .inspectorTrackingSeparator
           }), let modeIndex = toolbar.items.firstIndex(where: {
               $0.itemIdentifier == .workspaceInspectorModes
           }) {
            toolbar.insertItem(
                withItemIdentifier: .inspectorTrackingSeparator,
                at: modeIndex
            )
        }
    }

    @objc private func selectInspectorMode(_ sender: Any?) {
        guard let group = (sender as? NSToolbarItemGroup) ?? toolbarItem,
              InspectorMode.allCases.indices.contains(group.selectedIndex) else {
            return
        }
        let mode = InspectorMode.allCases[group.selectedIndex]
        guard appState?.inspectorMode != mode else { return }
        appState?.inspectorMode = mode
    }
}
