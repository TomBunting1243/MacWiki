import SwiftUI
import AppKit

enum ColumnChromeMetrics {
    static let titlebarBandHeight: CGFloat = 40
    static let topBarHeight: CGFloat = 32
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

    /// Combined overlay height the reader content must clear when it underlaps
    /// the top tab lane and the unified titlebar band above it.
    static func readerChromeOverlayHeight() -> CGFloat {
        titlebarBandHeight + topBarHeight
    }

    /// Suggested content inset that clears the reader-owned overlay chrome with comfortable breathing room.
    static func readerContentTopInset(
        additionalSpacing: CGFloat = 12
    ) -> CGFloat {
        readerChromeOverlayHeight() + additionalSpacing
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

private struct WindowMaterialBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
    }
}

private struct AppKitGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.configure(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.configure(cornerRadius: cornerRadius)
    }

    @MainActor
    final class HostView: NSView {
        private var hostedEffectView: NSView?

        func configure(cornerRadius: CGFloat) {
            let effectView = resolvedEffectView()
            if effectView.superview !== self {
                hostedEffectView?.removeFromSuperview()
                effectView.frame = bounds
                effectView.autoresizingMask = [.width, .height]
                addSubview(effectView)
                hostedEffectView = effectView
            }

            if #available(macOS 26, *),
               let glassView = effectView as? NSGlassEffectView {
                glassView.cornerRadius = cornerRadius
                glassView.style = .regular
                glassView.tintColor = nil
            } else if let visualEffectView = effectView as? NSVisualEffectView {
                visualEffectView.material = .sidebar
                visualEffectView.blendingMode = .withinWindow
                visualEffectView.state = .active
                visualEffectView.isEmphasized = false
            }
        }

        override func layout() {
            super.layout()
            hostedEffectView?.frame = bounds
        }

        private func resolvedEffectView() -> NSView {
            if #available(macOS 26, *),
               let glassView = hostedEffectView as? NSGlassEffectView {
                return glassView
            }

            if let visualEffectView = hostedEffectView as? NSVisualEffectView {
                return visualEffectView
            }

            if #available(macOS 26, *) {
                let glassView = NSGlassEffectView(frame: bounds)
                glassView.contentView = NSView(frame: bounds)
                glassView.contentView?.wantsLayer = true
                glassView.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
                return glassView
            }

            let visualEffectView = NSVisualEffectView(frame: bounds)
            return visualEffectView
        }
    }
}

struct CornerAdaptedInsetsReader: NSViewRepresentable {
    let onChange: (EdgeInsets) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.onChange = onChange
        view.reportInsetsIfNeeded()
    }

    @MainActor
    final class ObserverView: NSView {
        var onChange: ((EdgeInsets) -> Void)?
        private var lastReportedInsets = EdgeInsets()
        private var hasReportedInsets = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reportInsetsIfNeeded()
        }

        override func layout() {
            super.layout()
            reportInsetsIfNeeded()
        }

        func reportInsetsIfNeeded() {
            let resolvedInsets = resolvedCornerInsets()
            guard !hasReportedInsets || !edgeInsetsEqual(lastReportedInsets, resolvedInsets) else {
                return
            }

            hasReportedInsets = true
            lastReportedInsets = resolvedInsets

            DispatchQueue.main.async { [resolvedInsets, onChange] in
                onChange?(resolvedInsets)
            }
        }

        private func resolvedCornerInsets() -> EdgeInsets {
            let fallbackInsets: NSEdgeInsets
            if #available(macOS 26, *) {
                fallbackInsets = edgeInsets(for: .margins(cornerAdaptation: .horizontal))
            } else {
                fallbackInsets = safeAreaInsets
            }

            if let trafficLightInsets = resolvedTrafficLightInsets() {
                return EdgeInsets(
                    top: trafficLightInsets.top,
                    leading: trafficLightInsets.leading,
                    bottom: fallbackInsets.bottom,
                    trailing: fallbackInsets.right
                )
            }

            return EdgeInsets(
                top: fallbackInsets.top,
                leading: fallbackInsets.left,
                bottom: fallbackInsets.bottom,
                trailing: fallbackInsets.right
            )
        }

        private func resolvedTrafficLightInsets() -> EdgeInsets? {
            guard let window else { return nil }

            let buttons = [
                NSWindow.ButtonType.closeButton,
                .miniaturizeButton,
                .zoomButton
            ].compactMap { buttonType -> NSButton? in
                guard let button = window.standardWindowButton(buttonType), !button.isHidden else {
                    return nil
                }
                return button
            }

            guard !buttons.isEmpty else { return nil }

            var unionRect: NSRect?
            for button in buttons {
                let buttonRect = convert(button.bounds, from: button)
                unionRect = unionRect.map { $0.union(buttonRect) } ?? buttonRect
            }

            guard let unionRect else { return nil }

            return EdgeInsets(
                top: max(10, bounds.maxY - unionRect.minY + 8),
                leading: max(10, unionRect.maxX + 12),
                bottom: 0,
                trailing: 0
            )
        }

        private func edgeInsetsEqual(_ lhs: EdgeInsets, _ rhs: EdgeInsets) -> Bool {
            abs(lhs.top - rhs.top) < 0.5 &&
            abs(lhs.leading - rhs.leading) < 0.5 &&
            abs(lhs.bottom - rhs.bottom) < 0.5 &&
            abs(lhs.trailing - rhs.trailing) < 0.5
        }
    }
}

struct SidebarPaneBackground: View {
    var body: some View {
        WindowMaterialBackground(material: .sidebar)
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
            AppKitGlassBackground(cornerRadius: Metrics.cornerRadius)
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

struct TitlebarSectionBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    private var accentTint: Color {
        Color(nsColor: .controlAccentColor)
    }

    private var baseFill: Color {
        Color(nsColor: colorScheme == .dark ? .underPageBackgroundColor : .controlBackgroundColor)
    }

    var body: some View {
        Rectangle()
            .fill(baseFill)
            .overlay {
                Color(nsColor: .controlBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.34 : 0.28)
            }
            .overlay {
                LinearGradient(
                    colors: [
                        accentTint.opacity(colorScheme == .dark ? 0.10 : 0.085),
                        accentTint.opacity(colorScheme == .dark ? 0.045 : 0.036),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .overlay {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.04 : 0.03)
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
                    .opacity(colorScheme == .dark ? 0.08 : 0.026)
            }
    }
}
