import Foundation
import Testing

@testable import MacWiki

struct ReadingListPresentationOrderTests {
    @Test func capturesInitialOrderAndIgnoresQueryReordering() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var order = ReadingListPresentationOrder()

        order.reconcile(with: [first, second, third])
        order.reconcile(with: [third, first, second])

        #expect(order.arrangedIDs(for: [third, first, second]) == [first, second, third])
    }

    @Test func removesDeletedIDsAndAppendsNewIDsWithoutMovingSurvivors() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let added = UUID()
        var order = ReadingListPresentationOrder()

        order.reconcile(with: [first, second, third])
        order.reconcile(with: [added, third, first])

        #expect(order.arrangedIDs(for: [added, third, first]) == [first, third, added])
    }

    @Test func resetLetsTheNextPresentationCaptureFreshRecencyOrder() {
        let first = UUID()
        let second = UUID()
        var order = ReadingListPresentationOrder()

        order.reconcile(with: [first, second])
        order.reset()
        order.reconcile(with: [second, first])

        #expect(order.arrangedIDs(for: [second, first]) == [second, first])
    }
}
