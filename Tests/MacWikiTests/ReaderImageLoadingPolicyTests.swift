import Foundation
import SwiftUI
import Testing
import WebKit

@testable import MacWiki

@MainActor
@Suite(.serialized)
struct ReaderImageLoadingPolicyTests {
    @Test func initialPreparationFrontloadsThreeImagesBeforeIdleWork() async throws {
        let fixture = try await makeFixture(
            html: imageDocument(count: 8),
            capturesIdleWork: true
        )

        try await fixture.waitUntil(
            "document.querySelectorAll('[data-macwiki-layout-reserved=\"1\"]').length === 3",
            attempts: 200
        )

        let initialState = try #require(
            try await fixture.webView.evaluateJavaScript(
                """
                ({
                  prepared: document.querySelectorAll('[data-macwiki-layout-reserved="1"]').length,
                  pendingIdleWork: window.__macwikiIdleCallbacks.length
                })
                """
            ) as? [String: Any]
        )

        #expect((initialState["prepared"] as? NSNumber)?.intValue == 3)
        #expect((initialState["pendingIdleWork"] as? NSNumber)?.intValue == 1)
    }

    @Test func idleContinuationFinishesOnlyTheBoundedLargeDocumentSet() async throws {
        let fixture = try await makeFixture(
            html: imageDocument(count: 250),
            capturesIdleWork: true
        )

        try await fixture.waitUntil(
            "window.__macwikiIdleCallbacks.length === 1",
            attempts: 200
        )
        try await drainIdleWork(in: fixture)

        let completedState = try #require(
            try await fixture.webView.evaluateJavaScript(
                """
                ({
                  prepared: document.querySelectorAll('[data-macwiki-layout-reserved="1"]').length,
                  skeletons: document.querySelectorAll('[data-macwiki-image-skeleton="1"]').length,
                  untouched: Array.from(document.images)
                    .filter(function (image) { return image.dataset.macwikiLayoutReserved !== '1'; })
                    .length,
                  pendingIdleWork: window.__macwikiIdleCallbacks.length
                })
                """
            ) as? [String: Any]
        )

        #expect((completedState["prepared"] as? NSNumber)?.intValue == 220)
        #expect((completedState["skeletons"] as? NSNumber)?.intValue == 48)
        #expect((completedState["untouched"] as? NSNumber)?.intValue == 30)
        #expect((completedState["pendingIdleWork"] as? NSNumber)?.intValue == 0)
    }

    @Test func runtimePreparationPreservesNativeLoadingAndFetchPriorityHints() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body>
              <img id="automatic" width="200" height="100">
              <img id="deferred" width="200" height="100" loading="lazy" fetchpriority="low">
              <img id="priority" width="200" height="100" loading="eager" fetchpriority="high">
              <img id="fourth" width="200" height="100" loading="lazy">
            </body></html>
            """,
            capturesIdleWork: true,
            documentStartScript: """
            window.__macwikiFetchHintMutations = [];
            document.addEventListener('DOMContentLoaded', function () {
              window.__macwikiFetchHintObserver = new MutationObserver(function (records) {
                records.forEach(function (record) {
                  window.__macwikiFetchHintMutations.push({
                    id: record.target.id,
                    attribute: record.attributeName
                  });
                });
              });
              window.__macwikiFetchHintObserver.observe(document.body, {
                attributes: true,
                subtree: true,
                attributeFilter: ['loading', 'fetchpriority']
              });
            }, { once: true });
            """
        )

        try await fixture.waitUntil(
            "window.__macwikiIdleCallbacks.length === 1",
            attempts: 200
        )
        try await drainIdleWork(in: fixture)

        let hintsWerePreserved = try await fixture.webView.evaluateJavaScript(
            """
            (function () {
              var automatic = document.querySelector('#automatic');
              var deferred = document.querySelector('#deferred');
              var priority = document.querySelector('#priority');
              var fourth = document.querySelector('#fourth');
              return window.__macwikiFetchHintMutations.length === 0 &&
                !automatic.hasAttribute('loading') &&
                !automatic.hasAttribute('fetchpriority') &&
                deferred.getAttribute('loading') === 'lazy' &&
                deferred.getAttribute('fetchpriority') === 'low' &&
                priority.getAttribute('loading') === 'eager' &&
                priority.getAttribute('fetchpriority') === 'high' &&
                fourth.getAttribute('loading') === 'lazy' &&
                !fourth.hasAttribute('fetchpriority');
            })()
            """
        ) as? Bool

        #expect(hintsWerePreserved == true)
    }

    @Test func initialDocumentHintsOnlyPrioritizeTheFirstThreeImages() throws {
        let html = """
        <html><body>
          <img id="first" src="1.jpg">
          <img id="second" src="2.jpg" loading='lazy'>
          <img id="third" src="3.jpg" decoding="sync" fetchpriority="low">
          <img id="fourth" src="4.jpg">
          <img id="fifth" src="5.jpg" loading="eager" decoding="auto" fetchpriority="high">
        </body></html>
        """
        let coordinator = WebView.Coordinator(
            tabID: UUID(),
            onLinkTapped: nil,
            onOpenArticleInNewWindow: nil,
            scrollPosition: .constant(0),
            onScrollProgress: nil,
            fallbackScrollProgress: nil,
            appState: nil,
            modelContext: nil,
            onTextSelected: nil,
            onSelectionCleared: nil,
            highlights: [],
            articleTitle: "Images",
            contentRevision: 0,
            readerAppearance: .default,
            readerTopInset: 56,
            preferImmediateReveal: false,
            onTableOfContentsUpdate: nil,
            onReferencesUpdate: nil,
            onVisibleSectionChange: nil,
            onContentReveal: nil,
            onLinkHoverPreviewChange: nil,
            linkPreviewImmediateModifier: .default,
            nativeHighlightingMenuEnabled: false
        )

        let prepared = coordinator.prepareHTMLForInitialLoad(
            html,
            articleTitle: "Images",
            htmlSignature: ReaderDocumentRevision.digest(for: html)
        )
        let first = try imageTag(withID: "first", in: prepared)
        let second = try imageTag(withID: "second", in: prepared)
        let third = try imageTag(withID: "third", in: prepared)
        let fourth = try imageTag(withID: "fourth", in: prepared)
        let fifth = try imageTag(withID: "fifth", in: prepared)

        #expect(first.contains(#"loading="eager""#))
        #expect(first.contains(#"decoding="async""#))
        #expect(first.contains(#"fetchpriority="high""#))
        #expect(second.contains("loading='lazy'"))
        #expect(second.contains(#"decoding="async""#))
        #expect(second.contains(#"fetchpriority="high""#))
        #expect(third.contains(#"loading="eager""#))
        #expect(third.contains(#"decoding="sync""#))
        #expect(third.contains(#"fetchpriority="low""#))
        #expect(fourth.contains(#"loading="lazy""#))
        #expect(fourth.contains(#"decoding="async""#))
        #expect(fourth.contains(#"fetchpriority="auto""#))
        #expect(fifth.contains(#"loading="eager""#))
        #expect(fifth.contains(#"decoding="auto""#))
        #expect(fifth.contains(#"fetchpriority="high""#))
    }

    @Test func unknownDimensionImagesNeverReceiveSyntheticSkeletons() async throws {
        let fixture = try await makeFixture(
            html: """
            <!doctype html><html><body>
              <img id="unknown">
              <img id="known" width="200" height="100">
            </body></html>
            """
        )

        try await fixture.waitUntil(
            "document.querySelector('#known').dataset.macwikiFadePrepared === '1'",
            attempts: 200
        )

        let imageState = try #require(
            try await fixture.webView.evaluateJavaScript(
                """
                ({
                  unknownWasVisited: document.querySelector('#unknown').dataset.macwikiLayoutReserved === '1',
                  unknownHasFade: document.querySelector('#unknown').dataset.macwikiFadePrepared === '1',
                  unknownHasSkeleton: document.querySelector('#unknown').dataset.macwikiImageSkeleton === '1',
                  knownHasSkeleton: document.querySelector('#known').dataset.macwikiImageSkeleton === '1'
                })
                """
            ) as? [String: Any]
        )

        #expect(imageState["unknownWasVisited"] as? Bool == true)
        #expect(imageState["unknownHasFade"] as? Bool == false)
        #expect(imageState["unknownHasSkeleton"] as? Bool == false)
        #expect(imageState["knownHasSkeleton"] as? Bool == true)
    }

    private func imageTag(withID id: String, in html: String) throws -> String {
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        let regex = try NSRegularExpression(
            pattern: #"<img\b[^>]*\bid\s*=\s*(["'])"# + escapedID + #"\1[^>]*>"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let match = try #require(regex.firstMatch(in: html, range: range))
        let swiftRange = try #require(Range(match.range, in: html))
        return String(html[swiftRange])
    }

    private func imageDocument(count: Int) -> String {
        let images = (0..<count)
            .map { #"<img id="image-\#($0)" width="200" height="100">"# }
            .joined(separator: "\n")
        return "<!doctype html><html><body>\(images)</body></html>"
    }

    private func makeFixture(
        html: String,
        capturesIdleWork: Bool = false,
        documentStartScript: String? = nil
    ) async throws -> ReaderWebKitHarness {
        let fixtureID = UUID().uuidString
        let fixtureMarker = """
        <script>
          document.documentElement.dataset.macwikiImageFixture = '\(fixtureID)';
        </script>
        """
        let markedHTML = html.replacingOccurrences(
            of: "</body>",
            with: fixtureMarker + "</body>",
            options: [.caseInsensitive]
        )
        var documentStartScripts: [String] = []
        if capturesIdleWork {
            documentStartScripts.append(Self.idleCallbackCaptureScript)
        }
        if let documentStartScript {
            documentStartScripts.append(documentStartScript)
        }
        let fixture = ReaderWebKitHarness(
            size: CGSize(width: 640, height: 700),
            documentStartScripts: documentStartScripts,
            injectReaderStyle: false,
            injectWebViewScript: true
        )
        try await fixture.loadHTML(markedHTML)
        try await fixture.waitUntil(
            """
            document.readyState === 'complete' &&
              document.documentElement.dataset.macwikiImageFixture === '\(fixtureID)'
            """,
            attempts: 200
        )
        return fixture
    }

    private func drainIdleWork(in fixture: ReaderWebKitHarness) async throws {
        for _ in 0..<16 {
            let didRunCallback = try await fixture.evaluateBool(
                """
                (function () {
                  var pending = window.__macwikiIdleCallbacks.shift();
                  if (!pending) return false;
                  pending.callback({
                    didTimeout: false,
                    timeRemaining: function () { return 50; }
                  });
                  return true;
                })()
                """
            )
            if !didRunCallback {
                return
            }
        }

        Issue.record("Reader image preparation did not exhaust its idle work")
    }

    private static let idleCallbackCaptureScript = """
    window.__macwikiIdleCallbacks = [];
    window.requestIdleCallback = function (callback, options) {
      window.__macwikiIdleCallbacks.push({ callback: callback, options: options || {} });
      return window.__macwikiIdleCallbacks.length;
    };
    window.cancelIdleCallback = function () {};
    """
}
