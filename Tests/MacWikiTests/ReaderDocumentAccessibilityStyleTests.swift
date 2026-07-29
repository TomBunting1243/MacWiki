import Testing

@testable import MacWiki

@MainActor
@Suite(.serialized)
struct ReaderDocumentAccessibilityStyleTests {
    @Test func updateScriptTogglesNativeReaderAccessibilityClassesLive() async throws {
        let harness = ReaderWebKitHarness(injectReaderStyle: false)
        try await harness.loadHTML("<html><body>Reader</body></html>")

        let enabled = try await harness.evaluateBool(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: true,
                differentiateWithoutColor: true
            )
        )
        #expect(enabled)
        #expect(try await rootHasClass(
            ReaderDocumentAccessibilityStyle.reduceTransparencyClass,
            in: harness
        ))
        #expect(try await rootHasClass(
            ReaderDocumentAccessibilityStyle.differentiateWithoutColorClass,
            in: harness
        ))

        let disabled = try await harness.evaluateBool(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: false,
                differentiateWithoutColor: false
            )
        )
        #expect(!disabled)
        #expect(!(try await rootHasClass(
            ReaderDocumentAccessibilityStyle.reduceTransparencyClass,
            in: harness
        )))
        #expect(!(try await rootHasClass(
            ReaderDocumentAccessibilityStyle.differentiateWithoutColorClass,
            in: harness
        )))
    }

    @Test func reduceTransparencyClassMakesReaderTableSurfacesOpaque() async throws {
        let harness = ReaderWebKitHarness()
        try await harness.loadHTML(
            """
            <html><body>
              <div id="table-surface" style="background-color: var(--table-surface)">Facts</div>
            </body></html>
            """
        )

        let initialAlpha = try await tableSurfaceAlpha(in: harness)
        _ = try await harness.evaluateBool(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: true
            )
        )
        let accessibleAlpha = try await tableSurfaceAlpha(in: harness)
        _ = try await harness.evaluateBool(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: false
            )
        )
        let restoredAlpha = try await tableSurfaceAlpha(in: harness)

        #expect(initialAlpha < 1)
        #expect(accessibleAlpha == 1)
        #expect(restoredAlpha < 1)

        let parsedMediaQueries = try await harness.evaluateStrings(Self.mediaQueryConditionsScript)
        #expect(!parsedMediaQueries.contains { condition in
            condition.localizedCaseInsensitiveContains("prefers-reduced-transparency")
        })
    }

    @Test func differentiateWithoutColorGivesEveryRenderedHighlightADistinctPattern() async throws {
        let harness = ReaderWebKitHarness(injectWebViewScript: true)
        try await harness.loadHTML(
            """
            <html><body>
              <p>
                <mark id="highlight-yellow" class="macwiki-highlight" data-highlight-color="yellow">Yellow</mark>
                <mark id="highlight-blue" class="macwiki-highlight" data-highlight-color="blue">Blue</mark>
                <mark id="highlight-pink" class="macwiki-highlight" data-highlight-color="pink">Pink</mark>
                <mark id="highlight-orange" class="macwiki-highlight" data-highlight-color="orange">Orange</mark>
              </p>
            </body></html>
            """
        )
        try await harness.waitUntil(
            "window.getComputedStyle(document.querySelector('#highlight-yellow')).cursor === 'pointer'"
        )

        let initialDecorations = try await fallbackHighlightDecorations(in: harness)
        _ = try await harness.evaluateBool(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: false,
                differentiateWithoutColor: true
            )
        )
        let accessibleDecorations = try await fallbackHighlightDecorations(in: harness)
        let customHighlightDecorations = try await harness.evaluateStrings(
            Self.customHighlightDecorationsScript
        )

        #expect(initialDecorations.allSatisfy { $0 == "none|solid" })
        #expect(accessibleDecorations == [
            "underline|solid",
            "underline|double",
            "underline|dashed",
            "underline|wavy"
        ])
        #expect(customHighlightDecorations == [
            "underline|solid",
            "underline|double",
            "underline|dashed",
            "underline|wavy"
        ])
    }

    private func rootHasClass(
        _ className: String,
        in harness: ReaderWebKitHarness
    ) async throws -> Bool {
        try await harness.evaluateBool(
            "document.documentElement.classList.contains('\(className)')"
        )
    }

    private func tableSurfaceAlpha(in harness: ReaderWebKitHarness) async throws -> Double {
        try await harness.evaluateNumber(
            """
            (function () {
                const color = window.getComputedStyle(
                    document.querySelector('#table-surface')
                ).backgroundColor;
                const components = color.match(/[\\d.]+/g) || [];
                return components.length > 3 ? Number(components[3]) : 1;
            })();
            """
        )
    }

    private func fallbackHighlightDecorations(in harness: ReaderWebKitHarness) async throws -> [String] {
        try await harness.evaluateStrings(
            """
            ['yellow', 'blue', 'pink', 'orange'].map(function (color) {
                const style = window.getComputedStyle(document.querySelector('#highlight-' + color));
                return style.textDecorationLine + '|' + style.textDecorationStyle;
            });
            """
        )
    }

    private static let mediaQueryConditionsScript = """
    (function () {
        const conditions = [];
        function collect(ruleList) {
            Array.from(ruleList || []).forEach(function (rule) {
                if (rule instanceof CSSMediaRule) {
                    conditions.push(rule.conditionText);
                }
                if (rule.cssRules) {
                    collect(rule.cssRules);
                }
            });
        }
        Array.from(document.styleSheets).forEach(function (sheet) {
            collect(sheet.cssRules);
        });
        return conditions;
    })();
    """

    private static let customHighlightDecorationsScript = """
    (function () {
        const colors = ['yellow', 'blue', 'pink', 'orange'];
        if (!window.CSS || !CSS.highlights ||
            typeof Highlight !== 'function') {
            return [];
        }

        return colors.map(function (color) {
            const target = document.querySelector('#highlight-' + color);
            const range = new Range();
            range.selectNodeContents(target);
            const name = 'macwiki-' + color;
            CSS.highlights.set(name, new Highlight(range));
            const style = window.getComputedStyle(target, '::highlight(' + name + ')');
            return style.textDecorationLine + '|' + style.textDecorationStyle;
        });
    })();
    """
}
