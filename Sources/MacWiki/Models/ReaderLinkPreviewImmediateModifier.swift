import Foundation

enum ReaderLinkPreviewImmediateModifier: String, CaseIterable, Codable, Identifiable {
    case off = "off"
    case command = "command"

    static let `default`: Self = .command

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .command:
            return "Command"
        }
    }

    var summary: String {
        switch self {
        case .off:
            return "Use the normal hover delay for all link previews."
        case .command:
            return "Hold Command while hovering to reveal previews immediately."
        }
    }

    var javaScriptValue: String {
        rawValue
    }
}
