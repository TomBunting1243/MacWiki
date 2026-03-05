import Foundation

/// Pure helper for sidebar collapse behavior so we can regression-test
/// selection fallback logic in headless runtime tests.
enum SidebarCollapseSelectionGuard {
    static func collapseWouldHideSelectedList(
        selectedAreaID: UUID?,
        collapsingAreaID: UUID,
        parentAreaByID: [UUID: UUID?]
    ) -> Bool {
        guard let selectedAreaID else { return false }

        var currentAreaID: UUID? = selectedAreaID
        var visited: Set<UUID> = []

        while let areaID = currentAreaID {
            if areaID == collapsingAreaID {
                return true
            }

            // Defensive cycle break in case parent pointers are corrupted.
            guard visited.insert(areaID).inserted else {
                return false
            }

            currentAreaID = parentAreaByID[areaID] ?? nil
        }

        return false
    }
}
