import AppKit

enum AppIconLoader {
    @MainActor
    static func applyIfAvailable() {
        guard
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
            let iconImage = NSImage(contentsOf: iconURL)
        else {
            return
        }

        NSApp.applicationIconImage = iconImage
    }
}
