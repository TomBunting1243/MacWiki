import Foundation

enum HighlightMarkerStyle: String, CaseIterable, Identifiable {
    case dot = "Dot"
    case bar = "Bar"
    case background = "Background"

    var id: String { rawValue }
}
