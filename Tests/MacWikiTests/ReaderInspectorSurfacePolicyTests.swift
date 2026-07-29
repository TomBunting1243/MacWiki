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
}
