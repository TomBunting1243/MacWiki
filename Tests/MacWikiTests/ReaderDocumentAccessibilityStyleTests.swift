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

    @Test func differentiateWithoutColorAddsAnUnderlineToRenderedHighlights() async throws {
        let harness = ReaderWebKitHarness(injectWebViewScript: true)
        try await harness.loadHTML(
            """
            <html><body>
              <p><mark id="highlight" class="macwiki-highlight">Readable highlight</mark></p>
            </body></html>
            """
        )
        try await harness.waitUntil(
            "window.getComputedStyle(document.querySelector('#highlight')).cursor === 'pointer'"
        )

        let initialDecoration = try await highlightDecoration(in: harness)
        _ = try await harness.evaluateBool(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: false,
                differentiateWithoutColor: true
            )
        )
        let accessibleDecoration = try await highlightDecoration(in: harness)
        let customHighlightDecoration = try await harness.evaluateString(
            Self.customHighlightDecorationScript
        )

        #expect(initialDecoration == "none")
        #expect(accessibleDecoration.contains("underline"))
        #expect(customHighlightDecoration.contains("underline"))
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

    private func highlightDecoration(in harness: ReaderWebKitHarness) async throws -> String {
        try await harness.evaluateString(
            "window.getComputedStyle(document.querySelector('#highlight')).textDecorationLine"
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

    private static let customHighlightDecorationScript = """
    (function () {
        const target = document.querySelector('#highlight');
        if (!target || !target.firstChild || !window.CSS || !CSS.highlights ||
            typeof Highlight !== 'function') {
            return '';
        }

        const range = new Range();
        range.selectNodeContents(target);
        CSS.highlights.set('macwiki-yellow', new Highlight(range));
        return window.getComputedStyle(
            target,
            '::highlight(macwiki-yellow)'
        ).textDecorationLine || '';
    })();
    """
}
