import AppKit
import Foundation
import WebKit

enum WebViewContextMenuController {
    enum LinkMenuAction {
        case open
        case openInNewTab
        case openInNewBackgroundTab
        case copyTitle
        case copyLink
        case saveToList
    }

    final class LinkMenuPayload: NSObject {
        let action: LinkMenuAction
        let url: URL
        let articleTitle: String?
        let readingListID: UUID?

        init(
            action: LinkMenuAction,
            url: URL,
            articleTitle: String?,
            readingListID: UUID? = nil
        ) {
            self.action = action
            self.url = url
            self.articleTitle = articleTitle
            self.readingListID = readingListID
        }
    }

    enum HighlightMenuAction {
        case setColor(HighlightColor)
        case editNote
        case delete
    }

    final class HighlightMenuPayload: NSObject {
        let action: HighlightMenuAction
        let highlightID: UUID

        init(action: HighlightMenuAction, highlightID: UUID) {
            self.action = action
            self.highlightID = highlightID
        }
    }

    enum SelectionMenuAction {
        case highlight(HighlightColor)
        case highlightWithNote(HighlightColor)
        case copySelection
    }

    final class SelectionMenuPayload: NSObject {
        let action: SelectionMenuAction
        let request: WebViewSelectionContextRequest

        init(action: SelectionMenuAction, request: WebViewSelectionContextRequest) {
            self.action = action
            self.request = request
        }
    }

    @MainActor
    static func contextMenuPoint(_ point: CGPoint, in webView: WKWebView) -> CGPoint {
        let minInset: CGFloat = 6
        let maxX = max(minInset, webView.bounds.width - minInset)
        let x = min(max(point.x, minInset), maxX)

        let resolvedY = webView.isFlipped ? point.y : (webView.bounds.height - point.y)
        let maxY = max(minInset, webView.bounds.height - minInset)
        let y = min(max(resolvedY, minInset), maxY)
        return CGPoint(x: x, y: y)
    }

    static func contextPoint(from data: [String: Any]) -> CGPoint {
        CGPoint(
            x: numericValue(from: data["x"]) ?? 0,
            y: numericValue(from: data["y"]) ?? 0
        )
    }

    static func numericValue(from raw: Any?) -> CGFloat? {
        if let value = raw as? CGFloat { return value }
        if let value = raw as? Double { return CGFloat(value) }
        if let value = raw as? Int { return CGFloat(value) }
        if let value = raw as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }

    static func highlightColorSwatchImage(for color: HighlightColor) -> NSImage {
        let size = NSSize(width: 12, height: 12)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
        let circle = NSBezierPath(ovalIn: rect)
        highlightSwatchColor(for: color).setFill()
        circle.fill()

        NSColor.labelColor.withAlphaComponent(0.18).setStroke()
        circle.lineWidth = 0.8
        circle.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func highlightSwatchColor(for color: HighlightColor) -> NSColor {
        switch color {
        case .yellow:
            return NSColor(srgbRed: 1.0, green: 0.86, blue: 0.30, alpha: 1.0)
        case .blue:
            return NSColor(srgbRed: 0.52, green: 0.80, blue: 0.98, alpha: 1.0)
        case .pink:
            return NSColor(srgbRed: 0.96, green: 0.52, blue: 0.70, alpha: 1.0)
        case .orange:
            return NSColor(srgbRed: 0.98, green: 0.64, blue: 0.30, alpha: 1.0)
        }
    }
}
