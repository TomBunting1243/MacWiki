import CoreGraphics
import Foundation
import Testing

@testable import MacWiki

struct DiscoverResponsiveLayoutProfileTests {
    @Test func widthBandsPreserveEveryExistingBreakpointBoundary() throws {
        let cases: [(width: CGFloat, band: DiscoverResponsiveLayoutProfile.WidthBand)] = [
            (1, .under720),
            (719.999, .under720),
            (720, .from720),
            (759.999, .from720),
            (760, .from760),
            (819.999, .from760),
            (820, .from820),
            (879.999, .from820),
            (880, .from880),
            (939.999, .from880),
            (940, .from940),
            (1119.999, .from940),
            (1120, .from1120),
            (1199.999, .from1120),
            (1200, .from1200),
            (1239.999, .from1200),
            (1240, .from1240),
            (1319.999, .from1240),
            (1320, .from1320),
            (1539.999, .from1320),
            (1540, .from1540),
            (2200, .from1540)
        ]

        for testCase in cases {
            let profile = try #require(DiscoverResponsiveLayoutProfile(width: testCase.width))
            #expect(profile.widthBand == testCase.band)
        }

        #expect(DiscoverResponsiveLayoutProfile(width: 0) == nil)
        #expect(DiscoverResponsiveLayoutProfile(width: -1) == nil)
    }

    @Test func equalityChangesOnlyWhenARelevantBreakpointIsCrossed() throws {
        let lower720 = try #require(DiscoverResponsiveLayoutProfile(width: 720))
        let upper720 = try #require(DiscoverResponsiveLayoutProfile(width: 759.999))
        let at760 = try #require(DiscoverResponsiveLayoutProfile(width: 760))
        let lower1200 = try #require(DiscoverResponsiveLayoutProfile(width: 1200))
        let upper1200 = try #require(DiscoverResponsiveLayoutProfile(width: 1239.999))

        #expect(lower720 == upper720)
        #expect(lower720 != at760)
        #expect(lower1200 == upper1200)
    }

    @Test func wideLayoutsActivateTheNativeEditorialSpread() throws {
        let compact = try #require(DiscoverResponsiveLayoutProfile(width: 1_239.999))
        let wide = try #require(DiscoverResponsiveLayoutProfile(width: 1_240))
        let expanded = try #require(DiscoverResponsiveLayoutProfile(width: 1_540))

        #expect(!compact.prefersEditorialSpread)
        #expect(compact.todayMostReadColumnCount(hasNewsBriefing: false, itemCount: 14) == 1)
        #expect(wide.prefersEditorialSpread)
        #expect(wide.editorialColumnSpacing == 16)
        #expect(wide.todayMostReadColumnCount(hasNewsBriefing: true, itemCount: 14) == 1)
        #expect(wide.todayMostReadColumnCount(hasNewsBriefing: false, itemCount: 7) == 1)
        #expect(wide.todayMostReadColumnCount(hasNewsBriefing: false, itemCount: 8) == 2)
        #expect(expanded.prefersEditorialSpread)
        #expect(expanded.editorialColumnSpacing == 20)
    }

    @Test func discoveryUsesWideGridRailAndHorizontalMediaVariants() throws {
        let stages = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverFeedCollectionStages.swift"
        )

