import Foundation
import JavaScriptCore
import Testing

@testable import MacWiki

@Suite
struct ReaderDocumentAccessibilityStyleTests {
    @Test func updateScriptTogglesTheNativeReduceTransparencyClassLive() throws {
        let context = try #require(JSContext())
        context.evaluateScript(
            """
            var classStates = {};
            var document = {
                documentElement: {
                    classList: {
                        toggle: function(name, enabled) {
                            classStates[name] = Boolean(enabled);
                        },
                        contains: function(name) {
                            return classStates[name] === true;
                        }
                    }
                }
            };
            """
        )

        let enabled = context.evaluateScript(
            ReaderDocumentAccessibilityStyle.updateScript(reduceTransparency: true)
        )
        #expect(enabled?.toBool() == true)
        #expect(classState(in: context) == true)

        let disabled = context.evaluateScript(
            ReaderDocumentAccessibilityStyle.updateScript(reduceTransparency: false)
        )
        #expect(disabled?.toBool() == false)
        #expect(classState(in: context) == false)
    }

    @Test func readerCSSUsesTheNativeRootClassInsteadOfUnsupportedWebKitMediaQuery() throws {
        let css = try resource("Sources/MacWiki/Resources/Reader.css")

        #expect(css.contains("html.macwiki-reduce-transparency"))
        #expect(!css.contains("prefers-reduced-transparency"))
    }

    @Test func webViewReceivesAndSynchronizesTheNativeAccessibilityValue() throws {
        let reader = try resource("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let webView = try resource("Sources/MacWiki/Views/Components/WebView.swift")
        let lifecycle = try resource(
            "Sources/MacWiki/Views/Components/WebView/WebView+ContentLifecycle.swift"
        )

        #expect(reader.contains("reduceTransparency: accessibilityPersonalization.reduceTransparency"))
        #expect(webView.contains("reduceTransparency: reduceTransparency"))
        #expect(webView.contains("context.coordinator.reduceTransparency = reduceTransparency"))
        #expect(webView.contains("context.coordinator.syncReaderAccessibilityStyle(on: webView)"))
        #expect(lifecycle.contains("syncReaderAccessibilityStyle(on: webView, force: true)"))
        #expect(lifecycle.contains("self.lastAppliedReduceTransparency = requestedValue"))
    }

    private func classState(in context: JSContext) -> Bool {
        context.evaluateScript(
            "classStates['\(ReaderDocumentAccessibilityStyle.reduceTransparencyClass)'] === true"
        )?.toBool() == true
    }

    private func resource(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appending(path: path), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
