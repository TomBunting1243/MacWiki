import CoreGraphics
import Foundation

enum TabBarDragPlanner {
    static func shiftAmount(
        for index: Int,
        draggedTabID: UUID?,
        draggedSourceIndex: Int,
        currentTargetIndex: Int,
        tabFrames: [UUID: CGRect],
        tabSpacing: CGFloat,
        fallbackTabWidth: CGFloat = 180
    ) -> CGFloat {
        guard let draggedTabID, index != draggedSourceIndex else {
            return 0
        }

        let tabWidth = tabFrames[draggedTabID]?.width ?? fallbackTabWidth
        let shiftDistance = tabWidth + tabSpacing

        if draggedSourceIndex < index && index <= currentTargetIndex {
            return -shiftDistance
        }
        if draggedSourceIndex > index && index >= currentTargetIndex {
            return shiftDistance
        }

        return 0
    }

    static func targetIndex(
        pointerX: CGFloat,
        currentTargetIndex: Int,
        tabOrder: [UUID],
        tabFrames: [UUID: CGRect],
        fallback: Int,
        hysteresis: CGFloat = 8
    ) -> Int {
        var closestIndex = fallback
        var closestDistance = CGFloat.greatestFiniteMagnitude

        for (index, tabID) in tabOrder.enumerated() {
            guard let frame = tabFrames[tabID] else { continue }
            let distance = abs(frame.midX - pointerX)
            if distance < closestDistance {
                closestDistance = distance
                closestIndex = index
            }
        }

        if closestIndex != currentTargetIndex,
           tabOrder.indices.contains(currentTargetIndex),
           let currentFrame = tabFrames[tabOrder[currentTargetIndex]] {
            let currentDistance = abs(currentFrame.midX - pointerX)
            if closestDistance + hysteresis >= currentDistance {
                return currentTargetIndex
            }
        }

        return closestIndex
    }

    static func autoScrollTargetIndex(
        pointerX: CGFloat,
        viewportFrame: CGRect,
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        currentTargetIndex: Int,
        tabCount: Int,
        edgeThreshold: CGFloat
    ) -> Int? {
        guard !viewportFrame.isEmpty, tabCount > 1 else { return nil }
        guard contentWidth > viewportWidth + 8 else { return nil }

        let leadingDistance = pointerX - viewportFrame.minX
        let trailingDistance = viewportFrame.maxX - pointerX
        let nearLeadingEdge = leadingDistance < edgeThreshold
        let nearTrailingEdge = trailingDistance < edgeThreshold
        let isDeepEdge = min(leadingDistance, trailingDistance) < (edgeThreshold * 0.45)
        let step = isDeepEdge ? 2 : 1

        if nearLeadingEdge {
            return max(0, currentTargetIndex - step)
        }
        if nearTrailingEdge {
            return min(tabCount - 1, currentTargetIndex + step)
        }

        return nil
    }
}
