import AppKit
import Testing

@testable import MacWiki

@MainActor
struct NativeDesignRegressionTests {
    @Test func windowRolesExposeOnlyTheirNativeCommandCapabilities() {
        #expect(MacWikiCommandCapabilities.mainWorkspace.contains(.workspaceNavigation))
        #expect(MacWikiCommandCapabilities.mainWorkspace.contains(.tabs))
        #expect(MacWikiCommandCapabilities.mainWorkspace.contains(.reader))
        #expect(MacWikiCommandCapabilities.articleWindow.contains(.reader))
        #expect(MacWikiCommandCapabilities.articleWindow.contains(.inspector))
        #expect(!MacWikiCommandCapabilities.articleWindow.contains(.tabs))
        #expect(!MacWikiCommandCapabilities.articleWindow.contains(.workspaceNavigation))
        #expect(!MacWikiCommandCapabilities.articleWindow.contains(.libraryOrganization))
    }

    @Test func currentEventModifiersTakePrecedenceOverGlobalModifiers() {
        let flags = SystemBridge.resolveModifierFlags(
            currentEvent: [.command, .option],
            global: [.shift]
        )

        #expect(flags == [.command, .option])
        #expect(
            SystemBridge.resolveModifierFlags(
                currentEvent: [],
                global: [.command]
            ).isEmpty
        )
    }

    @Test func globalModifiersAreUsedWhenThereIsNoCurrentEvent() {
        let flags = SystemBridge.resolveModifierFlags(
            currentEvent: nil,
            global: [.shift, .option]
        )

        #expect(flags == [.shift, .option])
    }
}
