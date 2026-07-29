import SwiftUI
import Testing

@testable import MacWiki

struct MacWikiGlassPolicyTests {
    @Test func standardPersonalizationAllowsNativeGlass() {
        let policy = MacWikiGlassRuntime.surfacePolicy(
            isEnabled: true,
            forceLegacyFallback: false,
            personalization: .standard
        )

        #expect(policy.usesNativeGlass)
        #expect(!policy.usesOpaqueBackground)
        #expect(policy.allowsDepth)
    }

    @Test func userPreferenceAndFallbackCanDisableGlass() {
        #expect(
            !MacWikiGlassRuntime.usesNativeGlass(
                isEnabled: false,
                forceLegacyFallback: false,
                personalization: .standard
            )
        )
        #expect(
            !MacWikiGlassRuntime.usesNativeGlass(
                isEnabled: true,
                forceLegacyFallback: true,
                personalization: .standard
            )
        )
    }

    @Test func accessibilityRequestsAlwaysOverrideGlassPreferences() {
        let reduceTransparency = MacWikiAccessibilityPersonalization(
            reduceMotion: false,
            reduceTransparency: true,
            differentiateWithoutColor: false,
            colorSchemeContrast: .standard
        )
        let increaseContrast = MacWikiAccessibilityPersonalization(
            reduceMotion: false,
            reduceTransparency: false,
            differentiateWithoutColor: false,
            colorSchemeContrast: .increased
        )

        for isEnabled in [false, true] {
            for forceLegacyFallback in [false, true] {
                for personalization in [reduceTransparency, increaseContrast] {
                    let policy = MacWikiGlassRuntime.surfacePolicy(
                        isEnabled: isEnabled,
                        forceLegacyFallback: forceLegacyFallback,
                        personalization: personalization
                    )

                    #expect(!policy.usesNativeGlass)
                    #expect(policy.usesOpaqueBackground)
                    #expect(!policy.allowsDepth)
                }
            }
        }
    }

    @Test func disablingGlassKeepsAccessibleMaterialDepthWhenTransparencyIsAllowed() {
        for policy in [
            MacWikiGlassRuntime.surfacePolicy(
                isEnabled: false,
                forceLegacyFallback: false,
                personalization: .standard
            ),
            MacWikiGlassRuntime.surfacePolicy(
                isEnabled: true,
                forceLegacyFallback: true,
                personalization: .standard
            )
        ] {
            #expect(!policy.usesNativeGlass)
            #expect(!policy.usesOpaqueBackground)
            #expect(policy.allowsDepth)
        }
    }

    @Test func convenienceOverloadUsesTheSamePersonalizationPolicy() {
        #expect(
            MacWikiGlassRuntime.usesNativeGlass(
                forceLegacyFallback: false,
                personalization: .standard
            )
        )

        let highContrast = MacWikiAccessibilityPersonalization(
            reduceMotion: false,
            reduceTransparency: false,
            differentiateWithoutColor: false,
            colorSchemeContrast: .increased
        )
        #expect(
            !MacWikiGlassRuntime.usesNativeGlass(
                forceLegacyFallback: false,
                personalization: highContrast
            )
        )
    }

    @Test func materialSurfacesShareTheGlobalAccessibilityBoundaryWithoutGlass() {
        let standard = MacWikiGlassRuntime.materialSurfacePolicy(personalization: .standard)
        #expect(!standard.usesNativeGlass)
        #expect(!standard.usesOpaqueBackground)
        #expect(standard.allowsDepth)

        let reduceTransparency = MacWikiAccessibilityPersonalization(
            reduceMotion: false,
            reduceTransparency: true,
            differentiateWithoutColor: false,
            colorSchemeContrast: .standard
        )
        let accessible = MacWikiGlassRuntime.materialSurfacePolicy(
            personalization: reduceTransparency
        )
        #expect(!accessible.usesNativeGlass)
        #expect(accessible.usesOpaqueBackground)
        #expect(!accessible.allowsDepth)
    }
}
