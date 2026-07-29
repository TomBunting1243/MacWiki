import Foundation
import Testing
import WebKit

@testable import MacWiki

@MainActor
@Suite(.serialized)
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
        let rendered = ReaderDocumentStyle.renderedCSS(
            minimumReadableColumnWidth: 480,
            readerTopInset: 56
        )

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

    @Test func renderedReaderTablesPreserveSemanticsAndAdaptTheirLayout() async throws {
        let harness = try await makeRenderedFixture()
        let metrics = try await jsonObject(Self.tableMetricsScript, in: harness)

        #expect(metrics["compactWrapped"] as? Bool == true)
        #expect(metrics["compactIsIntrinsic"] as? Bool == true)
        #expect(metrics["compactIsFocusable"] as? Bool == false)
        #expect(metrics["wideWrapped"] as? Bool == true)
        #expect(metrics["wideEnhancedAsDataTable"] as? Bool == true)
        #expect(metrics["wideIsBounded"] as? Bool == true)
        #expect(metrics["wideOverflows"] as? Bool == true)
        #expect(metrics["wideTabIndex"] as? String == "0")
        #expect(metrics["wideRole"] as? String == "group")
        #expect(metrics["wrapperOverflowX"] as? String == "auto")
        #expect(metrics["wideTableMinimumWidth"] as? String == "0px")
        #expect(metrics["wideTableMaximumWidth"] as? String == "none")
        #expect(metrics["captionMatchesTable"] as? Bool == true)
        #expect(metrics["captionIsAboveTable"] as? Bool == true)
        #expect(metrics["tableUsesEditorialScale"] as? Bool == true)
        #expect(metrics["cellHasInlinePadding"] as? Bool == true)
        #expect(metrics["presentationalWrapped"] as? Bool == false)
        #expect(metrics["roleNoneWrapped"] as? Bool == false)
        #expect(metrics["infoboxWrapped"] as? Bool == false)
        #expect(metrics["infoboxChildWrapped"] as? Bool == false)
        #expect(metrics["pcsInfoboxWrapped"] as? Bool == false)
        #expect(metrics["pcsContainerWrapped"] as? Bool == false)
        #expect(metrics["pcsContentWrapped"] as? Bool == false)
        #expect(metrics["pcsOtherWrapped"] as? Bool == false)
        #expect(metrics["pcsScrollWrapped"] as? Bool == false)
        #expect(metrics["pcsHorizontalScrollWrapped"] as? Bool == false)
        #expect(metrics["mediaWikiScrollWrapped"] as? Bool == false)
        #expect(metrics["nestedWrapped"] as? Bool == false)
        #expect(metrics["nestedSurfaceClassified"] as? Bool == false)
        #expect(metrics["captionPriorityName"] as? String == "Scrollable table: Caption wins")
        #expect(metrics["labelledByPriorityName"] as? String == "Scrollable table: Population Growth")
        #expect(metrics["authoredLabelPriorityName"] as? String == "Scrollable table: Authored summary")
        #expect(metrics["sectionPriorityName"] as? String == "Scrollable table in Demographics")
        #expect(metrics["defaultName"] as? String == "Scrollable data table")
        #expect(metrics["rtlDirection"] as? String == "rtl")
        #expect(metrics["defaultDirectionAbsent"] as? Bool == true)
        #expect(metrics["lightSurfaceClassified"] as? Bool == true)
        #expect(metrics["darkSurfaceClassified"] as? Bool == true)
        #expect(metrics["translucentSurfaceUnclassified"] as? Bool == true)
        #expect(metrics["lightLinkColor"] as? String == "rgb(0, 0, 0)")
        #expect(metrics["darkLinkColor"] as? String == "rgb(255, 255, 255)")
        #expect(metrics["authoredTextColor"] as? String == "rgb(204, 0, 0)")
        #expect(metrics["authoredBackgroundColor"] as? String == "rgb(255, 242, 143)")
        #expect(metrics["authoredBackgroundImagePreserved"] as? Bool == true)
        #expect(metrics["authoredAlignment"] as? String == "right")
        #expect(metrics["authoredLinkUnderlined"] as? Bool == true)
        #expect(metrics["pcsContentScrolls"] as? Bool == true)
        #expect(metrics["pcsTableRemainsUnclassified"] as? Bool == true)

        let desktopCellPadding = try #require(metrics["desktopCellInlinePadding"] as? NSNumber)
        harness.webView.setFrameSize(NSSize(width: 600, height: 800))
        try await wait(
            until: "window.innerWidth <= 620 && getComputedStyle(document.querySelector('#responsive-infobox')).float === 'none'",
            in: harness,
            failureDescription: "Timed out waiting for the compact table layout"
        )
        let compactMetrics = try await jsonObject(Self.compactMetricsScript, in: harness)

        #expect(compactMetrics["compactMediaMatches"] as? Bool == true)
        #expect(compactMetrics["infoboxFloat"] as? String == "none")
        #expect(compactMetrics["infoboxFillsReader"] as? Bool == true)
        #expect(compactMetrics["wrapperBorderRadius"] as? String == "8px")
        let compactCellPadding = try #require(compactMetrics["cellInlinePadding"] as? NSNumber)
        #expect(compactCellPadding.doubleValue < desktopCellPadding.doubleValue)
    }

    @Test func tableOverflowLifecycleSharesObservationAndCleansUpFocusAndPageState() async throws {
        let harness = try await makeRenderedFixture()
        let initialMetrics = try await jsonObject(Self.observerMetricsScript, in: harness)

        #expect(initialMetrics["nativeResizeObserverAvailable"] as? Bool == true)
        #expect(initialMetrics["observerInstances"] as? Int == 1)
        #expect(initialMetrics["observedEveryWrapperAndTable"] as? Bool == true)
        #expect(initialMetrics["disconnects"] as? Int == 0)

        _ = try await harness.evaluateBool("""
        (function () {
            const wide = document.querySelector('#wide');
            wide.style.width = 'auto';
            wide.querySelectorAll('th, td').forEach(function (cell) {
                cell.textContent = 'A';
            });
            return true;
        })()
        """)
        try await wait(
            until: "!document.querySelector('#wide').parentElement.hasAttribute('tabindex')",
            in: harness,
            failureDescription: "Timed out waiting for overflow focus cleanup"
        )
        let cleanedMetrics = try await jsonObject(Self.focusCleanupMetricsScript, in: harness)

        #expect(cleanedMetrics["stillOverflows"] as? Bool == false)
        #expect(cleanedMetrics["hasOverflowClass"] as? Bool == false)
        #expect(cleanedMetrics["hasOverflowDataset"] as? Bool == false)
        #expect(cleanedMetrics["tabIndex"] is NSNull)
        #expect(cleanedMetrics["role"] is NSNull)
        #expect(cleanedMetrics["ariaLabel"] is NSNull)

        _ = try await harness.evaluateBool("""
        (function () {
            window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: true }));
            return true;
        })()
        """)
        let persistedDisconnects = try await harness.evaluateNumber(
            "window.__macwikiObserverMetrics.disconnects"
        )
        #expect(persistedDisconnects == 0)

        _ = try await harness.evaluateBool("""
        (function () {
            window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: false }));
            return true;
        })()
        """)
        let finalMetrics = try await jsonObject(Self.observerMetricsScript, in: harness)
        #expect(finalMetrics["disconnects"] as? Int == 1)
    }

    @Test func unforceableTableAccessibilityRulesSurviveCSSOMParsing() async throws {
        let harness = try await makeRenderedFixture()
        let contracts = try await jsonObject(Self.cssOMContractsScript, in: harness)

        #expect(contracts["focusVisibleOutline"] as? Bool == true)
        #expect(contracts["increasedContrastBorder"] as? Bool == true)
        #expect(contracts["forcedColorsSurface"] as? Bool == true)
        #expect(contracts["forcedColorsFocusHighlight"] as? Bool == true)
    }

    @Test func tableOverflowFallbackSharesOneResizeListenerAndRemovesItOnPageHide() async throws {
        let harness = try await makeRenderedFixture(
            instrumentationScript: Self.fallbackInstrumentationScript
        )
        let initialMetrics = try await jsonObject(Self.fallbackMetricsScript, in: harness)

        #expect(initialMetrics["resizeListenerAdds"] as? Int == 1)
        #expect(initialMetrics["resizeListenerRemovals"] as? Int == 0)

        _ = try await harness.evaluateBool("""
        (function () {
            const wide = document.querySelector('#wide');
            wide.style.width = 'auto';
            wide.querySelectorAll('th, td').forEach(function (cell) {
                cell.textContent = 'A';
            });
            window.dispatchEvent(new Event('resize'));
            return true;
        })()
        """)
        try await wait(
            until: "!document.querySelector('#wide').parentElement.hasAttribute('tabindex')",
            in: harness,
            failureDescription: "Timed out waiting for fallback resize cleanup"
        )

        _ = try await harness.evaluateBool("""
        (function () {
            window.dispatchEvent(new PageTransitionEvent('pagehide', { persisted: false }));
            return true;
        })()
        """)
        let finalMetrics = try await jsonObject(Self.fallbackMetricsScript, in: harness)
        #expect(finalMetrics["resizeListenerRemovals"] as? Int == 1)
    }

    private func makeRenderedFixture(
        width: CGFloat = 640,
        instrumentationScript: String = Self.testInstrumentationScript
    ) async throws -> ReaderWebKitHarness {
        let harness = ReaderWebKitHarness(
            size: CGSize(width: width, height: 800),
            documentStartScripts: [instrumentationScript],
            injectReaderStyle: true
        )
        try await harness.loadHTML(Self.tableFixture)

        try await wait(
            until: "document.readyState === 'complete' && document.querySelector('#wide')?.parentElement?.dataset.macwikiTableOverflow === 'true'",
            in: harness,
            failureDescription: "Timed out rendering the reader table fixture"
        )
        return harness
    }

    private func wait(
        until condition: String,
        in harness: ReaderWebKitHarness,
        failureDescription: String
    ) async throws {
        do {
            try await harness.waitUntil(condition, attempts: 300)
        } catch {
            throw NSError(
                domain: "ReaderTableDesignTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: failureDescription,
                    NSUnderlyingErrorKey: error
                ]
            )
        }
    }

    private func jsonObject(
        _ script: String,
        in harness: ReaderWebKitHarness
    ) async throws -> [String: Any] {
        let json = try await harness.evaluateString(script)
        let data = try #require(json.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static let testInstrumentationScript = """
    (function () {
        const NativeResizeObserver = window.ResizeObserver;
        window.__macwikiObserverMetrics = {
            nativeResizeObserverAvailable: typeof NativeResizeObserver === 'function',
            instances: 0,
            observeCalls: 0,
            disconnects: 0
        };
        if (typeof NativeResizeObserver === 'function') {
            window.ResizeObserver = class {
                constructor(callback) {
                    window.__macwikiObserverMetrics.instances += 1;
                    this.nativeObserver = new NativeResizeObserver(callback);
                }
                observe(target, options) {
                    window.__macwikiObserverMetrics.observeCalls += 1;
                    this.nativeObserver.observe(target, options);
                }
                unobserve(target) {
                    this.nativeObserver.unobserve(target);
                }
                disconnect() {
                    window.__macwikiObserverMetrics.disconnects += 1;
                    this.nativeObserver.disconnect();
                }
            };
        }
    })();
    """

    private static let fallbackInstrumentationScript = """
    (function () {
        window.__macwikiFallbackMetrics = {
            resizeListenerAdds: 0,
            resizeListenerRemovals: 0
        };
        const nativeAddEventListener = window.addEventListener;
        const nativeRemoveEventListener = window.removeEventListener;
        window.addEventListener = function (type, listener, options) {
            if (type === 'resize') {
                window.__macwikiFallbackMetrics.resizeListenerAdds += 1;
            }
            return nativeAddEventListener.call(this, type, listener, options);
        };
        window.removeEventListener = function (type, listener, options) {
            if (type === 'resize') {
                window.__macwikiFallbackMetrics.resizeListenerRemovals += 1;
            }
            return nativeRemoveEventListener.call(this, type, listener, options);
        };
        Object.defineProperty(window, 'ResizeObserver', {
            configurable: true,
            value: undefined
        });
    })();
    """

    private static let tableFixture = """
    <!doctype html>
    <html>
      <body>
        <table id="compact"><caption>Compact</caption><tr><th scope="col">A</th><th scope="col">B</th></tr><tr><td>1</td><td>2</td></tr></table>
        <table id="wide" style="width: 1400px"><caption>Wide facts</caption><tr><th>One</th><th>Two</th><th>Three</th></tr><tr><td>Long content</td><td>Long content</td><td>Long content</td></tr></table>
        <table id="presentational" role="presentation"><tr><td>Layout only</td></tr></table>
        <table id="role-none" role="none"><tr><td>Layout only</td></tr></table>
        <table id="responsive-infobox" class="infobox"><tr><td>Infobox</td></tr></table>
        <div class="infobox"><table id="infobox-child"><tr><td>Infobox child</td></tr></table></div>
        <div class="pcs-collapse-table-container"><table id="pcs-container"><tr><td>PCS container</td></tr></table></div>
        <div class="pcs-collapse-table-content"><table id="pcs-content"><tr><td>PCS content</td></tr></table></div>
        <div class="pcs-table-other"><table id="pcs-other"><tr><td>PCS other</td></tr></table></div>
        <div class="pcs-table-scroll"><table id="pcs-scroll"><tr><td>PCS scroll</td></tr></table></div>
        <div class="pcs-horizontal-scroll"><table id="pcs-horizontal-scroll"><tr><td>PCS horizontal scroll</td></tr></table></div>
        <div class="mw-table-scroll"><table id="mw-scroll"><tr><td>MediaWiki scroll</td></tr></table></div>
        <table id="pcs-infobox" class="pcs-table-infobox"><tr><td>PCS infobox</td></tr></table>
        <table id="outer"><tr><td><table id="nested"><tr><td id="nested-surface" style="background: #14213d">Nested layout</td></tr></table></td></tr></table>

        <h2 id="population-heading">Population</h2>
        <span id="growth-label">Growth</span>
        <table id="caption-priority" aria-labelledby="population-heading" aria-label="Authored label" style="width: 1400px"><caption>Caption wins</caption><tr><td>People</td></tr></table>
        <table id="labelledby-priority" aria-labelledby="population-heading growth-label" aria-label="Authored label" style="width: 1400px"><tr><td>People</td></tr></table>
        <table id="authored-label-priority" aria-labelledby="missing-label" aria-label="Authored summary" style="width: 1400px"><tr><td>People</td></tr></table>
        <section><h3>Demographics</h3><table id="section-priority" style="width: 1400px"><tr><td>People</td></tr></table></section>
        <table id="default-label" style="width: 1400px"><tr><td>People</td></tr></table>
        <table id="rtl" dir="rtl"><tr><td>مرحبا</td></tr></table>
        <table id="semantic-colors">
          <tr><td id="light-surface" style="background-color: #fff28f; background-image: linear-gradient(#fff28f, #f4cf52); color: #cc0000; text-align: right"><a id="light-link" href="#">Light</a></td></tr>
          <tr><td id="dark-surface" style="background: #14213d"><a id="dark-link" href="#">Dark</a></td></tr>
          <tr><td id="translucent-surface" style="background: rgba(20, 33, 61, 0.5)">Translucent</td></tr>
        </table>
      </body>
    </html>
    """

    private static let tableMetricsScript = """
    JSON.stringify((function () {
        const compact = document.querySelector('#compact');
        const compactWrapper = compact.parentElement;
        const compactStyle = getComputedStyle(compact);
        const compactCellStyle = getComputedStyle(compact.querySelector('td'));
        const wide = document.querySelector('#wide');
        const wideWrapper = wide.parentElement;
        const wideWrapperStyle = getComputedStyle(wideWrapper);
        const wideStyle = getComputedStyle(wide);
        const lightSurface = document.querySelector('#light-surface');
        const lightLinkStyle = getComputedStyle(document.querySelector('#light-link'));
        const pcsContent = document.querySelector('.pcs-collapse-table-content');
        const wrapperLabel = function (id) {
            return document.querySelector(id).parentElement.getAttribute('aria-label');
        };
        return {
            compactWrapped: compactWrapper.classList.contains('macwiki-table-scroll'),
            compactIsIntrinsic: compactWrapper.clientWidth < document.body.clientWidth,
            compactIsFocusable: compactWrapper.hasAttribute('tabindex'),
            wideWrapped: wideWrapper.classList.contains('macwiki-table-scroll'),
            wideEnhancedAsDataTable: wide.classList.contains('macwiki-reader-data-table'),
            wideIsBounded: wideWrapper.clientWidth <= document.body.clientWidth,
            wideOverflows: wide.scrollWidth > wideWrapper.clientWidth,
            wideTabIndex: wideWrapper.getAttribute('tabindex'),
            wideRole: wideWrapper.getAttribute('role'),
            wrapperOverflowX: wideWrapperStyle.overflowX,
            wideTableMinimumWidth: wideStyle.minWidth,
            wideTableMaximumWidth: wideStyle.maxWidth,
            captionMatchesTable: getComputedStyle(compact.querySelector('caption')).fontSize === compactStyle.fontSize,
            captionIsAboveTable: getComputedStyle(compact.querySelector('caption')).captionSide === 'top',
            tableUsesEditorialScale: parseFloat(compactStyle.fontSize) < parseFloat(getComputedStyle(document.body).fontSize),
            cellHasInlinePadding: parseFloat(compactCellStyle.paddingInlineStart) > 0 && parseFloat(compactCellStyle.paddingInlineEnd) > 0,
            desktopCellInlinePadding: parseFloat(compactCellStyle.paddingInlineStart),
            presentationalWrapped: document.querySelector('#presentational').parentElement.classList.contains('macwiki-table-scroll'),
            roleNoneWrapped: document.querySelector('#role-none').parentElement.classList.contains('macwiki-table-scroll'),
            infoboxWrapped: document.querySelector('#responsive-infobox').parentElement.classList.contains('macwiki-table-scroll'),
            infoboxChildWrapped: document.querySelector('#infobox-child').parentElement.classList.contains('macwiki-table-scroll'),
            pcsInfoboxWrapped: document.querySelector('#pcs-infobox').parentElement.classList.contains('macwiki-table-scroll'),
            pcsContainerWrapped: document.querySelector('#pcs-container').parentElement.classList.contains('macwiki-table-scroll'),
            pcsContentWrapped: document.querySelector('#pcs-content').parentElement.classList.contains('macwiki-table-scroll'),
            pcsOtherWrapped: document.querySelector('#pcs-other').parentElement.classList.contains('macwiki-table-scroll'),
            pcsScrollWrapped: document.querySelector('#pcs-scroll').parentElement.classList.contains('macwiki-table-scroll'),
            pcsHorizontalScrollWrapped: document.querySelector('#pcs-horizontal-scroll').parentElement.classList.contains('macwiki-table-scroll'),
            mediaWikiScrollWrapped: document.querySelector('#mw-scroll').parentElement.classList.contains('macwiki-table-scroll'),
            nestedWrapped: document.querySelector('#nested').parentElement.classList.contains('macwiki-table-scroll'),
            nestedSurfaceClassified: document.querySelector('#nested-surface').classList.contains('macwiki-authored-dark-surface'),
            captionPriorityName: wrapperLabel('#caption-priority'),
            labelledByPriorityName: wrapperLabel('#labelledby-priority'),
            authoredLabelPriorityName: wrapperLabel('#authored-label-priority'),
            sectionPriorityName: wrapperLabel('#section-priority'),
            defaultName: wrapperLabel('#default-label'),
            rtlDirection: document.querySelector('#rtl').parentElement.getAttribute('dir'),
            defaultDirectionAbsent: !compactWrapper.hasAttribute('dir'),
            lightSurfaceClassified: lightSurface.classList.contains('macwiki-authored-light-surface'),
            darkSurfaceClassified: document.querySelector('#dark-surface').classList.contains('macwiki-authored-dark-surface'),
            translucentSurfaceUnclassified: !document.querySelector('#translucent-surface').classList.contains('macwiki-authored-light-surface') &&
                !document.querySelector('#translucent-surface').classList.contains('macwiki-authored-dark-surface'),
            lightLinkColor: lightLinkStyle.color,
            darkLinkColor: getComputedStyle(document.querySelector('#dark-link')).color,
            authoredTextColor: getComputedStyle(lightSurface).color,
            authoredBackgroundColor: getComputedStyle(lightSurface).backgroundColor,
            authoredBackgroundImagePreserved: getComputedStyle(lightSurface).backgroundImage !== 'none',
            authoredAlignment: getComputedStyle(lightSurface).textAlign,
            authoredLinkUnderlined: lightLinkStyle.textDecorationLine === 'underline',
            pcsContentScrolls: getComputedStyle(pcsContent).overflowX === 'auto',
            pcsTableRemainsUnclassified: !document.querySelector('#pcs-content').classList.contains('macwiki-reader-data-table')
        };
    })())
    """

    private static let compactMetricsScript = """
    JSON.stringify((function () {
        const infobox = document.querySelector('#responsive-infobox');
        const compact = document.querySelector('#compact');
        const wrapper = compact.parentElement;
        const infoboxStyle = getComputedStyle(infobox);
        return {
            compactMediaMatches: matchMedia('(max-width: 620px)').matches,
            infoboxFloat: infoboxStyle.float,
            infoboxFillsReader: Math.abs(infobox.getBoundingClientRect().width - infobox.parentElement.getBoundingClientRect().width) < 2,
            wrapperBorderRadius: getComputedStyle(wrapper).borderRadius,
            cellInlinePadding: parseFloat(getComputedStyle(compact.querySelector('td')).paddingInlineStart)
        };
    })())
    """

    private static let observerMetricsScript = """
    JSON.stringify((function () {
        const metrics = window.__macwikiObserverMetrics;
        const wrapperCount = document.querySelectorAll('.macwiki-table-scroll').length;
        return {
            nativeResizeObserverAvailable: metrics.nativeResizeObserverAvailable,
            observerInstances: metrics.instances,
            observedEveryWrapperAndTable: metrics.observeCalls === wrapperCount * 2,
            disconnects: metrics.disconnects
        };
    })())
    """

    private static let focusCleanupMetricsScript = """
    JSON.stringify((function () {
        const wide = document.querySelector('#wide');
        const wrapper = wide.parentElement;
        return {
            stillOverflows: wide.scrollWidth > wrapper.clientWidth + 1,
            hasOverflowClass: wrapper.classList.contains('macwiki-table-scroll--overflowing'),
            hasOverflowDataset: wrapper.dataset.macwikiTableOverflow === 'true',
            tabIndex: wrapper.getAttribute('tabindex'),
            role: wrapper.getAttribute('role'),
            ariaLabel: wrapper.getAttribute('aria-label')
        };
    })())
    """

    private static let fallbackMetricsScript = """
    JSON.stringify({
        resizeListenerAdds: window.__macwikiFallbackMetrics.resizeListenerAdds,
        resizeListenerRemovals: window.__macwikiFallbackMetrics.resizeListenerRemovals
    })
    """

    private static let cssOMContractsScript = """
    JSON.stringify((function () {
        const records = [];
        const visit = function (rules, media) {
            Array.from(rules || []).forEach(function (rule) {
                if (rule.type === CSSRule.MEDIA_RULE) {
                    visit(rule.cssRules, rule.conditionText);
                } else if (rule.type === CSSRule.STYLE_RULE) {
                    records.push({
                        media: media || '',
                        selector: rule.selectorText,
                        style: rule.style
                    });
                }
            });
        };
        Array.from(document.styleSheets).forEach(function (sheet) {
            visit(sheet.cssRules, '');
        });
        const hasRule = function (media, selectorFragment, predicate) {
            return records.some(function (record) {
                return record.media === media &&
                    record.selector.includes(selectorFragment) &&
                    predicate(record.style);
            });
        };
        return {
            focusVisibleOutline: hasRule('', '.macwiki-table-scroll:focus-visible', function (style) {
                return style.outline.includes('2px') &&
                    style.outline.includes('solid') &&
                    style.outlineOffset === '2px';
            }),
            increasedContrastBorder: hasRule('(prefers-contrast: more)', '.macwiki-table-scroll', function (style) {
                return style.borderWidth === '2px';
            }),
            forcedColorsSurface: hasRule('(forced-colors: active)', '.macwiki-table-scroll', function (style) {
                return style.background.toLowerCase() === 'canvas' &&
                    style.getPropertyValue('border-color').toLowerCase().includes('canvastext');
            }),
            forcedColorsFocusHighlight: hasRule('(forced-colors: active)', '.macwiki-table-scroll:focus-visible', function (style) {
                return style.outlineColor.toLowerCase() === 'highlight';
            })
        };
    })())
    """
}
