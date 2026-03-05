import Foundation

enum InspectorTableOfContentsPresentation: String, CaseIterable, Identifiable {
    case standard
    case liquidDock

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:
            return "Standard"
        case .liquidDock:
            return "Liquid Dock"
        }
    }
}