        #expect(stages.contains("Grid(horizontalSpacing: responsiveLayout.editorialColumnSpacing"))
        #expect(stages.contains("let columnCount = responsiveLayout.todayMostReadColumnCount"))
        #expect(stages.contains("hasNewsBriefing: !feed.newsStories.isEmpty"))
        #expect(stages.contains("todayMostReadRows(columnCount: columnCount)"))
        #expect(stages.contains("let splitIndex = (todayMostReadItems.count + 1) / 2"))
        #expect(stages.contains("style: responsiveLayout.prefersEditorialSpread ? .rail : .standard"))
        #expect(stages.contains("prefersHorizontalLayout: responsiveLayout.prefersEditorialSpread"))
    }

    @Test func derivedLayoutValuesMatchThePreviousWidthFormulasAtEveryBoundary() throws {
        let boundaries: [CGFloat] = [720, 760, 820, 880, 940, 1120, 1200, 1240, 1320, 1540]
        var widths: [CGFloat] = [1, 1040, 2200]
        for boundary in boundaries {
            widths.append(contentsOf: [boundary - 0.001, boundary, boundary + 0.001])
        }

        for width in widths {
            let profile = try #require(DiscoverResponsiveLayoutProfile(width: width))
            #expect(LayoutSnapshot(profile) == LayoutSnapshot.legacy(width: width))
        }
    }

    @Test func discoveryPublishesOnlyTheEquatableProfileDuringResize() throws {
        let root = try repositorySource("Sources/MacWiki/Views/Home/DiscoverNewTabPageView.swift")
        let profile = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverResponsiveLayoutProfile.swift"
        )
        let profileConsumers = [
            "Sources/MacWiki/Views/Home/Discover/DiscoverFeedSections.swift",
            "Sources/MacWiki/Views/Home/Discover/DiscoverFeedSurface.swift",
            "Sources/MacWiki/Views/Home/Discover/DiscoverTimeMachineStageView.swift",
            "Sources/MacWiki/Views/Home/Discover/DiscoverTimeMachineControlsView.swift"
        ]

        #expect(root.contains("@State private var responsiveLayout = DiscoverResponsiveLayoutProfile.initial"))
        #expect(root.contains(".onGeometryChange(for: DiscoverResponsiveLayoutProfile?.self)"))
        #expect(root.contains("guard let newLayout, newLayout != responsiveLayout else { return }"))
        #expect(!root.contains("GeometryReader"))
        #expect(!root.contains("discoverContentWidth"))
        #expect(profile.contains("struct DiscoverResponsiveLayoutProfile: Equatable, Sendable"))

        for path in profileConsumers {
            let source = try repositorySource(path)
            #expect(source.contains("responsiveLayout: DiscoverResponsiveLayoutProfile"))
            #expect(!source.contains("discoverContentWidth"))
            #expect(!source.contains("availableWidth: CGFloat"))
        }
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}

private struct LayoutSnapshot: Equatable {
    let pageMaxWidth: CGFloat
    let horizontalPadding: CGFloat
    let pageSectionSpacing: CGFloat
    let timeMachineStageSpacing: CGFloat
    let prefersWideTimeMachineControls: Bool
    let showsInlineTimeMachineQuickJumps: Bool
    let isUltraCompact: Bool
    let isVeryCompact: Bool
    let isCompact: Bool
    let feedSectionSpacing: CGFloat
    let heroImageHeight: CGFloat
    let leadStoryTitleLineLimit: Int
    let leadStoryDescriptionLineLimit: Int
    let inTheNewsRailLimit: Int
    let newsBriefingLimit: Int
    let allTimeMostReadLimit: Int
    let playlistRowLimit: Int
    let todayMostReadLimit: Int

    init(_ profile: DiscoverResponsiveLayoutProfile) {
        pageMaxWidth = profile.pageMaxWidth
        horizontalPadding = profile.horizontalPadding
        pageSectionSpacing = profile.pageSectionSpacing
        timeMachineStageSpacing = profile.timeMachineStageSpacing
        prefersWideTimeMachineControls = profile.prefersWideTimeMachineControls
        showsInlineTimeMachineQuickJumps = profile.showsInlineTimeMachineQuickJumps
        isUltraCompact = profile.isUltraCompact
        isVeryCompact = profile.isVeryCompact
        isCompact = profile.isCompact
        feedSectionSpacing = profile.feedSectionSpacing
        heroImageHeight = profile.heroImageHeight
        leadStoryTitleLineLimit = profile.leadStoryTitleLineLimit
        leadStoryDescriptionLineLimit = profile.leadStoryDescriptionLineLimit
        inTheNewsRailLimit = profile.inTheNewsRailLimit
        newsBriefingLimit = profile.newsBriefingLimit
        allTimeMostReadLimit = profile.allTimeMostReadLimit
        playlistRowLimit = profile.playlistRowLimit
        todayMostReadLimit = profile.todayMostReadLimit
    }

