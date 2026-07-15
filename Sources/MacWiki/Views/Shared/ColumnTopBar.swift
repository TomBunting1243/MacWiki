import SwiftUI

enum ColumnChromeMetrics {
    static let horizontalPadding: CGFloat = 9
    static let dividerOpacity: CGFloat = 0.065
    static let internalDividerOpacity: CGFloat = 0.035
    static let darkDividerOpacity: CGFloat = 0.038
    static let darkInternalDividerOpacity: CGFloat = 0.020

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
}

enum TopChromeControlMetrics {
    static let groupButtonSize: CGFloat = 25
}

enum ColumnMotion {
    static let sidebarVisibility = Animation.interactiveSpring(response: 0.30, dampingFraction: 0.90, blendDuration: 0.12)
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

    static func tabSelect(density: Density) -> Animation {
        switch density {
        case .compact:
            return .spring(response: 0.22, dampingFraction: 0.92)
        case .regular:
            return .spring(response: 0.24, dampingFraction: 0.90)
        case .spacious:
            return .spring(response: 0.27, dampingFraction: 0.89)
        }
    }

    static func tabCreateClose(density: Density) -> Animation {
        switch density {
        case .compact:
            return .spring(response: 0.20, dampingFraction: 0.95)
        case .regular:
            return .spring(response: 0.22, dampingFraction: 0.94)
        case .spacious:
            return .spring(response: 0.25, dampingFraction: 0.92)
        }
    }

    static func neighborShift(density: Density) -> Animation {
        switch density {
        case .compact:
            return .interactiveSpring(
                response: 0.28,
                dampingFraction: 0.91,
                blendDuration: 0.08
            )
        case .regular:
            return .interactiveSpring(
                response: 0.32,
                dampingFraction: 0.90,
                blendDuration: 0.08
            )
        case .spacious:
            return .interactiveSpring(
                response: 0.36,
                dampingFraction: 0.89,
                blendDuration: 0.10
            )
        }
    }

    static func snapBack(density: Density) -> Animation {
        switch density {
        case .compact:
            return .spring(response: 0.22, dampingFraction: 0.84, blendDuration: 0.05)
        case .regular:
            return .spring(response: 0.25, dampingFraction: 0.84, blendDuration: 0.06)
        case .spacious:
            return .spring(response: 0.28, dampingFraction: 0.84, blendDuration: 0.08)
        }
    }

    static func dragLift(density: Density) -> Animation {
        switch density {
        case .compact:
            return .spring(response: 0.22, dampingFraction: 0.80)
        case .regular:
            return .spring(response: 0.24, dampingFraction: 0.79)
        case .spacious:
            return .spring(response: 0.26, dampingFraction: 0.78)
        }
    }

    static func hover(density: Density) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: 0.13)
        case .regular:
            return .easeOut(duration: 0.14)
        case .spacious:
            return .easeOut(duration: 0.15)
        }
    }

    static func closeReveal(density: Density) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: 0.13)
        case .regular:
            return .easeOut(duration: 0.13)
        case .spacious:
            return .easeOut(duration: 0.14)
        }
    }

    static func closeHide(density: Density) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: 0.16)
        case .regular:
            return .easeOut(duration: 0.16)
        case .spacious:
            return .easeOut(duration: 0.17)
        }
    }

    static func overflowAffordance(density: Density) -> Animation {
        switch density {
        case .compact:
            return .easeOut(duration: 0.15)
        case .regular:
            return .easeOut(duration: 0.16)
        case .spacious:
            return .easeOut(duration: 0.17)
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
