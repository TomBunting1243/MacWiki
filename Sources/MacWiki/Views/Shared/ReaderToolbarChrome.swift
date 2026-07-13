import SwiftUI

enum ReaderToolbarMetrics {
    static let toolbarTopPadding: CGFloat = 7
    static let toolbarHeight: CGFloat = 52
    static let trafficLightColumnThreshold: CGFloat = 150
    static let trafficLightReservedWidth: CGFloat = 86
    static let trafficLightTrailingGap: CGFloat = 10
}

enum ReaderToolbarDensity: Equatable {
    case regular
    case compact
    case narrow

    init(width: CGFloat) {
        if width < 540 {
            self = .narrow
        } else if width < 780 {
            self = .compact
        } else {
            self = .regular
        }
    }

    var buttonSize: CGFloat {
        switch self {
        case .regular: 34
        case .compact: 31
        case .narrow: 28
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .regular: 20
        case .compact: 12
        case .narrow: 6
        }
    }

    var pillHorizontalPadding: CGFloat {
        switch self {
        case .regular: 4
        case .compact: 3
        case .narrow: 2
        }
    }

    var pillVerticalPadding: CGFloat {
        switch self {
        case .regular, .compact: 1
        case .narrow: 0
        }
    }

    var pillSpacing: CGFloat {
        switch self {
        case .regular: 2
        case .compact, .narrow: 1
        }
    }

    var clusterSpacing: CGFloat {
        switch self {
        case .regular, .compact: 10
        case .narrow: 7
        }
    }

    var dividerHeight: CGFloat {
        switch self {
        case .regular: 21
        case .compact: 19
        case .narrow: 16
        }
    }

    var iconPointSize: CGFloat {
        switch self {
        case .regular: 15.5
        case .compact: 14.5
        case .narrow: 13.5
        }
    }
}

struct ReaderToolbarVisibility: Equatable {
    var showsBackForward: Bool
    var showsReaderStyle: Bool
    var showsPageViews: Bool
    var showsOpenInBrowser: Bool
    var showsShare: Bool

    init(width: CGFloat) {
        showsBackForward = width >= 620
        showsReaderStyle = width >= 700
        showsShare = width >= 760
        showsPageViews = width >= 860
        showsOpenInBrowser = width >= 940
    }

    var hasOverflowActions: Bool {
        !showsBackForward ||
        !showsReaderStyle ||
        !showsPageViews ||
        !showsOpenInBrowser ||
        !showsShare
    }
}

enum ReaderToolbarControl: Hashable {
    case listContents
    case back
    case forward
    case search
    case save
    case read
    case find
    case style
    case pageViews
    case openInBrowser
    case share
    case more
    case inspector
}

struct ReaderToolbarPill<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let density: ReaderToolbarDensity
    let usesNativeGlass: Bool
    let liquidGlassChrome: Bool
    @ViewBuilder let content: Content

    init(
        density: ReaderToolbarDensity,
        usesNativeGlass: Bool,
        liquidGlassChrome: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.density = density
        self.usesNativeGlass = usesNativeGlass
        self.liquidGlassChrome = liquidGlassChrome
        self.content = content()
    }

    var body: some View {
        let pill = HStack(spacing: density.pillSpacing) {
            content
        }
        .padding(.horizontal, density.pillHorizontalPadding)
        .padding(.vertical, density.pillVerticalPadding)

        if #available(macOS 26, *), usesNativeGlass {
            pill
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay { nativeStroke }
                .fixedSize()
                .shadow(color: shadowColor, radius: 7, x: 0, y: 3)
                .compositingGroup()
        } else {
            pill
                .background { fallbackBackground }
                .fixedSize()
                .shadow(color: shadowColor, radius: 7, x: 0, y: 3)
                .compositingGroup()
        }
    }

    private var shadowColor: Color {
        .black.opacity(colorScheme == .dark ? 0.10 : 0.026)
    }

    private var nativeStroke: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.056 : 0.038), lineWidth: 0.45)
    }

    @ViewBuilder
    private var fallbackBackground: some View {
        let darkMode = colorScheme == .dark
        let shape = Capsule(style: .continuous)
        if liquidGlassChrome {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.16 : 0.42))
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(darkMode ? 0.074 : 0.056), lineWidth: 0.50)
                }
        } else {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    shape.fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.11 : 0.065))
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(darkMode ? 0.06 : 0.045), lineWidth: 0.44)
                }
        }
    }
}