    private init(
        pageMaxWidth: CGFloat,
        horizontalPadding: CGFloat,
        pageSectionSpacing: CGFloat,
        timeMachineStageSpacing: CGFloat,
        prefersWideTimeMachineControls: Bool,
        showsInlineTimeMachineQuickJumps: Bool,
        isUltraCompact: Bool,
        isVeryCompact: Bool,
        isCompact: Bool,
        feedSectionSpacing: CGFloat,
        heroImageHeight: CGFloat,
        leadStoryTitleLineLimit: Int,
        leadStoryDescriptionLineLimit: Int,
        inTheNewsRailLimit: Int,
        newsBriefingLimit: Int,
        allTimeMostReadLimit: Int,
        playlistRowLimit: Int,
        todayMostReadLimit: Int
    ) {
        self.pageMaxWidth = pageMaxWidth
        self.horizontalPadding = horizontalPadding
        self.pageSectionSpacing = pageSectionSpacing
        self.timeMachineStageSpacing = timeMachineStageSpacing
        self.prefersWideTimeMachineControls = prefersWideTimeMachineControls
        self.showsInlineTimeMachineQuickJumps = showsInlineTimeMachineQuickJumps
        self.isUltraCompact = isUltraCompact
        self.isVeryCompact = isVeryCompact
        self.isCompact = isCompact
        self.feedSectionSpacing = feedSectionSpacing
        self.heroImageHeight = heroImageHeight
        self.leadStoryTitleLineLimit = leadStoryTitleLineLimit
        self.leadStoryDescriptionLineLimit = leadStoryDescriptionLineLimit
        self.inTheNewsRailLimit = inTheNewsRailLimit
        self.newsBriefingLimit = newsBriefingLimit
        self.allTimeMostReadLimit = allTimeMostReadLimit
        self.playlistRowLimit = playlistRowLimit
        self.todayMostReadLimit = todayMostReadLimit
    }

    static func legacy(width: CGFloat) -> Self {
        let isUltraCompact = width < 720
        let isVeryCompact = width < 820
        let isCompact = width < 940

        let pageMaxWidth: CGFloat = if width >= 1540 {
            1320
        } else if width >= 1240 {
            1160
        } else {
            980
        }
        let horizontalPadding: CGFloat = if width < 720 {
            18
        } else if width >= 1540 {
            42
        } else {
            28
        }
        let feedSectionSpacing: CGFloat = if isUltraCompact {
            16
        } else if isVeryCompact {
            20
        } else if isCompact {
            22
        } else {
            26
        }
        let heroImageHeight: CGFloat = if isUltraCompact {
            172
        } else if isVeryCompact {
            190
        } else if isCompact {
            214
        } else if width >= 1320 {
            320
        } else if width >= 1120 {
            286
        } else {
            252
        }
        let newsBriefingLimit: Int = if isUltraCompact {
            2
        } else if isVeryCompact {
            3
        } else if isCompact {
            4
        } else {
            6
        }
        let allTimeMostReadLimit: Int = if isUltraCompact {
            10
        } else if width >= 1200 {
            22
        } else if isVeryCompact {
            14
        } else {
            18
        }
        let playlistRowLimit: Int = if isUltraCompact {
            6
        } else if width >= 1200 {
            12
        } else if isVeryCompact {
            8
        } else {
            10
        }
        let todayMostReadLimit: Int = if isUltraCompact {
            8
        } else if isVeryCompact {
            10
        } else if width >= 1200 {
            14
        } else {
            12
        }

        return Self(
            pageMaxWidth: pageMaxWidth,
            horizontalPadding: horizontalPadding,
            pageSectionSpacing: width < 820 ? 16 : 20,
            timeMachineStageSpacing: width < 820 ? 18 : 22,
            prefersWideTimeMachineControls: width >= 760,
            showsInlineTimeMachineQuickJumps: width >= 880,
            isUltraCompact: isUltraCompact,
            isVeryCompact: isVeryCompact,
            isCompact: isCompact,
            feedSectionSpacing: feedSectionSpacing,
            heroImageHeight: heroImageHeight,
            leadStoryTitleLineLimit: isUltraCompact ? 3 : (isVeryCompact ? 4 : 5),
            leadStoryDescriptionLineLimit: isUltraCompact ? 2 : (isVeryCompact ? 3 : 4),
            inTheNewsRailLimit: isCompact ? 8 : 12,
            newsBriefingLimit: newsBriefingLimit,
            allTimeMostReadLimit: allTimeMostReadLimit,
            playlistRowLimit: playlistRowLimit,
            todayMostReadLimit: todayMostReadLimit
        )
    }
}
