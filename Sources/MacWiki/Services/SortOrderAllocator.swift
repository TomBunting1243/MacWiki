import Foundation

enum SortOrderAllocator {
    static func next(for existingOrders: some Sequence<Int>) -> Int {
        var maxOrder = -1
        for order in existingOrders {
            if order > maxOrder {
                maxOrder = order
            }
        }

        if maxOrder == Int.max {
            return Int.max
        }
        return maxOrder + 1
    }
}
