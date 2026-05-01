import CoreGraphics
import Foundation

struct InspectorPersistedSplitSettings {
    let ratio: Double
    let metadataHeight: Double
    let tocHeight: Double
}

enum InspectorSplitState {
    static func budget(
        viewportHeight: CGFloat,
        budgetRatio: CGFloat,
        budgetRange: ClosedRange<CGFloat>,
        fallbackBudget: CGFloat
    ) -> CGFloat {
        let proposedBudget: CGFloat
        if viewportHeight.isFinite, viewportHeight > 0 {
            proposedBudget = viewportHeight * max(budgetRatio, 0)
        } else {
            proposedBudget = fallbackBudget
        }

        return min(max(proposedBudget, budgetRange.lowerBound), budgetRange.upperBound)
    }

    static func clampedHeight(
        _ value: CGFloat,
        range: ClosedRange<CGFloat>
    ) -> CGFloat {
        guard value.isFinite else {
            return range.lowerBound
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func sanitizedPersistedHeight(
        _ storedValue: Double,
        range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        guard storedValue.isFinite, storedValue > 0 else {
            return nil
        }
        let value = CGFloat(storedValue)
        guard value.isFinite else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func persistedMetadataSplitRatio(
        infoSplitRatioSetting: Double,
        metadataSectionHeightSetting: Double,
        tocSectionHeightSetting: Double,
        metadataRange: ClosedRange<CGFloat>,
        tocRange: ClosedRange<CGFloat>
    ) -> CGFloat? {
        if infoSplitRatioSetting.isFinite,
           infoSplitRatioSetting > 0,
           infoSplitRatioSetting < 1 {
            return CGFloat(infoSplitRatioSetting)
        }

        if let storedMetadata = sanitizedPersistedHeight(
            metadataSectionHeightSetting,
            range: metadataRange
        ),
           let storedTOC = sanitizedPersistedHeight(
            tocSectionHeightSetting,
            range: tocRange
           ) {
            let combined = storedMetadata + storedTOC
            guard combined > 0 else { return nil }
            return storedMetadata / combined
        }

        return nil
    }

    static func resolveSplitHeights(
        budget: CGFloat,
        effectiveRatio: CGFloat,
        metadataRange: ClosedRange<CGFloat>,
        tocRange: ClosedRange<CGFloat>
    ) -> InspectorInfoSectionSplitSizer.Result {
        guard budget.isFinite, budget > 0 else {
            return InspectorInfoSectionSplitSizer.Result(
                metadataHeight: metadataRange.lowerBound,
                tocHeight: tocRange.lowerBound
            )
        }

        let metadataMinRatio = metadataRange.lowerBound / budget
        let metadataMaxRatio = 1 - (tocRange.lowerBound / budget)
        let ratio = min(max(effectiveRatio, metadataMinRatio), metadataMaxRatio)

        var metadataHeight = clampedHeight(budget * ratio, range: metadataRange)
        var tocHeight = clampedHeight(budget - metadataHeight, range: tocRange)

        var overflow = (metadataHeight + tocHeight) - budget
        if overflow > 0.001 {
            let metadataSlack = metadataHeight - metadataRange.lowerBound
            let tocSlack = tocHeight - tocRange.lowerBound
            if metadataSlack >= tocSlack, metadataSlack > 0 {
                let reduction = min(overflow, metadataSlack)
                metadataHeight -= reduction
                overflow -= reduction
            }
            if overflow > 0.001, tocSlack > 0 {
                let reduction = min(overflow, tocSlack)
                tocHeight -= reduction
                overflow -= reduction
            }
        }

        let remaining = budget - (metadataHeight + tocHeight)
        if remaining > 0.001 {
            let tocHeadroom = max(0, tocRange.upperBound - tocHeight)
            let tocIncrease = min(remaining, tocHeadroom)
            tocHeight += tocIncrease

            let metadataHeadroom = max(0, metadataRange.upperBound - metadataHeight)
            let metadataIncrease = min(remaining - tocIncrease, metadataHeadroom)
            metadataHeight += metadataIncrease
        }

        return InspectorInfoSectionSplitSizer.Result(
            metadataHeight: clampedHeight(metadataHeight, range: metadataRange),
            tocHeight: clampedHeight(tocHeight, range: tocRange)
        )
    }

    static func expandTOCIntoAvailableSpace(
        _ splitHeights: InspectorInfoSectionSplitSizer.Result,
        budget: CGFloat,
        metadataContentHeight: CGFloat,
        tocContentHeight: CGFloat,
        metadataRange: ClosedRange<CGFloat>,
        tocRange: ClosedRange<CGFloat>
    ) -> InspectorInfoSectionSplitSizer.Result {
        var metadataHeight = clampedHeight(splitHeights.metadataHeight, range: metadataRange)
        var tocHeight = clampedHeight(splitHeights.tocHeight, range: tocRange)
        guard budget.isFinite, budget > 0 else {
            return InspectorInfoSectionSplitSizer.Result(metadataHeight: metadataHeight, tocHeight: tocHeight)
        }

        let metadataNeededHeight = clampedHeight(
            sanitizeNonNegative(metadataContentHeight),
            range: metadataRange
        )
        let tocContentHeight = sanitizeNonNegative(tocContentHeight)
        let longTOCThreshold = max(tocRange.lowerBound * 3, metadataNeededHeight * 1.5)
        let tocCanUseMoreSpace = tocContentHeight > tocHeight + 0.001
            || tocContentHeight >= longTOCThreshold
        guard tocCanUseMoreSpace else {
            return InspectorInfoSectionSplitSizer.Result(metadataHeight: metadataHeight, tocHeight: tocHeight)
        }

        let reusableMetadataSpace = max(0, metadataHeight - metadataNeededHeight)
        if reusableMetadataSpace > 0 {
            let maximumTOCAfterReclaiming = min(
                tocRange.upperBound,
                budget - metadataNeededHeight
            )
            let reclaimed = min(
                reusableMetadataSpace,
                max(0, maximumTOCAfterReclaiming - tocHeight)
            )
            metadataHeight -= reclaimed
            tocHeight += reclaimed
        }

        let remainingBudget = budget - metadataHeight - tocHeight
        if remainingBudget > 0 {
            let expanded = min(remainingBudget, max(0, tocRange.upperBound - tocHeight))
            tocHeight += expanded
        }

        return InspectorInfoSectionSplitSizer.Result(
            metadataHeight: clampedHeight(metadataHeight, range: metadataRange),
            tocHeight: clampedHeight(tocHeight, range: tocRange)
        )
    }

    static func clampedMetadataSplitHeight(
        candidate: CGFloat,
        budget: CGFloat,
        metadataRange: ClosedRange<CGFloat>,
        tocRange: ClosedRange<CGFloat>
    ) -> CGFloat {
        let minimumMetadata = metadataRange.lowerBound
        let maximumMetadata = min(
            metadataRange.upperBound,
            budget - tocRange.lowerBound
        )
        guard maximumMetadata >= minimumMetadata else {
            return minimumMetadata
        }
        return min(max(candidate, minimumMetadata), maximumMetadata)
    }

    static func sanitizePersistedSettings(
        infoSplitRatioSetting: Double,
        metadataSectionHeightSetting: Double,
        tocSectionHeightSetting: Double
    ) -> InspectorPersistedSplitSettings {
        InspectorPersistedSplitSettings(
            ratio: infoSplitRatioSetting.isFinite && infoSplitRatioSetting >= 0 && infoSplitRatioSetting <= 1
                ? infoSplitRatioSetting
                : 0,
            metadataHeight: metadataSectionHeightSetting.isFinite && metadataSectionHeightSetting >= 0
                ? metadataSectionHeightSetting
                : 0,
            tocHeight: tocSectionHeightSetting.isFinite && tocSectionHeightSetting >= 0
                ? tocSectionHeightSetting
                : 0
        )
    }

    private static func sanitizeNonNegative(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}
