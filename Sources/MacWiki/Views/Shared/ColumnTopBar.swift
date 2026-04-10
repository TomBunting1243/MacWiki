import SwiftUI

enum ColumnChromeMetrics {
    /// Tiny downward optical nudge so grouped toolbar controls appear centered
    /// against the lane highlight/divider stack.
    static let readerToolbarOpticalYOffset: CGFloat = 0.6
    static let horizontalPadding: CGFloat = 9
    static let dividerOpacity: CGFloat = 0.065
    static let internalDividerOpacity: CGFloat = 0.035
    static let highlightStrongOpacity: CGFloat = 0.055
    static let highlightSoftOpacity: CGFloat = 0.012
    static let darkDividerOpacity: CGFloat = 0.038
    static let darkInternalDividerOpacity: CGFloat = 0.020
    static let darkHighlightStrongOpacity: CGFloat = 0.014
    static let darkHighlightSoftOpacity: CGFloat = 0.004
    static let darkBaseTintOpacity: CGFloat = 0.05

    static func dividerOpacity(for colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .dark ? darkDividerOpacity : dividerOpacity
    }

    static func internalDividerOpacity(for colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .dark ? darkInternalDividerOpacity : internalDividerOpacity
    }
}

enum ChromeIconMetrics {
    /// macOS default icon-control target is 28x28 pt; keep toolbar symbols sized
    /// typographically instead of forcing ad-hoc pixel dimensions.
    static let symbolPointSize: CGFloat = 13
    static let regularWeight: Font.Weight = .regular
    static let emphasizedWeight: Font.Weight = .semibold
    static let buttonSize: CGFloat = 28
    static let compactButtonSize: CGFloat = 24
}

enum TopChromeControlMetrics {
    static let groupHeight: CGFloat = 26
    static let groupButtonSize: CGFloat = 25
    static let groupInnerSpacing: CGFloat = 1
    static let groupHorizontalPadding: CGFloat = 5
    static let groupCornerRadius: CGFloat = 9
    static let activePlateCornerRadius: CGFloat = 6

    static func accessoryCornerRadius(compact: Bool) -> CGFloat {
        compact ? 9 : groupCornerRadius
    }
}

enum TopChromeControlSurface {
    static func tintOpacity(darkMode: Bool, compactAccessory: Bool = false) -> Double {
        if darkMode {
            return compactAccessory ? 0.18 : 0.16
        }
        return compactAccessory ? 0.08 : 0.07
    }

    static func sheenOpacity(darkMode: Bool, compactAccessory: Bool = false) -> Double {
        if darkMode {
            return compactAccessory ? 0.035 : 0.030
        }
        return compactAccessory ? 0.055 : 0.050
    }

    static func depthMultiplyOpacity(darkMode: Bool, compactAccessory: Bool = false) -> Double {
        if darkMode {
            return compactAccessory ? 0.050 : 0.045
        }
        return compactAccessory ? 0.012 : 0.010
    }

    static func borderOpacity(darkMode: Bool, liquid: Bool, compactAccessory: Bool = false) -> Double {
        if liquid {
            if darkMode {
                return compactAccessory ? 0.082 : 0.075
            }
            return compactAccessory ? 0.060 : 0.055
        }
        if darkMode {
            return compactAccessory ? 0.10 : 0.095
        }
        return compactAccessory ? 0.060 : 0.055
    }
}

enum ColumnMotion {
    static let sidebarVisibility = Animation.interactiveSpring(response: 0.30, dampingFraction: 0.90, blendDuration: 0.12)
    static let inspectorVisibility = Animation.interactiveSpring(response: 0.32, dampingFraction: 0.89, blendDuration: 0.12)
    static let sidebarRevealFollowDelay: Double = 0.14
}

enum TopChromeMotion {
    enum Density {
        case compact
        case regular
        case spacious

        static func resolve(for width: CGFloat) -> Density {
            if width < 560 { return .compact }
            if width > 900 { return .spacious }
            return .regular
        }
    }