struct ReaderToolbarIconLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let control: ReaderToolbarControl
    let systemImage: String
    let isActive: Bool
    let isEnabled: Bool
    let density: ReaderToolbarDensity
    let hoveredControl: ReaderToolbarControl?

    var body: some View {
        let isHovered = hoveredControl == control
        let isInteractive = isEnabled && (isHovered || isActive)

        ZStack {
            iconBackground(isHovered: isHovered)

            Image(systemName: systemImage)
                .font(.system(size: density.iconPointSize, weight: isActive ? .medium : .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconForeground(isHovered: isHovered))
        }
        .frame(width: density.buttonSize, height: density.buttonSize)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isInteractive && !reduceMotion ? 1.012 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private func iconBackground(isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let darkMode = colorScheme == .dark
        let fillOpacity: Double
        if !isEnabled {
            fillOpacity = 0
        } else if isActive {
            fillOpacity = darkMode ? 0.16 : 0.095
        } else if isHovered {
            fillOpacity = darkMode ? 0.14 : 0.075
        } else {
            fillOpacity = 0
        }

        return shape
            .fill(Color.primary.opacity(fillOpacity))
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity((isHovered || isActive) && isEnabled ? (darkMode ? 0.10 : 0.060) : 0),
                    lineWidth: 0.40
                )
            }
            .shadow(
                color: .black.opacity((isHovered || isActive) && isEnabled ? (darkMode ? 0.18 : 0.055) : 0),
                radius: 2,
                x: 0,
                y: 1
            )
            .padding(2)
    }

    private func iconForeground(isHovered: Bool) -> Color {
        let darkMode = colorScheme == .dark
        if !isEnabled {
            return Color.primary.opacity(darkMode ? 0.38 : 0.34)
        }
        if isActive {
            return Color.primary.opacity(darkMode ? 0.88 : 0.84)
        }
        if isHovered {
            return Color.primary.opacity(darkMode ? 0.90 : 0.86)
        }
        return Color.primary.opacity(darkMode ? 0.80 : 0.74)
    }
}

struct ReaderToolbarOverflowPopover: View {
    @Binding var isPresented: Bool
    let visibility: ReaderToolbarVisibility
    let canGoBack: Bool
    let canGoForward: Bool
    let canActOnCurrentArticle: Bool
    let articleURL: URL?
    let onBack: () -> Void
    let onForward: () -> Void
    let onReaderStyle: () -> Void
    let onPageViews: () -> Void
    let onOpenInBrowser: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !visibility.showsBackForward {
                actionButton("Back", systemImage: "chevron.left", isEnabled: canGoBack, action: onBack)
                actionButton("Forward", systemImage: "chevron.right", isEnabled: canGoForward, action: onForward)
            }

            if !visibility.showsReaderStyle {
                actionButton(
                    "Reader Style",
                    systemImage: "textformat.size",
                    isEnabled: canActOnCurrentArticle,
                    action: onReaderStyle
                )
            }

            if !visibility.showsPageViews {
                actionButton(
                    "Page Views",
                    systemImage: "chart.xyaxis.line",
                    isEnabled: canActOnCurrentArticle,
                    action: onPageViews
                )
            }

            if !visibility.showsOpenInBrowser {
                actionButton(
                    "Open in Browser",
                    systemImage: "safari",
                    isEnabled: canActOnCurrentArticle,
                    action: onOpenInBrowser
                )
            }

            if !visibility.showsShare {
                if let articleURL {
                    ShareLink(item: articleURL) {
                        actionLabel("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                } else {
                    actionButton("Share", systemImage: "square.and.arrow.up", isEnabled: false) {}
                }
            }

            if !visibility.hasOverflowActions {
                actionButton(
                    "Open in Browser",
                    systemImage: "safari",
                    isEnabled: canActOnCurrentArticle,
                    action: onOpenInBrowser
                )
            }
        }
        .padding(8)
        .frame(width: 190)
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            isPresented = false
            DispatchQueue.main.async {
                action()
            }
        } label: {
            actionLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        SwiftUI.Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
