import CoreGraphics
import Testing

@testable import MacWiki

struct InspectorSplitStateTests {
    private let metadataRange: ClosedRange<CGFloat> = 56...520
    private let tocRange: ClosedRange<CGFloat> = 72...560
    private let budgetRange: ClosedRange<CGFloat> = 280...620

    @Test func persistedRatioFallsBackToStoredSectionHeights() {
        let ratio = InspectorSplitState.persistedMetadataSplitRatio(
            infoSplitRatioSetting: 0,
            metadataSectionHeightSetting: 180,
            tocSectionHeightSetting: 240,
            metadataRange: metadataRange,
            tocRange: tocRange
        )

        #expect(abs((ratio ?? 0) - (180 / 420)) < 0.0001)
    }

    @Test func sanitizePersistedSettingsZeroesInvalidValues() {
        let sanitized = InspectorSplitState.sanitizePersistedSettings(
            infoSplitRatioSetting: 1.5,
            metadataSectionHeightSetting: -.infinity,
            tocSectionHeightSetting: .nan
        )

        #expect(sanitized.ratio == 0)
        #expect(sanitized.metadataHeight == 0)
        #expect(sanitized.tocHeight == 0)
    }

    @Test func clampedMetadataSplitHeightPreservesTOCMinimum() {
        let clamped = InspectorSplitState.clampedMetadataSplitHeight(
            candidate: 400,
            budget: 420,
            metadataRange: metadataRange,
            tocRange: tocRange
        )

        #expect(clamped == 348)
    }

    @Test func longTOCExpandsIntoUnusedBudgetAfterMetadataFits() {
        let expanded = InspectorSplitState.expandTOCIntoAvailableSpace(
            InspectorInfoSectionSplitSizer.Result(metadataHeight: 120, tocHeight: 360),
            budget: 620,
            metadataContentHeight: 120,
            tocContentHeight: 360,
            metadataRange: metadataRange,
            tocRange: tocRange
        )

        #expect(abs(expanded.metadataHeight - 120) < 0.5)
        #expect(abs(expanded.tocHeight - 500) < 0.5)
    }

    @Test func longTOCReclaimsUnusedPersistedMetadataSpace() {
        let persisted = InspectorSplitState.resolveSplitHeights(
            budget: 620,
            effectiveRatio: 0.5,
            metadataRange: metadataRange,
            tocRange: tocRange
        )
        let expanded = InspectorSplitState.expandTOCIntoAvailableSpace(
            persisted,
            budget: 620,
            metadataContentHeight: 156,
            tocContentHeight: 900,
            metadataRange: metadataRange,
            tocRange: tocRange
        )

        #expect(abs(expanded.metadataHeight - 156) < 0.5)
        #expect(abs(expanded.tocHeight - 464) < 0.5)
    }

    @Test func shortTOCDoesNotClaimUnusedBudget() {
        let expanded = InspectorSplitState.expandTOCIntoAvailableSpace(
            InspectorInfoSectionSplitSizer.Result(metadataHeight: 120, tocHeight: 132),
            budget: 620,
            metadataContentHeight: 120,
            tocContentHeight: 132,
            metadataRange: metadataRange,
            tocRange: tocRange
        )

        #expect(abs(expanded.metadataHeight - 120) < 0.5)
        #expect(abs(expanded.tocHeight - 132) < 0.5)
    }

    @Test func budgetUsesFallbackWhenViewportIsInvalid() {
        let budget = InspectorSplitState.budget(
            viewportHeight: .nan,
            budgetRatio: 0.58,
            budgetRange: budgetRange,
            fallbackBudget: 420
        )

        #expect(budget == 420)
    }
}
