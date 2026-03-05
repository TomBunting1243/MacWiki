import Foundation

enum ReferenceExportFormat: String, CaseIterable {
    case plainText
    case markdown
    case html

    var title: String {
        switch self {
        case .plainText: return "Plain Text"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        }
    }
} 
