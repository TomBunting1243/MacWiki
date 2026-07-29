import SwiftUI
import Testing
import WebKit

@testable import MacWiki

struct WebViewInspectorProjectionSchedulePolicyTests {
    typealias Policy = WebViewInspectorProjectionSchedulePolicy

    @Test func schedulePreservesNormalizationAndRetryOrder() {
        #expect(Policy.steps.map(\.delay) == [0.06, 0.24, 0.36, 0.55, 0.90])
        #expect(
            Policy.steps.map(\.requests) == [
                [.init(target: .tableOfContents, requirement: .always)],
                [.init(target: .references, requirement: .always)],
                [.init(target: .tableOfContents, requirement: .missingResult)],
                [.init(target: .references, requirement: .missingResult)],
                [
                    .init(target: .tableOfContents, requirement: .missingResult),
                    .init(target: .references, requirement: .missingResult)
                ]
            ]
        )
    }

    @Test func everyStepRequiresTheCapturedProjectionToRemainCurrent() {
        let missing = Policy.ProjectionState(
            hasTableOfContentsResult: false,
            hasReferencesResult: false
        )

        for step in Policy.steps {
            #expect(
                Policy.requests(
                    for: step,
                    projection: missing,
                    isCurrentProjection: false
                ).isEmpty
            )
        }
    }

    @Test func retriesOnlyProjectionResultsThatRemainMissing() throws {
        let tocRetry = try #require(Policy.steps.first { $0.delay == 0.36 })
        let referencesRetry = try #require(Policy.steps.first { $0.delay == 0.55 })
        let finalRetry = try #require(Policy.steps.first { $0.delay == 0.90 })
        let tableOfContentsReady = Policy.ProjectionState(
            hasTableOfContentsResult: true,
            hasReferencesResult: false
        )

        #expect(
            Policy.requests(
                for: tocRetry,
                projection: tableOfContentsReady,
                isCurrentProjection: true
            ).isEmpty
        )
        #expect(
            Policy.requests(
                for: referencesRetry,
                projection: tableOfContentsReady,
                isCurrentProjection: true
            ) == [.references]
        )
        #expect(
            Policy.requests(
                for: finalRetry,
                projection: tableOfContentsReady,
                isCurrentProjection: true
            ) == [.references]
        )
    }

    @Test func invalidResultsRetryAndValidResultsPublishTheirTypedProjection() {
        #expect(
            Policy.resultDecision(for: .tableOfContents, hasValidRows: false) == .retry
        )
        #expect(
            Policy.resultDecision(for: .references, hasValidRows: false) == .retry
        )
        #expect(
            Policy.resultDecision(for: .tableOfContents, hasValidRows: true) ==
                .publishTableOfContentsAndVisibleSection
        )
        #expect(
            Policy.resultDecision(for: .references, hasValidRows: true) == .publishReferences
        )
    }

    @MainActor
    @Test func emptyWebKitResultsCompleteTheProjectionAndSuppressLaterRetries() async throws {
        var tableOfContentsUpdates: [[ArticleTableOfContentsItem]] = []
        var referenceUpdates: [[ArticleReferenceSection]] = []
        let coordinator = makeCoordinator(
            onTableOfContentsUpdate: { tableOfContentsUpdates.append($0) },
            onReferencesUpdate: { referenceUpdates.append($0) }
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
        webView.loadHTMLString(
            """
            <!doctype html><html><body>
            <script>
              window.extractTableOfContents = function () { return []; };
              window.extractReferences = function () { return []; };
              window.currentVisibleSectionId = function () { return null; };
            </script>
            </body></html>
            """,
            baseURL: nil
        )

        for _ in 0..<200 {
            let isReady = (try? await webView.evaluateJavaScript(
                "document.readyState === 'complete'"
            )) as? Bool == true
            if isReady, !webView.isLoading {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!webView.isLoading)

        coordinator.lastLoadedArticleTitle = "Empty Projection"
        coordinator.lastLoadedHTMLSignature = 1
        coordinator.attachNewWebView(webView)
        coordinator.publishTableOfContents(from: webView)
        coordinator.publishReferences(from: webView)

        for _ in 0..<200 {
            if coordinator.inspectorProjection.hasTableOfContentsResult,
               coordinator.inspectorProjection.hasReferencesResult,
               !tableOfContentsUpdates.isEmpty,
               !referenceUpdates.isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.inspectorProjection.hasTableOfContentsResult)
        #expect(coordinator.inspectorProjection.hasReferencesResult)
        #expect(coordinator.inspectorProjection.tableOfContents.isEmpty)
        #expect(coordinator.inspectorProjection.references.isEmpty)
        #expect(tableOfContentsUpdates.count == 1)
        #expect(tableOfContentsUpdates.first?.isEmpty == true)
        #expect(referenceUpdates.count == 1)
        #expect(referenceUpdates.first?.isEmpty == true)

        let finalRetry = try #require(Policy.steps.first { $0.delay == 0.90 })
        let completedProjection = Policy.ProjectionState(
            hasTableOfContentsResult: coordinator.inspectorProjection.hasTableOfContentsResult,
            hasReferencesResult: coordinator.inspectorProjection.hasReferencesResult
        )
        #expect(Policy.requests(
            for: finalRetry,
            projection: completedProjection,
            isCurrentProjection: true
        ).isEmpty)
    }

    @MainActor
    private func makeCoordinator(
        onTableOfContentsUpdate: @escaping ([ArticleTableOfContentsItem]) -> Void,
        onReferencesUpdate: @escaping ([ArticleReferenceSection]) -> Void
    ) -> MacWiki.WebView.Coordinator {
        MacWiki.WebView.Coordinator(
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
            articleTitle: "Empty Projection",
            contentRevision: 1,
            readerAppearance: .default,
            readerTopInset: 56,
            preferImmediateReveal: false,
            onTableOfContentsUpdate: onTableOfContentsUpdate,
            onReferencesUpdate: onReferencesUpdate,
            onVisibleSectionChange: nil,
            onContentReveal: nil,
            onLinkHoverPreviewChange: nil,
            linkPreviewImmediateModifier: .default,
            nativeHighlightingMenuEnabled: true
        )
    }
}
