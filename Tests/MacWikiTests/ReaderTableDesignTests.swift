import Foundation
import Testing

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
        #expect(css.contains("font-size: 0.88em"))
        #expect(css.contains("padding-inline:"))
        #expect(css.contains("caption-side: top"))
        #expect(css.contains("@media (max-width: 620px)"))
        #expect(css.contains("float: none"))
        #expect(css.contains("@media (prefers-contrast: more)"))
        #expect(css.contains("@media (forced-colors: active)"))
        #expect(css.contains(".pcs-collapse-table-content"))
        #expect(css.contains(":not(table):not(table *)"))
        #expect(css.contains("table.macwiki-reader-data-table"))
        #expect(!css.contains("table:not(.infobox)"))
        #expect(css.contains("tr:nth-child(even):not([class]):not([style])"))
        #expect(!css.contains("text-align: left"))
        #expect(!css.contains("background-image: none"))
        #expect(!css.contains("table.wikitable td"))
        #expect(!css.contains("table td,\ntable th {\n    background-color:"))
    }

    @Test func readerTableEnhancerWrapsOnlyGeneralTablesAndFocusesOnlyOverflow() throws {
        let script = try resource("Sources/MacWiki/Resources/ReaderTableEnhancements.js")

        #expect(script.contains("table.closest(skipContainerSelector)"))
        #expect(script.contains("!table.matches(dataTableSelector)"))
        #expect(script.contains("table:not(:is(.infobox, .infobox-full-data, .pcs-table-infobox))"))
        #expect(script.contains("table.classList.add(dataTableClass)"))
        #expect(script.contains("const dataTableClass = 'macwiki-reader-data-table'"))
        #expect(script.contains("table.parentNode.insertBefore(wrapper, table)"))
        #expect(script.contains("wrapper.appendChild(table)"))
        #expect(script.contains(".querySelector('caption')"))
        #expect(script.contains("Scrollable data table"))
        #expect(script.contains("table.scrollWidth > wrapper.clientWidth + overflowTolerance"))
        #expect(script.contains("wrapper.tabIndex = 0"))
        #expect(script.contains("wrapper.removeAttribute('tabindex')"))
        #expect(script.contains("new ResizeObserver"))
        #expect(script.contains("table.parentElement?.classList.contains(wrapperClass)"))
        #expect(script.contains(".infobox"))
        #expect(script.contains(".pcs-collapse-table-container"))
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
