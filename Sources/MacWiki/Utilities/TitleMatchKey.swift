import Foundation

/// Canonical case- and underscore-insensitive key for matching article titles
/// across Discover stores and Wikipedia service lookups.
func titleMatchKey(_ title: String) -> String {
    title
        .lowercased()
        .replacingOccurrences(of: "_", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
