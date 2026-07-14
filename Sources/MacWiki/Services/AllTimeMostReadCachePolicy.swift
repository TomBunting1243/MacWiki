import Foundation

/// Keeps the historical ranking cache aligned with the amount of data the
/// current Discover presentation needs.
enum AllTimeMostReadCachePolicy {
    static let supportedLimit = 1...80

    static func clampedLimit(_ requestedLimit: Int) -> Int {
        min(max(requestedLimit, supportedLimit.lowerBound), supportedLimit.upperBound)
    }

    /// Returns the prefix size that can satisfy the request, or `nil` when a
    /// partial enrichment must be retried instead of being treated as complete.
    static func reusablePrefixCount(
        cachedCount: Int,
        requestedLimit: Int
    ) -> Int? {
        let requiredCount = clampedLimit(requestedLimit)
        return cachedCount >= requiredCount ? requiredCount : nil
    }
}
