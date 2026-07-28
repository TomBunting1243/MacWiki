import Foundation
import SwiftUI
import Testing

@testable import MacWiki

struct ReaderInspectorSurfacePolicyTests {
    @Test func reduceTransparencyUsesOpaqueSurfacesAndRemovesShadows() {
        let personalization = MacWikiAccessibilityPersonalization(
            reduceMotion: false,
            reduceTransparency: true,
            differentiateWithoutColor: false,
            colorSchemeContrast: .standard
        )

        let policy = ReaderInspectorSurfacePolicy(
            personalization: personalization,
            baseBorderOpacity: 0.04,
            baseBorderWidth: 0.5
        )

        #expect(policy.usesOpaqueBackground)
        #expect(policy.borderOpacity == 0.16)
        #expect(policy.borderWidth == 0.8)
        #expect(policy.shadowMultiplier == 0)
    }

    @Test func increasedContrastStrengthensSurfaceBoundaries() {
        let personalization = MacWikiAccessibilityPersonalization(
            reduceMotion: false,
            reduceTransparency: false,
            differentiateWithoutColor: false,
            colorSchemeContrast: .increased
        )

        let policy = ReaderInspectorSurfacePolicy(
            personalization: personalization,
            baseBorderOpacity: 0.08,
            baseBorderWidth: 0.7
        )

        #expect(policy.usesOpaqueBackground)
        #expect(policy.borderOpacity == 0.28)
        #expect(policy.borderWidth == 1)
        #expect(policy.shadowMultiplier == 0)
    }

    @Test func standardProfilePreservesRequestedMaterialTreatment() {
        let policy = ReaderInspectorSurfacePolicy(
            personalization: .standard,
            baseBorderOpacity: 0.12,
            baseBorderWidth: 0.8
        )

        #expect(!policy.usesOpaqueBackground)
        #expect(policy.borderOpacity == 0.12)
        #expect(policy.borderWidth == 0.8)
        #expect(policy.shadowMultiplier == 1)
    }

    @Test func targetedReaderAndInspectorMaterialsUseSharedPolicy() throws {
        let targetPaths = [
            "Sources/MacWiki/Views/Inspector/ReferenceListView.swift",
            "Sources/MacWiki/Views/Inspector/ReferenceExportBarView.swift",
            "Sources/MacWiki/Views/Inspector/ReferenceRowView.swift",
            "Sources/MacWiki/Views/Inspector/InspectorTagStatusBox.swift",
            "Sources/MacWiki/Views/Components/HighlightListView.swift",
            "Sources/MacWiki/Views/Components/HighlightRowView.swift"
        ]

        for path in targetPaths {
            let source = try source(path)
            #expect(source.contains("readerInspector"), "Missing shared surface policy in \(path)")
            #expect(!source.contains(".fill(.ultraThinMaterial)"), "Unmanaged material in \(path)")
            #expect(!source.contains(".background(.thinMaterial"), "Unmanaged material in \(path)")
        }
    }

    @Test func targetedMicroInteractionsHonorReduceMotion() throws {
        let toolbar = try source("Sources/MacWiki/Views/Components/HighlightToolbar.swift")
        let tagEditor = try source("Sources/MacWiki/Views/Inspector/InspectorTagEditor.swift")
        let hoverPreview = try source(
            "Sources/MacWiki/Views/Components/WebView/WebViewLinkHoverPreviewPane.swift"
        )

        #expect(toolbar.contains("accessibilityPersonalization.reduceMotion"))
        #expect(toolbar.contains("@Environment(\\.macWikiAccessibilityPersonalization.reduceMotion)"))
        #expect(tagEditor.contains("@Environment(\\.macWikiAccessibilityPersonalization.reduceMotion)"))
        #expect(tagEditor.contains("withAnimation(reduceMotion ? nil"))
        #expect(hoverPreview.contains("@Environment(\\.macWikiAccessibilityPersonalization.reduceMotion)"))
        #expect(hoverPreview.contains("withAnimation(reduceMotion ? nil"))
    }

    private func source(_ path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: path),
            encoding: .utf8
        )
    }
}
