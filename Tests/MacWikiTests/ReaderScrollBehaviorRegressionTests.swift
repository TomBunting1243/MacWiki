import Foundation
import Testing
import WebKit

@testable import MacWiki

@MainActor
@Suite(.serialized)
struct ReaderScrollBehaviorRegressionTests {
    @Test func resizeRefreshesTelemetryWithoutForcingReaderPosition() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <div id="content" style="height:3000px"></div>
            </body></html>
            """,
            messageNames: ["scrollChanged"]
        )
        _ = try await fixture.webView.evaluateJavaScript("window.scrollTo(0, 600)")
        try await Task.sleep(for: .milliseconds(100))
        let beforeY = try #require(
            (try await fixture.webView.evaluateJavaScript("window.scrollY") as? NSNumber)?.doubleValue
        )

        fixture.messages.removeAll()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            document.querySelector('#content').style.height = '6000px';
            window.dispatchEvent(new Event('resize'));
            """
        )
        try await waitForMessage(named: "scrollChanged", in: fixture.messages)
        try await Task.sleep(for: .milliseconds(120))

        let afterY = try #require(
            (try await fixture.webView.evaluateJavaScript("window.scrollY") as? NSNumber)?.doubleValue
        )
        let geometry = try #require(
            try await fixture.webView.evaluateJavaScript(
                """
                ({
                  y: window.scrollY,
                  maxScroll: Math.max(
                    document.documentElement.scrollHeight,
                    document.body.scrollHeight
                  ) - window.innerHeight
                })
                """
            ) as? [String: Any]
        )
        let y = try #require((geometry["y"] as? NSNumber)?.doubleValue)
        let maxScroll = try #require((geometry["maxScroll"] as? NSNumber)?.doubleValue)
        let payload = try #require(fixture.messages.payloads(named: "scrollChanged").last)
        let reportedProgress = try #require((payload["progress"] as? NSNumber)?.doubleValue)

        #expect(abs(afterY - beforeY) < 1)
        #expect(abs(reportedProgress - (y / maxScroll)) < 0.03)
    }

    @Test func tocUsesOneInterruptibleNativeSmoothScroll() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <div style="height:4000px"></div>
            </body></html>
            """
        )

        let outcome = try #require(
            try await fixture.webView.callAsyncJavaScript(
                """
                return await new Promise(function (resolve) {
                  var calls = [];
                  window.scrollTo = function () {
                    if (arguments.length === 1 && typeof arguments[0] === 'object') {
                      calls.push({
                        kind: 'options',
                        top: Number(arguments[0].top),
                        behavior: String(arguments[0].behavior || '')
                      });
                    } else {
                      calls.push({
                        kind: 'coordinates',
                        top: Number(arguments[1]),
                        behavior: ''
                      });
                    }
                  };

                  var didStart = window._macwikiSmoothScrollToY(720, {
                    nativeSmooth: true,
                    durationMs: 320,
                    onComplete: function (didReachTarget) {
                      resolve({
                        didStart: didStart,
                        didReachTarget: didReachTarget,
                        calls: calls
                      });
                    }
                  });
                  setTimeout(function () {
                    window.dispatchEvent(new WheelEvent('wheel', {
                      deltaY: 12,
                      deltaMode: 0
                    }));
                  }, 20);
                });
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? [String: Any]
        )
        let calls = try #require(outcome["calls"] as? [[String: Any]])
        let firstCall = try #require(calls.first)

        #expect(outcome["didStart"] as? Bool == true)
        #expect(outcome["didReachTarget"] as? Bool == false)
        #expect(calls.count == 1)
        #expect(firstCall["kind"] as? String == "options")
        #expect(firstCall["behavior"] as? String == "smooth")
    }

    @Test func tocScrollAwaitsSettlementAndMutesIntermediateSections() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <div style="height:900px"></div>
              <h2 id="target">Target</h2>
              <div style="height:1800px"></div>
            </body></html>
            """,
            messageNames: ["scrollChanged"]
        )

        let scrollOutcome = try #require(
            try await fixture.webView.callAsyncJavaScript(
                """
                var capturedOptions = null;
                window._macwikiSmoothScrollToY = function (target, options) {
                  capturedOptions = options;
                  setTimeout(function () { options.onComplete(true); }, 60);
                  return true;
                };
                var didSettle = false;
                var request = window.scrollToSection('target').then(function (value) {
                  didSettle = true;
                  return value;
                });
                await new Promise(function (resolve) { setTimeout(resolve, 10); });
                var settledEarly = didSettle;
                var result = await request;
                return {
                  settledEarly: settledEarly,
                  result: result,
                  reason: capturedOptions && capturedOptions.reason,
                  nativeSmooth: capturedOptions && capturedOptions.nativeSmooth
                };
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? [String: Any]
        )

        #expect(scrollOutcome["settledEarly"] as? Bool == false)
        #expect(scrollOutcome["result"] as? Bool == true)
        #expect(scrollOutcome["reason"] as? String == "toc")
        #expect(scrollOutcome["nativeSmooth"] as? Bool == true)

        fixture.messages.removeAll()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            window.__macwikiVisibleSectionCalls = 0;
            window.currentVisibleSectionId = function () {
              window.__macwikiVisibleSectionCalls += 1;
              return 'target';
            };
            window._macwikiSetProgrammaticScrollMode(600);
            window.setScrollTelemetrySectionTrackingEnabled(true);
            """
        )
        try await waitForMessage(named: "scrollChanged", in: fixture.messages)
        let mutedPayload = try #require(fixture.messages.payloads(named: "scrollChanged").last)
        let mutedLookupCount = try #require(
            (try await fixture.webView.evaluateJavaScript(
                "window.__macwikiVisibleSectionCalls"
            ) as? NSNumber)?.intValue
        )

        #expect(mutedPayload["programmatic"] as? Bool == true)
        #expect(mutedPayload["sectionId"] == nil)
        #expect(mutedLookupCount == 0)

        fixture.messages.removeAll()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            window.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown' }));
            window.setScrollTelemetrySectionTrackingEnabled(true);
            """
        )
        try await waitForMessage(named: "scrollChanged", in: fixture.messages)
        let settledPayload = try #require(fixture.messages.payloads(named: "scrollChanged").last)
        let settledLookupCount = try #require(
            (try await fixture.webView.evaluateJavaScript(
                "window.__macwikiVisibleSectionCalls"
            ) as? NSNumber)?.intValue
        )

        #expect(settledPayload["programmatic"] as? Bool == false)
        #expect(settledPayload["sectionId"] as? String == "target")
        #expect(settledLookupCount > 0)
    }

    @Test func visibleSectionStartsEmptyBeforeFirstHeadingThreshold() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <div style="height:400px"></div>
              <h2 id="first">First</h2>
              <div style="height:1200px"></div>
            </body></html>
            """
        )

        let startsEmpty = try await fixture.webView.evaluateJavaScript(
            "window.currentVisibleSectionId() === null"
        ) as? Bool
        _ = try await fixture.webView.evaluateJavaScript(
            "window.scrollTo(0, document.querySelector('#first').offsetTop - 80)"
        )
        let visible = try await fixture.webView.evaluateJavaScript(
            "window.currentVisibleSectionId()"
        ) as? String

        #expect(startsEmpty == true)
        #expect(visible == "first")
    }

    @Test func visibleSectionSelfCorrectsAfterLateDocumentLayoutShift() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <div id="late" style="height:0"></div>
              <h2 id="biography">Biography</h2><div style="height:900px"></div>
              <h2 id="death">Death</h2><div style="height:900px"></div>
              <h2 id="work">Work</h2><div style="height:900px"></div>
              <h2 id="legacy">Legacy</h2><div style="height:900px"></div>
            </body></html>
            """
        )

        _ = try await fixture.webView.evaluateJavaScript("window.currentVisibleSectionId()")
        _ = try await fixture.webView.evaluateJavaScript(
            "document.querySelector('#late').style.height = '2400px'"
        )
        _ = try await fixture.webView.evaluateJavaScript(
            "window.scrollTo(0, document.querySelector('#legacy').offsetTop - 80)"
        )
        let visible = try await fixture.webView.evaluateJavaScript(
            "window.currentVisibleSectionId()"
        ) as? String

        #expect(visible == "legacy")
    }

    @Test func highlightNavigationUsesReducedMotionAwareSharedScrollPath() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <div style="height:4000px"></div>
            </body></html>
            """
        )

        let outcome = try #require(
            try await fixture.webView.callAsyncJavaScript(
                """
                window._macwikiHighlightRanges = {
                  highlight: {
                    range: {
                      getBoundingClientRect: function () { return { top: 900 }; }
                    }
                  }
                };
                window.matchMedia = function (query) {
                  return { matches: query === '(prefers-reduced-motion: reduce)' };
                };
                var calls = [];
                window.scrollTo = function () {
                  calls.push({
                    kind: arguments.length === 1 ? 'options' : 'coordinates',
                    top: Number(arguments.length === 1 ? arguments[0].top : arguments[1]),
                    behavior: arguments.length === 1 ? String(arguments[0].behavior || '') : ''
                  });
                };
                var captured = null;
                var sharedScroll = window._macwikiSmoothScrollToY;
                window._macwikiSmoothScrollToY = function (target, options) {
                  captured = {
                    target: target,
                    reason: options.reason,
                    nativeSmooth: options.nativeSmooth
                  };
                  return sharedScroll(target, options);
                };
                var didStart = window.scrollToHighlight('highlight');
                await new Promise(function (resolve) { setTimeout(resolve, 45); });
                return { didStart: didStart, captured: captured, calls: calls };
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? [String: Any]
        )
        let captured = try #require(outcome["captured"] as? [String: Any])
        let calls = try #require(outcome["calls"] as? [[String: Any]])
        let firstCall = try #require(calls.first)

        #expect(outcome["didStart"] as? Bool == true)
        #expect(captured["reason"] as? String == "highlight")
        #expect(captured["nativeSmooth"] as? Bool == true)
        #expect(firstCall["kind"] as? String == "coordinates")
        #expect(firstCall["behavior"] as? String == "")
    }

    @Test func readerAppearanceInvalidatesLayoutAndPublishesFreshTelemetry() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <h2 id="first">First</h2>
              <div style="height:2400px"></div>
            </body></html>
            """,
            messageNames: ["scrollChanged"]
        )
        fixture.messages.removeAll()

        let outcome = try #require(
            try await fixture.webView.callAsyncJavaScript(
                """
                var invalidations = 0;
                var invalidateHeadingCache = window._invalidateHeadingCache;
                window._invalidateHeadingCache = function () {
                  invalidations += 1;
                  invalidateHeadingCache();
                };
                var didApply = window.setReaderAppearance({
                  fontSize: '19px',
                  lineHeight: '1.65',
                  contentWidth: '720px'
                });
                await new Promise(function (resolve) {
                  requestAnimationFrame(function () {
                    requestAnimationFrame(resolve);
                  });
                });
                return {
                  didApply: didApply,
                  invalidations: invalidations,
                  fontSize: document.documentElement.style.getPropertyValue('--reader-font-size'),
                  lineHeight: document.documentElement.style.getPropertyValue('--reader-line-height'),
                  contentWidth: document.documentElement.style.getPropertyValue('--reader-max-width')
                };
                """,
                arguments: [:],
                in: nil,
                contentWorld: .page
            ) as? [String: Any]
        )
        try await waitForMessage(named: "scrollChanged", in: fixture.messages)

        #expect(outcome["didApply"] as? Bool == true)
        #expect((outcome["invalidations"] as? NSNumber)?.intValue ?? 0 > 0)
        #expect(outcome["fontSize"] as? String == "19px")
        #expect(outcome["lineHeight"] as? String == "1.65")
        #expect(outcome["contentWidth"] as? String == "720px")
        #expect(!fixture.messages.payloads(named: "scrollChanged").isEmpty)
    }

    @Test func cachedSectionTrackingDoesNotIncreaseBridgeCadence() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body style="margin:0">
              <div style="height:2400px"></div>
            </body></html>
            """,
            messageNames: ["scrollChanged", "scrollPerfSnapshot"],
            beforeScript: """
            window.__macwikiTestNow = 1000;
            Date.now = function () { return window.__macwikiTestNow; };
            """
        )

        fixture.messages.removeAll()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            window.__macwikiTestNow = 3000;
            window.setScrollTelemetrySectionTrackingEnabled(false);
            """
        )
        try await waitForMessage(named: "scrollPerfSnapshot", in: fixture.messages)
        let disabledSnapshot = try #require(
            fixture.messages.payloads(named: "scrollPerfSnapshot").last
        )

        fixture.messages.removeAll()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            window.__macwikiVisibleSectionID = 'alpha';
            window.currentVisibleSectionId = function () {
              return window.__macwikiVisibleSectionID;
            };
            window.__macwikiTestNow = 5000;
            window.setScrollTelemetrySectionTrackingEnabled(true);
            """
        )
        try await waitForMessage(named: "scrollPerfSnapshot", in: fixture.messages)
        try await waitForMessage(named: "scrollChanged", in: fixture.messages)
        let enabledSnapshot = try #require(
            fixture.messages.payloads(named: "scrollPerfSnapshot").last
        )
        let enabledScroll = try #require(
            fixture.messages.payloads(named: "scrollChanged").last
        )

        #expect(disabledSnapshot["throttleMs"] as? NSNumber == enabledSnapshot["throttleMs"] as? NSNumber)
        #expect(disabledSnapshot["sectionTrackingEnabled"] as? Bool == false)
        #expect(enabledSnapshot["sectionTrackingEnabled"] as? Bool == true)
        #expect(enabledScroll["sectionId"] as? String == "alpha")

        try await Task.sleep(for: .milliseconds(260))
        fixture.messages.removeAll()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            window.__macwikiTestNow = 5300;
            window.setScrollTelemetrySectionTrackingEnabled(true);
            """
        )
        try await waitForMessage(named: "scrollChanged", in: fixture.messages)
        let repeatedSectionPayloads = fixture.messages.payloads(named: "scrollChanged")
        #expect(repeatedSectionPayloads.allSatisfy { $0["sectionId"] == nil })

        try await Task.sleep(for: .milliseconds(260))
        fixture.messages.removeAll()
        _ = try await fixture.webView.evaluateJavaScript(
            """
            window.__macwikiVisibleSectionID = 'beta';
            window.__macwikiTestNow = 5600;
            window.setScrollTelemetrySectionTrackingEnabled(true);
            """
        )
        try await waitForMessage(named: "scrollChanged", in: fixture.messages)
        let changedSectionPayload = try #require(
            fixture.messages.payloads(named: "scrollChanged").last
        )
        #expect(changedSectionPayload["sectionId"] as? String == "beta")
    }

    private struct Fixture {
        let webView: WKWebView
        let messages: WebViewScriptMessageCollector
    }

    private func makeFixture(
        html: String,
        messageNames: [String] = [],
        beforeScript: String? = nil
    ) async throws -> Fixture {
        let configuration = WKWebViewConfiguration()
        let messages = WebViewScriptMessageCollector()
        for name in messageNames {
            configuration.userContentController.add(messages, name: name)
        }

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 700),
            configuration: configuration
        )
        webView.loadHTMLString(html, baseURL: nil)

        var didLoad = false
        for _ in 0..<200 {
            let isReady = (try? await webView.evaluateJavaScript(
                "document.readyState === 'complete'"
            )) as? Bool == true
            if isReady, !webView.isLoading {
                didLoad = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(didLoad)

        // Offscreen WKWebViews can suspend animation frames. Keep the production
        // frame-driven code executable in tests with an equivalent timer-backed queue.
        _ = try await webView.evaluateJavaScript(
            """
            window.requestAnimationFrame = function (callback) {
              return setTimeout(function () { callback(performance.now()); }, 0);
            };
            window.cancelAnimationFrame = function (identifier) {
              clearTimeout(identifier);
            };
            true;
            """
        )
        if let beforeScript {
            _ = try await webView.evaluateJavaScript(beforeScript + "\ntrue;")
        }
        _ = try await webView.evaluateJavaScript(WebViewResources.scriptSource)
        return Fixture(webView: webView, messages: messages)
    }

    private func waitForMessage(
        named name: String,
        in messages: WebViewScriptMessageCollector
    ) async throws {
        for _ in 0..<100 {
            if !messages.payloads(named: name).isEmpty {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for WebView message named \(name)")
    }
}

@MainActor
private final class WebViewScriptMessageCollector: NSObject, WKScriptMessageHandler {
    private var messagesByName: [String: [Any]] = [:]

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        messagesByName[message.name, default: []].append(message.body)
    }

    func payloads(named name: String) -> [[String: Any]] {
        messagesByName[name, default: []].compactMap { $0 as? [String: Any] }
    }

    func removeAll() {
        messagesByName.removeAll(keepingCapacity: true)
    }
}
