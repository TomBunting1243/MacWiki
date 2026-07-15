import SwiftUI

enum ColumnChromeMetrics {
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
    static let groupButtonSize: CGFloat = 25
}

enum ColumnMotion {
    static let sidebarVisibility = Animation.interactiveSpring(response: 0.30, dampingFraction: 0.90, blendDuration: 0.12)
    static let readerOnlyVisibility = Animation.interactiveSpring(response: 0.44, dampingFraction: 0.93, blendDuration: 0.18)
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
    @Environment(\.macWikiAccessibilityPersonalization.reduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *) {
            Rectangle()
                .fill(.thinMaterial)
                .backgroundExtensionEffect()
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
