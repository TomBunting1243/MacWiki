import SwiftUI

struct MacWikiAccessibilityPersonalization: Equatable {
    var reduceMotion: Bool
    var reduceTransparency: Bool
    var differentiateWithoutColor: Bool
    var colorSchemeContrast: ColorSchemeContrast

    static let standard = Self(
        reduceMotion: false,
        reduceTransparency: false,
        differentiateWithoutColor: false,
        colorSchemeContrast: .standard
    )
}

private struct MacWikiAccessibilityPersonalizationKey: EnvironmentKey {
    static let defaultValue = MacWikiAccessibilityPersonalization.standard
}

extension EnvironmentValues {
    var macWikiAccessibilityPersonalization: MacWikiAccessibilityPersonalization {
        get { self[MacWikiAccessibilityPersonalizationKey.self] }
        set { self[MacWikiAccessibilityPersonalizationKey.self] = newValue }
    }
}

struct MacWikiQAPersonalizationOverrides: Equatable {
    static let environmentKey = "MACWIKI_QA_ACCESSIBILITY_PROFILE"

    let reduceMotion: Bool?
    let reduceTransparency: Bool?
    let increaseContrast: Bool?
    let differentiateWithoutColor: Bool?

    static let current = requested(in: ProcessInfo.processInfo.environment)

    static func requested(in environment: [String: String]) -> Self? {
        guard MacWikiQAEnvironment.trustedSuiteName(in: environment) != nil,
              let rawProfile = environment[environmentKey] else {
            return nil
        }

        let tokens = Set(
            rawProfile
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let supportedTokens: Set<String> = [
            "all",
            "reduce-motion",
            "reduce-transparency",
            "increase-contrast",
            "differentiate-without-color"
        ]
        guard !tokens.isEmpty, tokens.isSubset(of: supportedTokens) else {
            return nil
        }

        let enablesAll = tokens.contains("all")
        return Self(
            reduceMotion: enablesAll || tokens.contains("reduce-motion") ? true : nil,
            reduceTransparency: enablesAll || tokens.contains("reduce-transparency") ? true : nil,
            increaseContrast: enablesAll || tokens.contains("increase-contrast") ? true : nil,
            differentiateWithoutColor: enablesAll || tokens.contains("differentiate-without-color") ? true : nil
        )
    }
}

private struct MacWikiQAPersonalizationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var systemDifferentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var systemColorSchemeContrast

    let overrides: MacWikiQAPersonalizationOverrides?

    func body(content: Content) -> some View {
        let personalization = MacWikiAccessibilityPersonalization(
            reduceMotion: overrides?.reduceMotion ?? systemReduceMotion,
            reduceTransparency: overrides?.reduceTransparency ?? systemReduceTransparency,
            differentiateWithoutColor: overrides?.differentiateWithoutColor ?? systemDifferentiateWithoutColor,
            colorSchemeContrast: overrides?.increaseContrast == true ? .increased : systemColorSchemeContrast
        )

        ZStack(alignment: .bottomTrailing) {
            content

            if overrides != nil {
                MacWikiQAPersonalizationProbe()
            }
        }
        .environment(\.macWikiAccessibilityPersonalization, personalization)
    }
}

private struct MacWikiQAPersonalizationProbe: View {
    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("qa.accessibility-personalization")
            .accessibilityLabel("Accessibility personalization, \(accessibilityValue)")
    }

    private var accessibilityValue: String {
        [
            "Reduce Motion: \(personalization.reduceMotion ? "On" : "Off")",
            "Reduce Transparency: \(personalization.reduceTransparency ? "On" : "Off")",
            "Increase Contrast: \(personalization.colorSchemeContrast == .increased ? "On" : "Off")",
            "Differentiate Without Color: \(personalization.differentiateWithoutColor ? "On" : "Off")"
        ].joined(separator: ", ")
    }
}

extension View {
    func macWikiQAAccessibilityEnvironment(
        _ overrides: MacWikiQAPersonalizationOverrides? = .current
    ) -> some View {
        modifier(MacWikiQAPersonalizationModifier(overrides: overrides))
    }
}
