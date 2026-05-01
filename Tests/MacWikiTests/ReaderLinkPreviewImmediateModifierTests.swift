import Testing

@testable import MacWiki

struct ReaderLinkPreviewImmediateModifierTests {
    @Test func commandIsTheDefaultModifier() {
        #expect(ReaderLinkPreviewImmediateModifier.default == .command)
    }

    @Test func exposesStableJavaScriptValues() {
        #expect(ReaderLinkPreviewImmediateModifier.off.javaScriptValue == "off")
        #expect(ReaderLinkPreviewImmediateModifier.command.javaScriptValue == "command")
    }
}
