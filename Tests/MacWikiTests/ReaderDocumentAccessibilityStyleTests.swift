import Foundation
import JavaScriptCore
import Testing

@testable import MacWiki

@Suite
struct ReaderDocumentAccessibilityStyleTests {
    @Test func updateScriptTogglesNativeReaderAccessibilityClassesLive() throws {
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
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: true,
                differentiateWithoutColor: true
            )
        )
        #expect(enabled?.toBool() == true)
        #expect(classState(
            ReaderDocumentAccessibilityStyle.reduceTransparencyClass,
            in: context
        ) == true)
        #expect(classState(
            ReaderDocumentAccessibilityStyle.differentiateWithoutColorClass,
            in: context
        ) == true)

        let disabled = context.evaluateScript(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: false,
                differentiateWithoutColor: false
            )
        )
        #expect(disabled?.toBool() == false)
        #expect(classState(
            ReaderDocumentAccessibilityStyle.reduceTransparencyClass,
            in: context
        ) == false)
        #expect(classState(
            ReaderDocumentAccessibilityStyle.differentiateWithoutColorClass,
            in: context
        ) == false)
    }

    @Test func readerCSSUsesTheNativeRootClassInsteadOfUnsupportedWebKitMediaQuery() throws {
        let css = try resource("Sources/MacWiki/Resources/Reader.css")

        #expect(css.contains("html.macwiki-reduce-transparency"))
        #expect(!css.contains("prefers-reduced-transparency"))
    }

    @Test func highlightCSSProvidesANonColorCueWhenRequested() throws {
        let script = try resource("Sources/MacWiki/Resources/WebView.js")

        #expect(script.contains("html.macwiki-differentiate-without-color ::highlight(macwiki-yellow)"))
        #expect(script.contains("html.macwiki-differentiate-without-color .macwiki-highlight"))
        #expect(script.contains("text-decoration-line: underline"))
    }

    private func classState(_ className: String, in context: JSContext) -> Bool {
        context.evaluateScript(
            "classStates['\(className)'] === true"
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
