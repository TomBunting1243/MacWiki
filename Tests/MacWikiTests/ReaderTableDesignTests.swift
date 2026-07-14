import Foundation
import Testing
import WebKit

@testable import MacWiki

@Suite
struct ReaderTableDesignTests {
    @Test func readerResourcesResolveFromTheSwiftPackageBundle() {
        #expect(!ReaderDocumentStyle.cssTemplate.isEmpty)
        #expect(!ReaderDocumentStyle.tableEnhancementScript.isEmpty)
        #expect(WebViewResourceLoader.resolvedURL(
            named: "Reader",
            withExtension: "css"
        ) != nil)
        #expect(WebViewResourceLoader.resolvedURL(
            named: "ReaderTableEnhancements",
            withExtension: "js"
        ) != nil)
    }

    @Test func webViewBuildsItsDocumentStyleThroughTheExtractedResourceBoundary() throws {
        let webViewSource = try resource("Sources/MacWiki/Views/Components/WebView.swift")
        let rendered = ReaderDocumentStyle.renderedCSS(
            minimumReadableColumnWidth: 480,
            readerTopInset: 56
        )

        #expect(webViewSource.contains("ReaderDocumentStyle.makeInjectionScript("))
        #expect(!webViewSource.contains("let css = \"\"\""))
        #expect(rendered.contains("calc((100vw - 480px) / 2)"))
        #expect(rendered.contains("--reader-top-inset: 56px"))
        #expect(!rendered.contains("__MACWIKI_"))
    }

    @Test func readerStyleResourceRendersDynamicMetricsWithoutLeavingTemplateTokens() {
        let rendered = ReaderDocumentStyle.renderedCSS(
            source: ":root { --safe: __MACWIKI_MINIMUM_READABLE_COLUMN_WIDTH_PX__px; --top: __MACWIKI_READER_TOP_INSET_PX__px; }",
            minimumReadableColumnWidth: 517.6,
            readerTopInset: 63.5
        )

        #expect(rendered.contains("--safe: 518px"))
        #expect(rendered.contains("--top: 64px"))
        #expect(!rendered.contains("__MACWIKI_"))
    }

    @Test func readerStyleInjectionUsesAJavaScriptStringLiteralInsteadOfATemplateLiteral() {
        let script = ReaderDocumentStyle.makeInjectionScript(
            css: "body::before { content: `reader ${unsafe}`; }\n</style>",
            tableEnhancementScript: "window.__readerTablePolicyLoaded = true;"
        )

        #expect(script.contains("style.textContent = \""))
        #expect(script.contains(#"`reader ${unsafe}`"#))
        #expect(script.contains(#"\n<\/style>"#))
        #expect(!script.contains("style.textContent = `"))
        #expect(script.contains("window.__readerTablePolicyLoaded = true;"))
        #expect(script.contains("meta.name = 'viewport'"))
    }

    @Test func readerCSSKeepsTablesEditorialResponsiveAndSemanticallyColored() throws {
        let css = try resource("Sources/MacWiki/Resources/Reader.css")

        #expect(css.contains("__MACWIKI_MINIMUM_READABLE_COLUMN_WIDTH_PX__"))
        #expect(css.contains("__MACWIKI_READER_TOP_INSET_PX__"))
        #expect(css.contains(".macwiki-table-scroll"))
        #expect(css.contains("overflow-x: auto"))
        #expect(css.contains("width: fit-content"))
        #expect(css.contains("min-width: 0"))
        #expect(css.contains("font-size: 0.88em"))
        #expect(css.contains("padding-inline:"))
        #expect(css.contains("caption-side: top"))
        #expect(css.contains("font-size: 1em"))
        #expect(css.contains("@media (max-width: 620px)"))
        #expect(css.contains("float: none"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        #expect(css.contains("@media (forced-colors: active)"))
        #expect(css.contains(".macwiki-authored-light-surface"))
        #expect(css.contains(".macwiki-authored-dark-surface"))
        #expect(css.contains("--macwiki-authored-surface-foreground"))
        #expect(css.contains("text-decoration-line: underline"))
        #expect(css.contains(".pcs-collapse-table-content"))
        #expect(css.contains(":not(table):not(table *)"))
        #expect(css.contains("table.macwiki-reader-data-table"))
        #expect(!css.contains("table:not(.infobox)"))
        #expect(css.contains("tr:nth-child(even):not([class]):not([style])"))
        #expect(css.contains("th[scope=\"col\"]:not([style]):not([bgcolor])"))
        #expect(!css.contains("text-align: left"))
        #expect(!css.contains("background-image: none"))
        #expect(!css.contains("table.wikitable td"))
        #expect(!css.contains("table td,\ntable th {\n    background-color:"))
        #expect(!css.contains(".macwiki-table-scroll > table {\n    width: auto;\n    min-width: 100%;"))
    }

    @Test func readerTableEnhancerWrapsOnlyGeneralTablesAndFocusesOnlyOverflow() throws {
        let script = try resource("Sources/MacWiki/Resources/ReaderTableEnhancements.js")

        #expect(script.contains("table.closest(skipContainerSelector)"))
        #expect(script.contains("!table.matches(dataTableSelector)"))
        #expect(script.contains("[role=\"presentation\"]"))
        #expect(script.contains("[role=\"none\"]"))
        #expect(script.contains("table.parentElement?.closest('table, .macwiki-table-scroll')"))
        #expect(script.contains("table.classList.add(dataTableClass)"))
        #expect(script.contains("const dataTableClass = 'macwiki-reader-data-table'"))
        #expect(script.contains("table.parentNode.insertBefore(wrapper, table)"))
        #expect(script.contains("wrapper.appendChild(table)"))
        #expect(script.contains(".querySelector('caption')"))
        #expect(script.contains("Scrollable data table"))
        #expect(script.contains("pendingRecord.table.scrollWidth >"))
        #expect(script.contains("pendingRecord.wrapper.clientWidth + overflowTolerance"))
        #expect(script.contains("wrapper.tabIndex = 0"))
        #expect(script.contains("wrapper.removeAttribute('tabindex')"))
        #expect(script.contains("wrapper.setAttribute('role', 'group')"))
        #expect(!script.contains("wrapper.setAttribute('role', 'region')"))
        #expect(script.contains("table.getAttribute('aria-labelledby')"))
        #expect(script.contains("new ResizeObserver"))
        #expect(script.components(separatedBy: "new ResizeObserver").count - 1 == 1)
        #expect(script.contains("const observedRecords = new Set()"))
        #expect(script.contains("const observedTargets = new WeakMap()"))
        #expect(script.contains("const pendingRecords = new Set()"))
        #expect(script.contains("let overflowFrameID = 0"))
        #expect(script.contains("const measurements = []"))
        #expect(script.contains("sharedResizeObserver.disconnect()"))
        #expect(script.contains("if (!event.persisted)"))
        #expect(script.contains("window.addEventListener('pagehide', handlePageHide)"))
        #expect(script.components(separatedBy: "window.addEventListener('resize'").count - 1 == 1)
        #expect(script.contains("const authoredSurfaceSelector"))
        #expect(script.contains("window.getComputedStyle(surface).backgroundColor"))
        #expect(script.contains("relativeLuminance"))
        #expect(script.contains("relativeLuminance(color) > 0.179"))
        #expect(script.contains("alpha < 0.9"))
        #expect(script.contains("surface.closest('table') !== table"))
        #expect(script.contains("classifyAuthoredSurfaces(table)"))
        #expect(script.contains("table.getAttribute('dir')"))
        #expect(!script.contains("wrapper.dir = 'auto'"))
        #expect(script.contains(".infobox"))
        #expect(script.contains(".pcs-collapse-table-container"))
    }

    @MainActor
    @Test func renderedReaderTablesPreserveSemanticsAndAdaptTheirLayout() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            window.requestAnimationFrame = function (callback) {
                return window.setTimeout(function () { callback(performance.now()); }, 0);
            };
            window.cancelAnimationFrame = function (identifier) {
                window.clearTimeout(identifier);
            };
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.addUserScript(WKUserScript(
            source: ReaderDocumentStyle.makeInjectionScript(
                minimumReadableColumnWidth: 480,
                readerTopInset: 0
            ),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 800),
            configuration: configuration
        )
        webView.loadHTMLString(Self.tableFixture, baseURL: nil)

        try await waitUntilReady(webView)
        let result = try await webView.evaluateJavaScript(Self.tableMetricsScript)
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let metrics = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(metrics["compactWrapped"] as? Bool == true)
        #expect(metrics["compactIsIntrinsic"] as? Bool == true)
        #expect(metrics["compactIsFocusable"] as? Bool == false)
        #expect(metrics["wideWrapped"] as? Bool == true)
        #expect(metrics["wideIsBounded"] as? Bool == true)
        #expect(metrics["wideOverflows"] as? Bool == true)
        #expect(metrics["wideTabIndex"] as? String == "0")
        #expect(metrics["wideRole"] as? String == "group")
        #expect(metrics["captionMatchesTable"] as? Bool == true)
        #expect(metrics["presentationalWrapped"] as? Bool == false)
        #expect(metrics["nestedWrapped"] as? Bool == false)
        #expect(metrics["nestedSurfaceClassified"] as? Bool == false)
        #expect(metrics["labelledName"] as? String == "Scrollable table: Population")
        #expect(metrics["rtlDirection"] as? String == "rtl")
        #expect(metrics["lightLinkColor"] as? String == "rgb(0, 0, 0)")
        #expect(metrics["darkLinkColor"] as? String == "rgb(255, 255, 255)")
        #expect(metrics["authoredTextColor"] as? String == "rgb(204, 0, 0)")
    }

    @MainActor
    private func waitUntilReady(_ webView: WKWebView) async throws {
        for _ in 0..<200 {
            let readyState = try? await webView.evaluateJavaScript("document.readyState") as? String
            let enhanced = try? await webView.evaluateJavaScript(
                "document.querySelector('#wide')?.parentElement?.dataset.macwikiTableOverflow === 'true'"
            ) as? Bool
            if readyState == "complete", enhanced == true {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        throw NSError(
            domain: "ReaderTableDesignTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out rendering the reader table fixture"]
        )
    }

    private static let tableFixture = """
    <!doctype html>
    <html>
      <body>
        <table id="compact"><caption>Compact</caption><tr><th scope="col">A</th><th scope="col">B</th></tr><tr><td>1</td><td>2</td></tr></table>
        <table id="wide" style="width: 1400px"><caption>Wide facts</caption><tr><th>One</th><th>Two</th><th>Three</th></tr><tr><td>Long content</td><td>Long content</td><td>Long content</td></tr></table>
        <table id="presentational" role="presentation"><tr><td>Layout only</td></tr></table>
        <table id="outer"><tr><td><table id="nested"><tr><td id="nested-surface" style="background: #14213d">Nested layout</td></tr></table></td></tr></table>
        <h2 id="population-heading">Population</h2>
        <table id="labelled" aria-labelledby="population-heading" style="width: 1400px"><tr><td>People</td></tr></table>
        <table id="rtl" dir="rtl"><tr><td>مرحبا</td></tr></table>
        <table id="semantic-colors">
          <tr><td id="light-surface" style="background: #fff28f; color: #cc0000"><a id="light-link" href="#">Light</a></td></tr>
          <tr><td id="dark-surface" style="background: #14213d"><a id="dark-link" href="#">Dark</a></td></tr>
        </table>
      </body>
    </html>
    """

    private static let tableMetricsScript = """
    JSON.stringify((function () {
        const compact = document.querySelector('#compact');
        const compactWrapper = compact.parentElement;
        const wide = document.querySelector('#wide');
        const wideWrapper = wide.parentElement;
        const labelledWrapper = document.querySelector('#labelled').parentElement;
        const rtlWrapper = document.querySelector('#rtl').parentElement;
        return {
            compactWrapped: compactWrapper.classList.contains('macwiki-table-scroll'),
            compactIsIntrinsic: compactWrapper.clientWidth < document.body.clientWidth,
            compactIsFocusable: compactWrapper.hasAttribute('tabindex'),
            wideWrapped: wideWrapper.classList.contains('macwiki-table-scroll'),
            wideIsBounded: wideWrapper.clientWidth <= document.body.clientWidth,
            wideOverflows: wide.scrollWidth > wideWrapper.clientWidth,
            wideTabIndex: wideWrapper.getAttribute('tabindex'),
            wideRole: wideWrapper.getAttribute('role'),
            captionMatchesTable: getComputedStyle(compact.querySelector('caption')).fontSize === getComputedStyle(compact).fontSize,
            presentationalWrapped: document.querySelector('#presentational').parentElement.classList.contains('macwiki-table-scroll'),
            nestedWrapped: document.querySelector('#nested').parentElement.classList.contains('macwiki-table-scroll'),
            nestedSurfaceClassified: document.querySelector('#nested-surface').classList.contains('macwiki-authored-dark-surface'),
            labelledName: labelledWrapper.getAttribute('aria-label'),
            rtlDirection: rtlWrapper.getAttribute('dir'),
            lightLinkColor: getComputedStyle(document.querySelector('#light-link')).color,
            darkLinkColor: getComputedStyle(document.querySelector('#dark-link')).color,
            authoredTextColor: getComputedStyle(document.querySelector('#light-surface')).color
        };
    })())
    """

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
