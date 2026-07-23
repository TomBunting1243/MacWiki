import SwiftUI

extension EnvironmentValues {
    /// Height of reader-owned chrome that floats above scroll content. The
    /// initial document inset clears the controls, then scrolls away so content
    /// can continue beneath the native accessory and its scroll-edge effect.
    @Entry var readerChromeUnderlapHeight: CGFloat = 0
}
