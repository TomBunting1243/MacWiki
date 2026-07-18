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
        if #available(macOS 27, *) {
            item.role = .tabs
        }
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
        toolbar?.items.filter {
            [.workspaceReaderInspectorBoundary, .workspaceInspectorModes]
                .contains($0.itemIdentifier)
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
        let inspectorToolTip = isVisible ? "Hide Inspector" : "Show Inspector"
        if let inspectorToggle = toolbar?.items.first(where: {
            $0.itemIdentifier == .workspaceInspectorToggle
        }), inspectorToggle.toolTip != inspectorToolTip {
            inspectorToggle.toolTip = inspectorToolTip
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
