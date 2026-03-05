import CoreGraphics

enum InspectorInfoSectionSplitSizer {
    struct Result: Equatable {
        let metadataHeight: CGFloat
        let tocHeight: CGFloat
    }

    static func calculate(
        metadataContentHeight: CGFloat,
        tocContentHeight: CGFloat,
        viewportHeight: CGFloat?,
        metadataRange: ClosedRange<CGFloat>,
        tocRange: ClosedRange<CGFloat>,
        budgetRange: ClosedRange<CGFloat>,
        budgetRatio: CGFloat,
        fallbackBudget: CGFloat
    ) -> Result {
        let sanitizedBudgetRatio = sanitizeNonNegative(budgetRatio)
        let proposedBudget = if let viewportHeight, viewportHeight.isFinite, viewportHeight > 0 {
            viewportHeight * sanitizedBudgetRatio
        } else {
            fallbackBudget
        }
        let fallbackClampedBudget = clamp(
            fallbackBudget,
            to: budgetRange,
            fallback: budgetRange.lowerBound
        )
        let budget = clamp(
            proposedBudget,
            to: budgetRange,
            fallback: fallbackClampedBudget
        )
        let metadataDesired = sanitizeNonNegative(metadataContentHeight)
        let tocDesired = sanitizeNonNegative(tocContentHeight)

        var metadataTarget: CGFloat
        var tocTarget: CGFloat

        // TOC-first policy:
        // 1) If both sections already fit, keep them compact.
        // 2) If we can fit the whole TOC while preserving minimum metadata height, do it.
        // 3) Otherwise, if metadata fully fits while preserving minimum TOC height, do that.
        // 4) If both are long, reserve both minimums and bias extra space toward TOC.
        let metadataMinimum = metadataRange.lowerBound
        let tocMinimum = tocRange.lowerBound

        let combinedDesired = metadataDesired + tocDesired
        if combinedDesired > 0, combinedDesired <= budget {
            metadataTarget = metadataDesired
            tocTarget = tocDesired
        } else if tocDesired <= (budget - metadataMinimum) {
            tocTarget = tocDesired
            metadataTarget = budget - tocTarget
        } else if metadataDesired <= (budget - tocMinimum) {
            metadataTarget = metadataDesired
            tocTarget = budget - metadataTarget
        } else {
            let distributableBudget = max(0, budget - metadataMinimum - tocMinimum)
            let metadataNeed = max(0, metadataDesired - metadataMinimum)
            let tocNeed = max(0, tocDesired - tocMinimum)
            let tocShare = weightedLongSectionShare(
                primaryDesired: tocNeed,
                secondaryDesired: metadataNeed,
                shareRange: 0.58...0.82
            )
            tocTarget = tocMinimum + (distributableBudget * tocShare)
            metadataTarget = budget - tocTarget
        }

        metadataTarget = clamp(
            metadataTarget,
            to: metadataRange,
            fallback: metadataRange.lowerBound
        )
        tocTarget = clamp(
            tocTarget,
            to: tocRange,
            fallback: tocRange.lowerBound
        )
        rebalanceToBudget(
            metadataHeight: &metadataTarget,
            tocHeight: &tocTarget,
            budget: budget,
            metadataRange: metadataRange,
            tocRange: tocRange
        )

        let safeMetadata = clamp(
            metadataTarget,
            to: metadataRange,
            fallback: metadataRange.lowerBound
        )
        let safeTOC = clamp(
            tocTarget,
            to: tocRange,
            fallback: tocRange.lowerBound
        )
        return Result(metadataHeight: safeMetadata, tocHeight: safeTOC)
    }

    private static func rebalanceToBudget(
        metadataHeight: inout CGFloat,
        tocHeight: inout CGFloat,
        budget: CGFloat,
        metadataRange: ClosedRange<CGFloat>,
        tocRange: ClosedRange<CGFloat>
    ) {
        metadataHeight = clamp(
            metadataHeight,
            to: metadataRange,
            fallback: metadataRange.lowerBound
        )
        tocHeight = clamp(
            tocHeight,
            to: tocRange,
            fallback: tocRange.lowerBound
        )
        guard budget.isFinite else { return }

        var overflow = metadataHeight + tocHeight - budget
        while overflow > 0.001 {
            let metadataSlack = metadataHeight - metadataRange.lowerBound
            let tocSlack = tocHeight - tocRange.lowerBound

            if metadataSlack <= 0, tocSlack <= 0 {
                break
            }

            if metadataSlack >= tocSlack, metadataSlack > 0 {
                let reduction = min(overflow, metadataSlack)
                metadataHeight -= reduction
                overflow -= reduction
            } else if tocSlack > 0 {
                let reduction = min(overflow, tocSlack)
                tocHeight -= reduction
                overflow -= reduction
            }
        }
    }

    private static func clamp(
        _ value: CGFloat,
        to range: ClosedRange<CGFloat>,
        fallback: CGFloat
    ) -> CGFloat {
        let lower = min(range.lowerBound, range.upperBound)
        let upper = max(range.lowerBound, range.upperBound)

        let resolvedFallback: CGFloat
        if fallback.isFinite {
            resolvedFallback = min(max(fallback, lower), upper)
        } else {
            resolvedFallback = lower
        }

        guard value.isFinite else {
            return resolvedFallback
        }
        return min(max(value, lower), upper)
    }

    private static func weightedLongSectionShare(
        primaryDesired: CGFloat,
        secondaryDesired: CGFloat,
        shareRange: ClosedRange<CGFloat>
    ) -> CGFloat {
        // Exponent < 1 dampens extreme differences while still adapting per article.
        let weightingExponent: CGFloat = 0.82
        let primaryWeight = pow(max(primaryDesired, 1), weightingExponent)
        let secondaryWeight = pow(max(secondaryDesired, 1), weightingExponent)
        guard primaryWeight.isFinite, secondaryWeight.isFinite else {
            return (shareRange.lowerBound + shareRange.upperBound) * 0.5
        }
        let denominator = primaryWeight + secondaryWeight
        guard denominator > 0 else { return 0.5 }
        let rawShare = primaryWeight / denominator
        return clamp(rawShare, to: shareRange, fallback: 0.5)
    }

    private static func sanitizeNonNegative(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}
