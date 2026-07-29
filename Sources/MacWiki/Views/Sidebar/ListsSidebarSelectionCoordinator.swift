import Foundation
import Observation

struct ListsSidebarExternalSelection: Equatable {
    let isSearchPresented: Bool
    let selectedListID: UUID?
    let selectedLabelID: UUID?
    let selectedTagID: UUID?
    let rootSelection: SidebarRootSelection
    let isWikiHopAvailable: Bool
}

enum ListsSidebarSelectionResolution: Equatable {
    case restoreExternalSelection
    case apply(SidebarSelectionID)
    case selectAreas(Set<UUID>)
}

/// Owns the native List selection mirror for one window. External bindings remain the
/// source of truth; this coordinator canonicalizes their many inputs without spreading
/// a bidirectional state machine across SwiftUI lifecycle modifiers.
@MainActor
@Observable
final class ListsSidebarSelectionCoordinator {
    var selectionSet: Set<SidebarSelectionID> = []
    var selectedAreaIDs: Set<UUID> = []

    func sync(from external: ListsSidebarExternalSelection) {
        let resolved = resolvedSelection(from: external)
        guard selectionSet != resolved else { return }
        selectionSet = resolved
    }

    func resolvedSelection(
        from external: ListsSidebarExternalSelection
    ) -> Set<SidebarSelectionID> {
        if external.isSearchPresented {
            return [.search]
        }
        if let listID = external.selectedListID {
            return [.list(listID)]
        }
        if let labelID = external.selectedLabelID {
            return [.label(labelID)]
        }
        if let tagID = external.selectedTagID {
            return [.tag(tagID)]
        }
        if !selectedAreaIDs.isEmpty {
            return Set(selectedAreaIDs.map(SidebarSelectionID.area))
        }
        if external.rootSelection == .wikiHop && !external.isWikiHopAvailable {
            return [.root(.recents)]
        }
        return [.root(external.rootSelection)]
    }

    /// Accessibility actions can invoke an already-selected row without producing a native
    /// List selection change. Return that row so the caller can apply it immediately.
    func select(_ selection: SidebarSelectionID) -> SidebarSelectionID? {
        let canonical: Set<SidebarSelectionID> = [selection]
        guard selectionSet != canonical else { return selection }
        selectionSet = canonical
        return nil
    }

    func reconcileSelectionChange(
        from oldValue: Set<SidebarSelectionID>,
        to newValue: Set<SidebarSelectionID>
    ) -> ListsSidebarSelectionResolution {
        guard !newValue.isEmpty else {
            return .restoreExternalSelection
        }

        let addedSelections = newValue.subtracting(oldValue)
        let nonAreaSelections = Set(newValue.filter { selection in
            if case .area = selection { return false }
            return true
        })

        if let selection = preferredSelection(
            in: nonAreaSelections,
            preferring: addedSelections
        ) {
            selectedAreaIDs.removeAll()
            canonicalizeSelectionSet([selection])
            return .apply(selection)
        }

        let areaIDs = Set(newValue.compactMap { selection -> UUID? in
            if case .area(let areaID) = selection {
                return areaID
            }
            return nil
        })
        guard !areaIDs.isEmpty else {
            return .restoreExternalSelection
        }

        selectedAreaIDs = areaIDs
        canonicalizeSelectionSet(Set(areaIDs.map(SidebarSelectionID.area)))
        return .selectAreas(areaIDs)
    }

    func retainAreaIDs(_ availableAreaIDs: Set<UUID>) {
        selectedAreaIDs.formIntersection(availableAreaIDs)
        selectionSet = Set(selectionSet.filter { selection in
            guard case .area(let areaID) = selection else { return true }
            return availableAreaIDs.contains(areaID)
        })
    }

    func setRecentsSelection() {
        selectedAreaIDs.removeAll()
        canonicalizeSelectionSet([.root(.recents)])
    }

    private func canonicalizeSelectionSet(_ canonical: Set<SidebarSelectionID>) {
        guard selectionSet != canonical else { return }
        selectionSet = canonical
    }

    private func preferredSelection(
        in selections: Set<SidebarSelectionID>,
        preferring addedSelections: Set<SidebarSelectionID>
    ) -> SidebarSelectionID? {
        let preferredSelections = addedSelections
            .intersection(selections)
            .sorted(by: compareSelections(_:_:))
        if let preferred = preferredSelections.first {
            return preferred
        }
        return selections.sorted(by: compareSelections(_:_:)).first
    }

    private func compareSelections(_ lhs: SidebarSelectionID, _ rhs: SidebarSelectionID) -> Bool {
        selectionSortKey(lhs) < selectionSortKey(rhs)
    }

    private func selectionSortKey(_ selection: SidebarSelectionID) -> String {
        switch selection {
        case .search:
            return "0-search"
        case .root(let root):
            return "1-root-\(rootSortTitle(root))"
        case .list(let id):
            return "2-list-\(id.uuidString)"
        case .label(let id):
            return "3-label-\(id.uuidString)"
        case .tag(let id):
            return "4-tag-\(id.uuidString)"
        case .area(let id):
            return "5-area-\(id.uuidString)"
        }
    }

    private func rootSortTitle(_ selection: SidebarRootSelection) -> String {
        switch selection {
        case .discover:
            return "Discover"
        case .recents:
            return "Recents"
        case .wikiHop:
            return "Wiki-Hop"
        }
    }
}