    static func tabSelect(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .spring(response: strip ? 0.22 : 0.20, dampingFraction: 0.92)
        case .regular:
            return .spring(response: strip ? 0.24 : 0.22, dampingFraction: 0.90)
        case .spacious:
            return .spring(response: strip ? 0.27 : 0.25, dampingFraction: 0.89)
        }
    }

    static func tabCreateClose(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .spring(response: strip ? 0.20 : 0.18, dampingFraction: 0.95)
        case .regular:
            return .spring(response: strip ? 0.22 : 0.20, dampingFraction: 0.94)
        case .spacious:
            return .spring(response: strip ? 0.25 : 0.23, dampingFraction: 0.92)
        }
    }

    static func neighborShift(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .interactiveSpring(
                response: strip ? 0.28 : 0.26,
                dampingFraction: strip ? 0.91 : 0.90,
                blendDuration: 0.08
            )
        case .regular:
            return .interactiveSpring(
                response: strip ? 0.32 : 0.30,
                dampingFraction: strip ? 0.90 : 0.89,
                blendDuration: 0.08
            )
        case .spacious:
            return .interactiveSpring(
                response: strip ? 0.36 : 0.34,
                dampingFraction: strip ? 0.89 : 0.88,
                blendDuration: 0.10
            )
        }
    }

    static func snapBack(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .spring(response: strip ? 0.22 : 0.20, dampingFraction: 0.84, blendDuration: 0.05)
        case .regular:
            return .spring(response: strip ? 0.25 : 0.23, dampingFraction: 0.84, blendDuration: 0.06)
        case .spacious:
            return .spring(response: strip ? 0.28 : 0.26, dampingFraction: 0.84, blendDuration: 0.08)
        }
    }

    static func dragLift(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .spring(response: strip ? 0.22 : 0.20, dampingFraction: 0.80)
        case .regular:
            return .spring(response: strip ? 0.24 : 0.22, dampingFraction: 0.79)
        case .spacious:
            return .spring(response: strip ? 0.26 : 0.24, dampingFraction: 0.78)
        }
    }

    static func hover(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: strip ? 0.13 : 0.12)
        case .regular:
            return .easeOut(duration: strip ? 0.14 : 0.13)
        case .spacious:
            return .easeOut(duration: strip ? 0.15 : 0.14)
        }
    }

    static func closeReveal(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: strip ? 0.13 : 0.12)
        case .regular:
            return .easeOut(duration: strip ? 0.13 : 0.12)
        case .spacious:
            return .easeOut(duration: strip ? 0.14 : 0.13)
        }
    }

    static func closeHide(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: strip ? 0.16 : 0.14)
        case .regular:
            return .easeOut(duration: strip ? 0.16 : 0.14)
        case .spacious:
            return .easeOut(duration: strip ? 0.17 : 0.15)
        }
    }

    static func overflowAffordance(density: Density, strip: Bool) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: strip ? 0.15 : 0.14)
        case .regular:
            return .easeOut(duration: strip ? 0.16 : 0.15)
        case .spacious:
            return .easeOut(duration: strip ? 0.17 : 0.16)
        }
    }

    static func dragAutoScroll(density: Density) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: 0.12)
        case .regular:
            return .easeOut(duration: 0.13)
        case .spacious:
            return .easeOut(duration: 0.14)
        }
    }
}

struct SidebarPaneBackground: View {
    var body: some View {
        if #available(macOS 26, *) {
            Rectangle()
                .fill(.thinMaterial)
                .backgroundExtensionEffect()
        } else {
            Rectangle()
                .fill(.thinMaterial)
        }
    }
}

struct LeadingSidebarFloatingPaneBackground: View {
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme

    private enum Metrics {
        static let cornerRadius: CGFloat = 24
    }

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: Metrics.cornerRadius,
            bottomLeadingRadius: Metrics.cornerRadius,
            bottomTrailingRadius: Metrics.cornerRadius,
            topTrailingRadius: Metrics.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback) {
            panelShape
                .fill(.clear)
                .glassEffect(.regular, in: panelShape)
        } else {
            panelShape
                .fill(.thinMaterial)
                .overlay {
                    panelShape
                        .strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.035 : 0.055),
                            lineWidth: 0.6
                        )
                }
        }
    }
}

struct LeadingSidebarChromeMergeBackground: View {
    private enum Metrics {
        static let bridgeWidth: CGFloat = 112
        static let bridgeHeight: CGFloat = 26
        static let bridgeTopOffset: CGFloat = 8
        static let bridgeTrailingOffset: CGFloat = 18
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LeadingSidebarFloatingPaneBackground()

            LeadingSidebarChromeBridgeBackground()
                .frame(width: Metrics.bridgeWidth, height: Metrics.bridgeHeight)
                .offset(x: Metrics.bridgeTrailingOffset, y: Metrics.bridgeTopOffset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct LeadingSidebarChromeBridgeBackground: View {
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme

    private var bridgeShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: 12,
            topTrailingRadius: 12,
            style: .continuous
        )
    }

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback) {
            bridgeShape
                .fill(.clear)
                .glassEffect(.regular, in: bridgeShape)
        } else {
            bridgeShape
                .fill(.thinMaterial)
                .overlay {
                    bridgeShape
                        .strokeBorder(
                            Color.white.opacity(colorScheme == .dark ? 0.03 : 0.05),
                            lineWidth: 0.5
                        )
                }
        }
    }
}

struct ReaderTabLaneBackground: View {
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
        } else {
            Rectangle()
                .fill(.thinMaterial)
        }
    }
}

struct WorkspaceBackdropBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
    }
}
