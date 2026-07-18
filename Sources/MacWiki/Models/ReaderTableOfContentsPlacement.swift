import Foundation

enum ReaderTableOfContentsPlacement: String, CaseIterable, Codable, Identifiable {
    case inspector = "Inspector"
    case readerLeading = "Left Overlay"
    case readerTrailing = "Right Overlay"

    var id: Self { self }

    var usesReaderOverlay: Bool {
        self != .inspector
    }

    var helpText: String {
        switch self {
        case .inspector:
            "Keep Contents in the lower half of the Info inspector."
        case .readerLeading:
            "Show Contents from a compact control on the left edge of the article."
        case .readerTrailing:
            "Show Contents from a compact control on the right edge of the article."
        }
    }
}
