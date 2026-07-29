import Foundation
import Testing

@testable import MacWiki

@MainActor
struct ListsSidebarSelectionCoordinatorTests {
    @Test func externalSelectionUsesTheExistingSidebarPrecedence() {
        let coordinator = ListsSidebarSelectionCoordinator()
        let listID = UUID()
        let labelID = UUID()
        let tagID = UUID()
        let areaID = UUID()
        coordinator.selectedAreaIDs = [areaID]

        let allInputs = ListsSidebarExternalSelection(
            isSearchPresented: true,
            selectedListID: listID,
            selectedLabelID: labelID,
            selectedTagID: tagID,
            rootSelection: .discover,
            isWikiHopAvailable: true
        )
        #expect(coordinator.resolvedSelection(from: allInputs) == [.search])

        let listInputs = ListsSidebarExternalSelection(
            isSearchPresented: false,
            selectedListID: listID,
            selectedLabelID: labelID,
            selectedTagID: tagID,
            rootSelection: .discover,
            isWikiHopAvailable: true
        )
        #expect(coordinator.resolvedSelection(from: listInputs) == [.list(listID)])

        let labelInputs = ListsSidebarExternalSelection(
            isSearchPresented: false,
            selectedListID: nil,
            selectedLabelID: labelID,
            selectedTagID: tagID,
            rootSelection: .discover,
            isWikiHopAvailable: true
        )
        #expect(coordinator.resolvedSelection(from: labelInputs) == [.label(labelID)])

        let tagInputs = ListsSidebarExternalSelection(
            isSearchPresented: false,
            selectedListID: nil,
            selectedLabelID: nil,
            selectedTagID: tagID,
            rootSelection: .discover,
            isWikiHopAvailable: true
        )
        #expect(coordinator.resolvedSelection(from: tagInputs) == [.tag(tagID)])

        let areaInputs = ListsSidebarExternalSelection(
            isSearchPresented: false,
            selectedListID: nil,
            selectedLabelID: nil,
            selectedTagID: nil,
            rootSelection: .discover,
            isWikiHopAvailable: true
        )
        #expect(coordinator.resolvedSelection(from: areaInputs) == [.area(areaID)])
    }

    @Test func unavailableWikiHopResolvesToRecentsWithoutChangingOtherRoots() {
        let coordinator = ListsSidebarSelectionCoordinator()
        let unavailableWikiHop = ListsSidebarExternalSelection(
            isSearchPresented: false,
            selectedListID: nil,
            selectedLabelID: nil,
            selectedTagID: nil,
            rootSelection: .wikiHop,
            isWikiHopAvailable: false
        )
        #expect(coordinator.resolvedSelection(from: unavailableWikiHop) == [.root(.recents)])

        let discover = ListsSidebarExternalSelection(
            isSearchPresented: false,
            selectedListID: nil,
            selectedLabelID: nil,
            selectedTagID: nil,
            rootSelection: .discover,
            isWikiHopAvailable: false
        )
        #expect(coordinator.resolvedSelection(from: discover) == [.root(.discover)])
    }

    @Test func selectionChangePrefersTheNewNonAreaSelectionAndCanonicalizesIt() {
        let coordinator = ListsSidebarSelectionCoordinator()
        let areaID = UUID()
        let listID = UUID()
        let oldSelection: Set<SidebarSelectionID> = [.area(areaID)]
        let newSelection: Set<SidebarSelectionID> = [.area(areaID), .list(listID)]

        let resolution = coordinator.reconcileSelectionChange(
            from: oldSelection,
            to: newSelection
        )

        #expect(resolution == .apply(.list(listID)))
        #expect(coordinator.selectionSet == [.list(listID)])
        #expect(coordinator.selectedAreaIDs.isEmpty)
    }

    @Test func areaSelectionKeepsEveryNativeSelectedFolder() {
        let coordinator = ListsSidebarSelectionCoordinator()
        let first = UUID()
        let second = UUID()
        let selected: Set<SidebarSelectionID> = [.area(first), .area(second)]

        let resolution = coordinator.reconcileSelectionChange(from: [], to: selected)

        #expect(resolution == .selectAreas([first, second]))
        #expect(coordinator.selectedAreaIDs == [first, second])
        #expect(coordinator.selectionSet == selected)
    }

    @Test func emptyNativeSelectionRequestsExternalRestoration() {
        let coordinator = ListsSidebarSelectionCoordinator()
        #expect(
            coordinator.reconcileSelectionChange(from: [.root(.recents)], to: []) ==
            .restoreExternalSelection
        )
    }

    @Test func selectingTheCurrentAccessibilityRowAppliesImmediately() {
        let coordinator = ListsSidebarSelectionCoordinator()
        coordinator.selectionSet = [.root(.discover)]

        #expect(coordinator.select(.root(.discover)) == .root(.discover))
        #expect(coordinator.select(.root(.recents)) == nil)
        #expect(coordinator.selectionSet == [.root(.recents)])
    }

    @Test func recentsFallbackAndAreaReconciliationStayWindowLocal() {
        let coordinator = ListsSidebarSelectionCoordinator()
        let retained = UUID()
        let removed = UUID()
        coordinator.selectedAreaIDs = [retained, removed]
        coordinator.selectionSet = [.area(retained), .area(removed)]

        coordinator.retainAreaIDs([retained])
        #expect(coordinator.selectedAreaIDs == [retained])
        #expect(coordinator.selectionSet == [.area(retained)])

        coordinator.setRecentsSelection()
        #expect(coordinator.selectedAreaIDs.isEmpty)
        #expect(coordinator.selectionSet == [.root(.recents)])
    }
}
