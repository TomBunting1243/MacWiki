import CoreGraphics
import Testing

@testable import MacWiki

struct InspectorInfoSectionSplitSizerTests {
    private let metadataRange: ClosedRange<CGFloat> = 56...520
    private let tocRange: ClosedRange<CGFloat> = 72...560
    private let budgetRange: ClosedRange<CGFloat> = 280...620

    @Test func shortMetadataLongTOCFavorsShowingAllMetadata() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: 92,
            tocContentHeight: 900,
            viewportHeight: 720,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: 0.58,
            fallbackBudget: 420
        )

        #expect(abs(result.metadataHeight - 92) < 0.5)
        #expect(result.tocHeight > 300)
    }

    @Test func shortTOCLongMetadataFavorsShowingMostMetadata() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: 900,
            tocContentHeight: 88,
            viewportHeight: 720,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: 0.58,
            fallbackBudget: 420
        )

        #expect(abs(result.tocHeight - 88) < 0.5)
        #expect(result.metadataHeight > 300)
    }

    @Test func longMetadataAndLongTOCUseContentWeightedBalancedSplit() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: 700,
            tocContentHeight: 760,
            viewportHeight: 700,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: 0.58,
            fallbackBudget: 420
        )

        #expect(result.tocHeight > result.metadataHeight)
        #expect(result.tocHeight - result.metadataHeight > 48)
    }

    @Test func highlyAsymmetricLongSectionsAreStillGuardrailed() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: 1600,
            tocContentHeight: 640,
            viewportHeight: 700,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: 0.58,
            fallbackBudget: 420
        )

        #expect(result.tocHeight > result.metadataHeight)
        #expect(result.tocHeight >= 220)
        #expect(result.metadataHeight >= 160)
        #expect(result.metadataHeight <= 190)
    }

    @Test func shortMetadataAndShortTOCRemainCompact() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: 120,
            tocContentHeight: 132,
            viewportHeight: 700,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: 0.58,
            fallbackBudget: 420
        )

        #expect(abs(result.metadataHeight - 120) < 0.5)
        #expect(abs(result.tocHeight - 132) < 0.5)
    }

    @Test func nilViewportUsesFallbackBudget() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: 900,
            tocContentHeight: 900,
            viewportHeight: nil,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: 0.58,
            fallbackBudget: 420
        )

        #expect(abs(result.metadataHeight - 178.64) < 0.5)
        #expect(abs(result.tocHeight - 241.36) < 0.5)
    }

    @Test func tocIsShownFullyWhenItFitsBudgetAfterMetadataMinimum() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: 1200,
            tocContentHeight: 240,
            viewportHeight: 700,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: 0.58,
            fallbackBudget: 420
        )

        #expect(abs(result.tocHeight - 240) < 0.5)
        #expect(result.metadataHeight >= metadataRange.lowerBound)
    }

    @Test func nonFiniteInputsResolveToFiniteHeightsWithinConfiguredRanges() {
        let result = InspectorInfoSectionSplitSizer.calculate(
            metadataContentHeight: .nan,
            tocContentHeight: .infinity,
            viewportHeight: .nan,
            metadataRange: metadataRange,
            tocRange: tocRange,
            budgetRange: budgetRange,
            budgetRatio: .nan,
            fallbackBudget: .infinity
        )

        #expect(result.metadataHeight.isFinite)
        #expect(result.tocHeight.isFinite)
        #expect(result.metadataHeight >= metadataRange.lowerBound)
        #expect(result.metadataHeight <= metadataRange.upperBound)
        #expect(result.tocHeight >= tocRange.lowerBound)
        #expect(result.tocHeight <= tocRange.upperBound)
    }
}
