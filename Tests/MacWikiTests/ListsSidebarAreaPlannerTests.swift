import Foundation
import Testing

@testable import MacWiki

@MainActor
struct ListsSidebarAreaPlannerTests {
    @Test func buildDeletionPlanCollapsesNestedSelectionIntoSingleRootPlan() {
        let rootArea = Area(name: "Research")
        rootArea.sortOrder = 0
        rootArea.createdAt = Date(timeIntervalSinceReferenceDate: 100)

        let childArea = Area(name: "Swift", parentId: rootArea.id)
        childArea.sortOrder = 0
        childArea.createdAt = Date(timeIntervalSinceReferenceDate: 101)

        let grandchildArea = Area(name: "Runtime", parentId: childArea.id)
        grandchildArea.sortOrder = 0
        grandchildArea.createdAt = Date(timeIntervalSinceReferenceDate: 102)

        let rootList = ReadingList(name: "Inbox")
        rootList.areaId = rootArea.id

        let nestedList = ReadingList(name: "Benchmarks")
        nestedList.areaId = grandchildArea.id

        let snapshot = ListsSidebarSnapshot(
            lists: [rootList, nestedList],
            areas: [grandchildArea, childArea, rootArea],
            labels: [],
            tags: [],
            savedArticles: [],
            highlights: [],
            articleStates: [],
            sortOrder: .manual
        )

        let plan = ListsSidebarAreaPlanner.buildDeletionPlan(
            requestedAreaIDs: [rootArea.id, childArea.id],
            snapshot: snapshot
        )

        #expect(plan?.rootAreaIDs == [rootArea.id])
        #expect(plan?.subtreeAreaIDs == [rootArea.id, childArea.id, grandchildArea.id])
        #expect(plan?.folderCount == 1)
        #expect(plan?.nestedFolderCount == 2)
        #expect(plan?.listCount == 2)
        #expect(plan?.hasContents == true)
    }

    @Test func buildDeletionPlanIgnoresUnknownAreaIDs() {
        let rootArea = Area(name: "Research")
        let snapshot = ListsSidebarSnapshot(
            lists: [],
            areas: [rootArea],
            labels: [],
            tags: [],
            savedArticles: [],
            highlights: [],
            articleStates: [],
            sortOrder: .manual
        )

        let plan = ListsSidebarAreaPlanner.buildDeletionPlan(
            requestedAreaIDs: [UUID()],
            snapshot: snapshot
        )

        #expect(plan == nil)
    }

    @Test func sortAreasDeepestFirstPrefersChildrenBeforeParents() {
        let rootArea = Area(name: "Research")
        let childArea = Area(name: "Swift", parentId: rootArea.id)
        let grandchildArea = Area(name: "Runtime", parentId: childArea.id)

        let snapshot = ListsSidebarSnapshot(
            lists: [],
            areas: [grandchildArea, rootArea, childArea],
            labels: [],
            tags: [],
            savedArticles: [],
            highlights: [],
            articleStates: [],
            sortOrder: .manual
        )

        let orderedAreaIDs = ListsSidebarAreaPlanner.sortAreasDeepestFirst(
            [rootArea.id, childArea.id, grandchildArea.id],
            snapshot: snapshot
        )

        #expect(orderedAreaIDs == [grandchildArea.id, childArea.id, rootArea.id])
    }

    @Test func isDescendantBreaksCyclesSafely() {
        let areaA = UUID()
        let areaB = UUID()
        let unrelated = UUID()
        let parentAreaByID: [UUID: UUID?] = [
            areaA: areaB,
            areaB: areaA
        ]

        #expect(ListsSidebarAreaPlanner.isDescendant(areaID: areaB, of: areaA, parentAreaByID: parentAreaByID))
        #expect(!ListsSidebarAreaPlanner.isDescendant(areaID: areaA, of: unrelated, parentAreaByID: parentAreaByID))
    }

    @Test func buildDeletionPlanBreaksAncestryCyclesOutsideTheCandidateSet() {
        let selected = Area(name: "Selected")
        let cycleA = Area(name: "Cycle A")
        let cycleB = Area(name: "Cycle B")
        selected.parentId = cycleA.id
        cycleA.parentId = cycleB.id
        cycleB.parentId = cycleA.id

        let snapshot = ListsSidebarSnapshot(
            lists: [], areas: [selected, cycleA, cycleB], labels: [], tags: [],
            savedArticles: [], highlights: [], articleStates: [], sortOrder: .manual
        )

        let plan = ListsSidebarAreaPlanner.buildDeletionPlan(
            requestedAreaIDs: [selected.id],
            snapshot: snapshot
        )

        #expect(plan?.rootAreaIDs == [selected.id])
        #expect(plan?.subtreeAreaIDs == [selected.id])
    }

    @Test func buildDeletionPlanTreatsSelfParentedCandidateAsItsOwnRoot() {
        let selected = Area(name: "Selected")
        selected.parentId = selected.id
        let snapshot = ListsSidebarSnapshot(
            lists: [], areas: [selected], labels: [], tags: [], savedArticles: [],
            highlights: [], articleStates: [], sortOrder: .manual
        )

        let plan = ListsSidebarAreaPlanner.buildDeletionPlan(
            requestedAreaIDs: [selected.id], snapshot: snapshot
        )

        #expect(plan?.rootAreaIDs == [selected.id])
        #expect(plan?.subtreeAreaIDs == [selected.id])
    }

    @Test func buildDeletionPlanChoosesOneStableRootForSelectedCycle() {
        let first = Area(name: "First")
        first.sortOrder = 0
        let second = Area(name: "Second")
        second.sortOrder = 1
        first.parentId = second.id
        second.parentId = first.id
        let snapshot = ListsSidebarSnapshot(
            lists: [], areas: [second, first], labels: [], tags: [], savedArticles: [],
            highlights: [], articleStates: [], sortOrder: .manual
        )

        let plan = ListsSidebarAreaPlanner.buildDeletionPlan(
            requestedAreaIDs: [first.id, second.id], snapshot: snapshot
        )

        #expect(plan?.rootAreaIDs == [first.id])
        #expect(plan?.subtreeAreaIDs == [first.id, second.id])
        #expect(plan?.folderCount == 1)
        #expect(plan?.nestedFolderCount == 1)
    }
}
