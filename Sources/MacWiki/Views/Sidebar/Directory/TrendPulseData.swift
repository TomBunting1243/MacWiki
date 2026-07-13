import Foundation

struct TrendPulsePoint: Identifiable, Equatable {
    let id: Int
    let date: Date
    let views: Int
}

enum TrendPulseDownsampler {
    static func points(_ points: [TrendPulsePoint], maximumCount: Int) -> [TrendPulsePoint] {
        guard points.count > maximumCount, maximumCount >= 8 else { return points }
        guard let first = points.first, let last = points.last else { return points }

        let interior = Array(points.dropFirst().dropLast())
        guard !interior.isEmpty else { return points }

        let bucketCount = max(1, (maximumCount - 2) / 2)
        let bucketSize = max(1, Int((Double(interior.count) / Double(bucketCount)).rounded(.up)))

        var sampled: [TrendPulsePoint] = [first]
        sampled.reserveCapacity(maximumCount)

        var start = 0
        while start < interior.count {
            let end = min(start + bucketSize, interior.count)
            let bucket = interior[start..<end]
            if let minimum = bucket.min(by: { $0.views < $1.views }),
               let maximum = bucket.max(by: { $0.views < $1.views }) {
                if minimum.id == maximum.id {
                    sampled.append(minimum)
                } else if minimum.id < maximum.id {
                    sampled.append(minimum)
                    sampled.append(maximum)
                } else {
                    sampled.append(maximum)
                    sampled.append(minimum)
                }
            }
            start += bucketSize
        }

        sampled.append(last)

        var seen = Set<Int>()
        let extrema = sampled
            .filter { seen.insert($0.id).inserted }
            .sorted(by: { $0.id < $1.id })

        guard extrema.count > maximumCount else { return extrema }

        let stride = max(1, Int((Double(points.count - 2) / Double(maximumCount - 2)).rounded(.up)))
        var reduced: [TrendPulsePoint] = [first]
        var index = 1
        while index < points.count - 1 {
            reduced.append(points[index])
            index += stride
        }
        if reduced.last?.id != last.id {
            reduced.append(last)
        }
        return Array(reduced.prefix(maximumCount))
    }
}
