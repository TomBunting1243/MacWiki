import Foundation
import Testing

@testable import MacWiki

/// Direct behavioral coverage retained from the former source-shape beta suite.
@MainActor
struct ShellBehaviorRegressionTests {
    @Test func webViewPoolRetentionIsUnionedByWindowOwner() {
        let pool = WebViewPool.makeForTesting()
        pool.resetForTesting()

        let mainOwner = UUID()
        let articleOwner = UUID()
        let mainTab = UUID()
        let articleTab = UUID()

        pool.retain(only: [mainTab], for: mainOwner)
        pool.retain(only: [articleTab], for: articleOwner)
        #expect(pool.retainedTabIDsForTesting() == [mainTab, articleTab])
        #expect(pool.canStoreWebViewForTesting(for: mainTab))

        pool.retain(only: [], for: articleOwner)
        #expect(pool.retainedTabIDsForTesting() == [mainTab])
        #expect(!pool.canStoreWebViewForTesting(for: articleTab))

        pool.releaseOwner(mainOwner)
        #expect(pool.retainedTabIDsForTesting().isEmpty)
        #expect(!pool.canStoreWebViewForTesting(for: UUID()))

        pool.releaseOwner(articleOwner)
        #expect(pool.canStoreWebViewForTesting(for: UUID()))
    }

    /// The preference was renamed, but changing its defaults key would silently reset it for
    /// existing users.
    @Test func liquidGlassChromeKeepsLegacyStorageKey() {
        #expect(AppStorageKey.Chrome.liquidGlassChrome == "tabBarLiquidGlass")
        #expect(AppStorageKey.Chrome.tabBarLiquidGlass == AppStorageKey.Chrome.liquidGlassChrome)
    }

    @Test func tabAccessibilityValueIncludesSemanticMarkers() {
        let value = TabAccessibilityStatus.value(
            isActive: true,
            isSaved: true,
            hasHighlights: true,
            isRead: false,
            showsProgress: true,
            progress: 0.62
        )

        #expect(value == "Active tab, saved, has highlights, 62% read")
    }

    @Test func inactiveTabChromeKeepsVisibleBoundariesAndReadingProgress() {
        #expect(
            TabChromeHierarchy.borderOpacity(
                isActive: false,
                isHovered: false,
                isKeyWindow: true,
                darkMode: false,
                increasedContrast: false
            ) > 0
        )
        #expect(
            TabChromeHierarchy.progressFillOpacity(
                darkMode: false,
                isActive: false
            ) > 0
        )
    }

    @Test func nativeArticleSelectionDefersModifiedClicksToTheNativeList() {
        #expect(ArticleListSelectionPresentation.custom.handlesPrimaryTap(
            isCommandPressed: false,
            isShiftPressed: false
        ))
        #expect(ArticleListSelectionPresentation.custom.handlesPrimaryTap(
            isCommandPressed: true,
            isShiftPressed: true
        ))
        #expect(ArticleListSelectionPresentation.native.handlesPrimaryTap(
            isCommandPressed: false,
            isShiftPressed: false
        ))
        #expect(!ArticleListSelectionPresentation.native.handlesPrimaryTap(
            isCommandPressed: true,
            isShiftPressed: false
        ))
        #expect(!ArticleListSelectionPresentation.native.handlesPrimaryTap(
            isCommandPressed: false,
            isShiftPressed: true
        ))
    }

    @Test func persistedColumnWidthsRejectInvalidValuesAndClampToSupportedRanges() {
        #expect(MainWindowColumnWidth.clampedStorageValue(.nan, range: MainWindowColumnWidth.sidebarRange) == nil)
        #expect(MainWindowColumnWidth.clampedStorageValue(120, range: MainWindowColumnWidth.sidebarRange) == 176)
        #expect(MainWindowColumnWidth.clampedStorageValue(480, range: MainWindowColumnWidth.directoryRange) == 420)
        #expect(MainWindowColumnWidth.clampedStorageValue(260, range: MainWindowColumnWidth.inspectorRange) == 320)
        #expect(MainWindowColumnWidth.clampedStorageValue(320, range: MainWindowColumnWidth.inspectorRange) == 320)
        #expect(MainWindowLayout.minimumContentWidth(
            listsSidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true
        ) == 1_279)
        #expect(MainWindowLayout.minimumContentWidth(
            listsSidebarVisible: false,
            directoryVisible: false,
            inspectorVisible: false
        ) == MainWindowLayout.minimumReaderWidth)
    }

    @Test func revisionMetadataUnknownCacheDoesNotBlockHydrationRetry() async {
        let service = WikipediaService()
        let staleMetadata = [
            WikipediaService.MetadataItem(label: "Word count", value: "2,009 words"),
            WikipediaService.MetadataItem(label: "Last edited", value: "Unknown"),
            WikipediaService.MetadataItem(label: "First created", value: "Unknown")
        ]
        let completeMetadata = [
            WikipediaService.MetadataItem(label: "Word count", value: "2,009 words"),
            WikipediaService.MetadataItem(label: "Last edited", value: "Apr 26, 2026"),
            WikipediaService.MetadataItem(label: "First created", value: "Mar 10, 2010")
        ]

        #expect(await service.hasUnknownRevisionMetadata(staleMetadata))
        #expect(!(await service.hasUnknownRevisionMetadata(completeMetadata)))
    }
}
