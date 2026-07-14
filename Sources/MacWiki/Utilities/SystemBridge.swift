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

    @MainActor static var isCommandPressed: Bool {
        currentModifierFlags.contains(.command)
    }

    @MainActor static var isShiftPressed: Bool {
        currentModifierFlags.contains(.shift)
    }

    @MainActor static var isOptionPressed: Bool {
        currentModifierFlags.contains(.option)
    }

    /// Prefer the event that triggered the current AppKit action. The static
    /// fallback covers keyboard-driven actions without creating a global
    /// Core Graphics event snapshot.
    @MainActor private static var currentModifierFlags: NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    }
}
