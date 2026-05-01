import Foundation
import Testing

@testable import MacWiki

struct ReaderAppearanceTests {
    @Test func defaultReaderTypographyMatchesProductPreference() {
        let appearance = ReaderAppearance.default

        #expect(appearance.fontPreset == .newYork)
        #expect(approximatelyEqual(appearance.fontSize, 17))
    }

    @Test func webPayloadContainsAllTypographyKeys() {
        let payload = ReaderAppearance.default.webPayload
        let expectedKeys = Set([
            "bodyFontFamily",
            "headingFontFamily",
            "fontSize",
            "lineHeight",
            "paragraphSpacing",
            "contentWidth",
            "inlinePadding",
            "headingScale"
        ])

        #expect(Set(payload.keys) == expectedKeys)
    }

    @Test func viewportResolutionPreservesValuesOnWideLayout() {
        let appearance = ReaderAppearance.default
        let resolved = appearance.resolvedForViewportWidth(1400)

        #expect(resolved == appearance)
    }

    @Test func viewportResolutionClampsUnsafePaddingOnNarrowLayout() {
        let appearance = ReaderAppearance(
            fontPreset: .system,
            fontSize: 17,
            lineHeight: 1.65,
            paragraphSpacing: 16,
            contentWidth: 860,
            horizontalPadding: 120,
            headingScale: 1.0
        )

        let resolved = appearance.resolvedForViewportWidth(500)

        #expect(approximatelyEqual(resolved.horizontalPadding, 70))
        #expect(approximatelyEqual(resolved.contentWidth, 360))
    }

    @Test func viewportResolutionKeepsTinyWindowsReadable() {
        let appearance = ReaderAppearance(
            fontPreset: .system,
            fontSize: 17,
            lineHeight: 1.65,
            paragraphSpacing: 16,
            contentWidth: 420,
            horizontalPadding: 120,
            headingScale: 1.0
        )

        let resolved = appearance.resolvedForViewportWidth(320)

        #expect(approximatelyEqual(resolved.horizontalPadding, 12))
        #expect(approximatelyEqual(resolved.contentWidth, 296))
    }

    @Test func viewportResolutionMaintainsReadableColumnWhenViewportAllows() {
        let appearance = ReaderAppearance(
            fontPreset: .system,
            fontSize: 17,
            lineHeight: 1.65,
            paragraphSpacing: 16,
            contentWidth: 1400,
            horizontalPadding: 120,
            headingScale: 1.0
        )

        let readableThreshold = ReaderAppearance.minimumReadableColumnWidth
        let viewportSamples: [Double] = [380, 420, 600, 900]

        for viewport in viewportSamples {
            let resolved = appearance.resolvedForViewportWidth(viewport)
            let availableWidth = viewport - (resolved.horizontalPadding * 2)

            #expect(resolved.horizontalPadding >= ReaderAppearance.horizontalPaddingRange.lowerBound)
            #expect(resolved.horizontalPadding <= appearance.horizontalPadding)
            #expect(approximatelyEqual(resolved.contentWidth, min(appearance.contentWidth, max(availableWidth, 0))))

            let canFitReadableWidth = viewport >= (readableThreshold + (ReaderAppearance.horizontalPaddingRange.lowerBound * 2))
            if canFitReadableWidth {
                #expect(resolved.contentWidth >= readableThreshold)
            }
        }
    }

    @Test func viewportResolutionIgnoresInvalidViewport() {
        let appearance = ReaderAppearance.default

        #expect(appearance.resolvedForViewportWidth(0) == appearance)
        #expect(appearance.resolvedForViewportWidth(-100) == appearance)
        #expect(appearance.resolvedForViewportWidth(.infinity) == appearance)
    }

    private func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        abs(lhs - rhs) <= tolerance
    }
}
