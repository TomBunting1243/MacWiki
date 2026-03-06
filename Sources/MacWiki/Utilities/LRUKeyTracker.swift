struct LRUKeyTracker<Key: Hashable & Sendable>: Sendable {
    private var order: [Key] = []

    var orderedKeys: [Key] {
        order
    }

    mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    mutating func remove(_ key: Key) {
        order.removeAll { $0 == key }
    }

    mutating func trim(to limit: Int) -> [Key] {
        guard limit >= 0 else {
            let evicted = order
            order.removeAll()
            return evicted
        }

        var evicted: [Key] = []
        while order.count > limit {
            evicted.append(order.removeFirst())
        }
        return evicted
    }

    mutating func removeAll() {
        order.removeAll()
    }
}
