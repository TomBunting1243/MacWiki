import SwiftUI

enum MacWikiGlassRuntime {
    static let forceLegacyFallbackKey = "forceLegacyGlassFallback"

    static func usesNativeGlass(isEnabled: Bool, forceLegacyFallback: Bool) -> Bool {
        guard isEnabled, !forceLegacyFallback else { return false }
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    static func usesNativeGlass(forceLegacyFallback: Bool) -> Bool {
        usesNativeGlass(isEnabled: true, forceLegacyFallback: forceLegacyFallback)
    }
}

struct MacWikiGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
