import SwiftUI
import Testing

@testable import MacWiki

struct DiscoverSurfacePolicyTests {
    @Test func reduceTransparencyUsesOpaqueSurfacesWithoutShadowsOrNativeGlass() {
        let personalization = MacWikiAccessibilityPersonalization(
            reduceMotion: false,
            reduceTransparency: true,
            differentiateWithoutColor: false,
            colorSchemeContrast: .standard
        )

        let policy = DiscoverSurfacePolicy(
            personalization: personalization,
            nativeGlassEnabled: true,
            baseBorderOpacity: 0.32
        )

        #expect(policy.usesOpaqueBackground)
        #expect(!policy.usesNativeGlass)
        #expect(policy.borderOpacity == 0.48)
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

        let policy = DiscoverSurfacePolicy(
            personalization: personalization,
            nativeGlassEnabled: true,
            baseBorderOpacity: 0.34
        )

        #expect(policy.usesOpaqueBackground)
        #expect(!policy.usesNativeGlass)
        #expect(policy.borderOpacity == 0.62)
        #expect(policy.borderWidth == 1)
        #expect(policy.shadowMultiplier == 0)
    }

    @Test func standardPolicyPreservesNativeGlassAndRequestedBorder() {
        let policy = DiscoverSurfacePolicy(
            personalization: .standard,
            nativeGlassEnabled: true,
            baseBorderOpacity: 0.38
        )

        #expect(!policy.usesOpaqueBackground)
        #expect(policy.usesNativeGlass)
        #expect(policy.borderOpacity == 0.38)
        #expect(policy.borderWidth == 0.7)
        #expect(policy.shadowMultiplier == 1)
    }

}
