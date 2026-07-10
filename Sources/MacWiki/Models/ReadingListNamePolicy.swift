import Foundation

enum ReadingListNamePolicy {
    static func normalized(_ proposedName: String) -> String? {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
