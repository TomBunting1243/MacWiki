import CoreGraphics
import Foundation
import Testing

@testable import MacWiki

struct TabBarDragPlannerTests {
    @Test func targetIndexHonorsHysteresisAroundCurrentTarget() {
        let firstID = UUID()
        let secondID = UUID()
        let tabFrames: [UUID: CGRect] = [
            firstID: CGRect(x: 80, y: 0, width: 40, height: 20),
            secondID: CGRect(x: 92, y: 0, width: 40, height: 20)
        ]

        let targetIndex = TabBarDragPlanner.targetIndex(
            pointerX: 103,
            currentTargetIndex: 0,
            tabOrder: [firstID, secondID],
            tabFrames: tabFrames,
            fallback: 0
        )

        #expect(targetIndex == 0)
    }

    @Test func shiftAmountMovesIntermediateTabsLeftWhenDraggingRight() {
        let draggedTabID = UUID()
        let tabFrames: [UUID: CGRect] = [
            draggedTabID: CGRect(x: 0, y: 0, width: 120, height: 30)
        ]

        let shift = TabBarDragPlanner.shiftAmount(
            for: 2,
            draggedTabID: draggedTabID,
            draggedSourceIndex: 0,
            currentTargetIndex: 2,
            tabFrames: tabFrames,
            tabSpacing: 12
        )

        #expect(shift == -132)
    }

    @Test func autoScrollTargetIndexStepsTwoSlotsAtDeepTrailingEdge() {
        let targetIndex = TabBarDragPlanner.autoScrollTargetIndex(
            pointerX: 294,
            viewportFrame: CGRect(x: 0, y: 0, width: 300, height: 40),
            viewportWidth: 300,
            contentWidth: 620,
            currentTargetIndex: 2,
            tabCount: 6,
            edgeThreshold: 80
        )

        #expect(targetIndex == 4)
    }

    @Test func autoScrollTargetIndexReturnsNilWhenContentFitsViewport() {
        let targetIndex = TabBarDragPlanner.autoScrollTargetIndex(
            pointerX: 10,
            viewportFrame: CGRect(x: 0, y: 0, width: 300, height: 40),
            viewportWidth: 300,
            contentWidth: 300,
            currentTargetIndex: 1,
            tabCount: 3,
            edgeThreshold: 80
        )

        #expect(targetIndex == nil)
    }
}
