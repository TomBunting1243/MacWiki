import Foundation

/// Keeps query-backed reading lists stable for the lifetime of a presentation.
///
/// Saving changes a list's recency timestamp, which can reorder a SwiftData query.
/// Holding identifiers instead of model references prevents rows from moving under
/// the pointer while still allowing deleted and newly created lists to reconcile.
struct ReadingListPresentationOrder: Equatable {
    private(set) var orderedIDs: [UUID] = []

    mutating func reconcile(with currentIDs: [UUID]) {
        guard !orderedIDs.isEmpty else {
            orderedIDs = currentIDs
            return
        }

        let currentIDSet = Set(currentIDs)
        orderedIDs.removeAll { !currentIDSet.contains($0) }

        let knownIDs = Set(orderedIDs)
        orderedIDs.append(contentsOf: currentIDs.filter { !knownIDs.contains($0) })
    }

    func arrangedIDs(for currentIDs: [UUID]) -> [UUID] {
        let currentIDSet = Set(currentIDs)
        let survivingIDs = orderedIDs.filter(currentIDSet.contains)
        let knownIDs = Set(survivingIDs)
        return survivingIDs + currentIDs.filter { !knownIDs.contains($0) }
    }

    mutating func reset() {
        orderedIDs.removeAll(keepingCapacity: true)
    }
}
