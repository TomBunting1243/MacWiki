import AppKit

enum SystemBridge {
    @discardableResult
    static func copyText(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    static func openURLExternally(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    static var isCommandPressed: Bool {
        CGEvent(source: nil)?.flags.contains(.maskCommand) ?? false
    }

    static var isShiftPressed: Bool {
        CGEvent(source: nil)?.flags.contains(.maskShift) ?? false
    }

    static var isOptionPressed: Bool {
        CGEvent(source: nil)?.flags.contains(.maskAlternate) ?? false
    }
}
