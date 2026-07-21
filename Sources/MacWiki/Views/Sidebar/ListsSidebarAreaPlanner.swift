import Foundation

struct ListsSidebarAreaDeletionPlan {
    let rootAreaIDs: [UUID]
    let subtreeAreaIDs: Set<UUID>
    let folderCount: Int
    let listCount: Int
    let nestedFolderCount: Int

    var hasContents: Bool {
        listCount > 0 || nestedFolderCount > 0
    }
}

@MainActor
enum ListsSidebarAreaPlanner {
    static func buildDeletionPlan(
        requestedAreaIDs: Set<UUID>,
        snapshot: ListsSidebarSnapshot
    ) -> ListsSidebarAreaDeletionPlan? {
        let validAreaIDs = requestedAreaIDs.intersection(Set(snapshot.areaIndexByID.keys))
        guard !validAreaIDs.isEmpty else { return nil }

        let rootAreaIDs = topLevelAreaIDs(from: validAreaIDs, snapshot: snapshot)
        guard !rootAreaIDs.isEmpty else { return nil }

        var subtreeAreaIDs: Set<UUID> = []
        for areaID in rootAreaIDs {
            subtreeAreaIDs.formUnion(areaSubtreeIDs(for: areaID, snapshot: snapshot))
        }

        return ListsSidebarAreaDeletionPlan(
            rootAreaIDs: rootAreaIDs,
            subtreeAreaIDs: subtreeAreaIDs,
            folderCount: rootAreaIDs.count,
            listCount: listCount(in: subtreeAreaIDs, snapshot: snapshot),
            nestedFolderCount: max(0, subtreeAreaIDs.count - rootAreaIDs.count)
        )
    }

    static func sortAreasDeepestFirst(
        _ areaIDs: Set<UUID>,
        snapshot: ListsSidebarSnapshot
    ) -> [UUID] {
        areaIDs.sorted { lhsID, rhsID in
            let lhsDepth = areaDepth(lhsID, parentAreaByID: snapshot.parentAreaByID)
            let rhsDepth = areaDepth(rhsID, parentAreaByID: snapshot.parentAreaByID)
            if lhsDepth != rhsDepth {
                return lhsDepth > rhsDepth
            }

            guard let lhs = snapshot.areaIndexByID[lhsID], let rhs = snapshot.areaIndexByID[rhsID] else {
                return lhsID.uuidString < rhsID.uuidString
            }

            return ListsSidebarSnapshot.compareAreasForSortOrder(lhs, rhs)
        }
    }

    static func isDescendant(
        areaID potentialDescendantID: UUID,
        of potentialAncestorID: UUID,
        parentAreaByID: [UUID: UUID?]
    ) -> Bool {
        var currentID: UUID? = potentialDescendantID
        var visited: Set<UUID> = []

        while let resolvedID = currentID {
            if resolvedID == potentialAncestorID {
                return true
            }

            guard visited.insert(resolvedID).inserted else {
                return false
            }

            currentID = parentAreaByID[resolvedID] ?? nil
        }

        return false
    }

    private static func topLevelAreaIDs(
        from candidateIDs: Set<UUID>,
        snapshot: ListsSidebarSnapshot
    ) -> [UUID] {
        let sorted = candidateIDs.sorted { lhsID, rhsID in
            guard let lhs = snapshot.areaIndexByID[lhsID], let rhs = snapshot.areaIndexByID[rhsID] else {
                return lhsID.uuidString < rhsID.uuidString
            }
            return ListsSidebarSnapshot.compareAreasForSortOrder(lhs, rhs)
        }

        var roots: [UUID] = []
        var coveredAreaIDs: Set<UUID> = []

        for candidateID in sorted {
            guard !coveredAreaIDs.contains(candidateID) else { continue }

            let candidateSubtree = areaSubtreeIDs(for: candidateID, snapshot: snapshot)
            roots.removeAll { candidateSubtree.contains($0) }
            roots.append(candidateID)

            coveredAreaIDs = roots.reduce(into: []) { covered, rootID in
                covered.formUnion(areaSubtreeIDs(for: rootID, snapshot: snapshot))
            }
        }

        return roots.sorted { lhsID, rhsID in
            guard let lhs = snapshot.areaIndexByID[lhsID], let rhs = snapshot.areaIndexByID[rhsID] else {
                return lhsID.uuidString < rhsID.uuidString
            }
            return ListsSidebarSnapshot.compareAreasForSortOrder(lhs, rhs)
        }
    }

    private static func areaSubtreeIDs(
        for rootAreaID: UUID,
        snapshot: ListsSidebarSnapshot
    ) -> Set<UUID> {
        guard let rootArea = snapshot.areaIndexByID[rootAreaID] else {
            return []
        }

        var visited: Set<UUID> = [rootAreaID]
        var queue: [Area] = [rootArea]

        while let current = queue.popLast() {
            for childArea in snapshot.childAreas(of: current) {
                if visited.insert(childArea.id).inserted {
                    queue.append(childArea)
                }
            }
        }

        return visited
    }

    private static func listCount(
        in subtreeAreaIDs: Set<UUID>,
        snapshot: ListsSidebarSnapshot
    ) -> Int {
        subtreeAreaIDs.reduce(into: 0) { count, areaID in
            guard let area = snapshot.areaIndexByID[areaID] else { return }
            count += snapshot.lists(in: area).count
        }
    }

    private static func areaDepth(
        _ areaID: UUID,
        parentAreaByID: [UUID: UUID?]
    ) -> Int {
        var depth = 0
        var currentID: UUID? = areaID
        var visited: Set<UUID> = []

        while let resolvedID = currentID,
              let parentID = parentAreaByID[resolvedID] ?? nil {
            guard visited.insert(resolvedID).inserted else {
                return depth
            }
            depth += 1
            currentID = parentID
        }

        return depth
    }
}
