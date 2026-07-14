import AppKit
import Testing

@testable import MacWiki

@Suite(.serialized)
@MainActor
struct WindowContentMinimumSizeBridgeTests {
    @Test func appliesAndUpdatesTheNativeWindowContentMinimum() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_400, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let contentView = try #require(window.contentView)
        let minimumSizeView = WindowContentMinimumSizeView(
            minimumSize: CGSize(width: 1_229, height: 520)
        )

        contentView.addSubview(minimumSizeView)
        #expect(window.contentMinSize == NSSize(width: 1_229, height: 520))

        minimumSizeView.minimumSize = CGSize(width: 791, height: 520)
        #expect(window.contentMinSize == NSSize(width: 791, height: 520))

        window.setContentSize(NSSize(width: 800, height: 600))
        minimumSizeView.minimumSize = CGSize(width: 1_229, height: 700)
        #expect(window.contentMinSize == NSSize(width: 1_229, height: 700))
        #expect(window.contentView?.bounds.width == 800)
        #expect(window.contentView?.bounds.height == 600)
    }
}
