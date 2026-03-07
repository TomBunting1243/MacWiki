import SwiftUI

enum ColumnChromeMetrics {
    static let topBarHeight: CGFloat = 32
    /// Tiny downward optical nudge so grouped toolbar controls appear centered
    /// against the lane highlight/divider stack.
    static let readerToolbarOpticalYOffset: CGFloat = 0.6
    /// Minimum blank space to clear the traffic-light buttons (used by sidebar).
    static let trafficLightsClearance: CGFloat = 38
    /// Minimum title-bar height when content (text) sits below traffic lights.
    static let titleBarClearance: CGFloat = 52
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

    static func titlebarBandHeight(windowTopObscuredHeight: CGFloat) -> CGFloat {
        max(windowTopObscuredHeight, titleBarClearance)
    }

    static func internalDividerOpacity(for colorScheme: ColorScheme) -> CGFloat {
        colorScheme == .dark ? darkInternalDividerOpacity : internalDividerOpacity
    }

    /// Combined overlay height the reader content must clear when it underlaps
    /// the window toolbar. The center reader now flows beneath the native
    /// toolbar glass, so article content needs to clear both the titlebar band
    /// and the reader-owned tab lane.
    static func readerChromeOverlayHeight(windowTopObscuredHeight: CGFloat) -> CGFloat {
        titlebarBandHeight(windowTopObscuredHeight: windowTopObscuredHeight) + topBarHeight
    }

    /// Suggested content inset that clears the reader-owned overlay chrome with comfortable breathing room.
    static func readerContentTopInset(
        windowTopObscuredHeight: CGFloat,
        additionalSpacing: CGFloat = 12
    ) -> CGFloat {
        readerChromeOverlayHeight(windowTopObscuredHeight: windowTopObscuredHeight) + additionalSpacing
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

struct ColumnChromeBackground: View {
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.082 : 0.050)
                }
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.028 : 0.016)
                }
        } else {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        return Rectangle()
            .fill(.thinMaterial)
            .overlay {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.12 : 0.075)
            }
            .overlay {
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.06 : 0.035)
            }
    }
}

struct SidebarPaneBackground: View {
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.092 : 0.058)
                }
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.032 : 0.020)
                }
        } else {
            fallbackBackground
        }
    }

    private var fallbackBackground: some View {
        return Rectangle()
            .fill(.thinMaterial)
            .overlay {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.14 : 0.085)
            }
            .overlay {
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.09 : 0.055)
            }
    }
}

struct ToolbarBandBackground: View {
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme

    private var accentTint: Color {
        Color(nsColor: .controlAccentColor)
    }

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
                .overlay {
                    toolbarTintOverlay
                }
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.045 : 0.026)
                }
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.016 : 0.008)
                }
        } else {
            Rectangle()
                .fill(.thinMaterial)
                .overlay {
                    toolbarTintOverlay
                }
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.075 : 0.042)
                }
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.026 : 0.014)
                }
        }
    }

    private var toolbarTintOverlay: some View {
        LinearGradient(
            colors: [
                accentTint.opacity(colorScheme == .dark ? 0.078 : 0.032),
                accentTint.opacity(colorScheme == .dark ? 0.034 : 0.014),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.11 : 0.07)
                }
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.040 : 0.022)
                }
        } else {
            Rectangle()
                .fill(.thinMaterial)
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.16 : 0.095)
                }
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.075 : 0.042)
                }
        }
    }
}

struct WorkspaceBackdropBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay {
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.10 : 0.038)
            }
    }
}

struct ColumnTopChrome<Content: View>: View {
    private let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, ColumnChromeMetrics.horizontalPadding)
            .frame(height: ColumnChromeMetrics.topBarHeight)
            .frame(maxWidth: .infinity)
            .background {
                ColumnChromeBackground()
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                    .frame(height: 0.5)
            }
    }
}

struct ColumnTopBar<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        ColumnTopChrome {
            HStack(spacing: 8) {
                leading
                Spacer(minLength: 0)
                trailing
            }
        }
    }
}

extension ColumnTopBar where Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, trailing: { EmptyView() })
    }
}
