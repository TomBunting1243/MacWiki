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
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
           ) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
