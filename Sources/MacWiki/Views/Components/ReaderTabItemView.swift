import SwiftUI

/// Individual draggable tab item component
struct ReaderTabItemView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false

    let tab: ArticleTab
    let lists: [ReadingList]
    let allLabels: [Label]
    let liquidGlassChrome: Bool
    let isActive: Bool
    let isDragged: Bool
    let dragOffset: CGFloat
    let shiftAmount: CGFloat
    let tabWidth: CGFloat
    let interactionProfile: TabInteractionProfile
    let matchingSavedArticle: SavedArticle?
    let hasHighlights: Bool
    let readingProgress: Double
    let showSavedMarker: Bool
    let showHighlightMarker: Bool
    let showReadMarker: Bool
    let showProgressTrack: Bool
    let showActiveDepth: Bool
    let reduceMotion: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onClose: () -> Void
    let onSelect: () -> Void
    let onDragChanged: (CGFloat, CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var isHovered = false
    @State private var showCloseButton = false

    // MARK: - Drag Animation Settings
    private var liftScale: CGSize {
        isDragged ? CGSize(width: 1.02, height: 1.0) : CGSize(width: 1.0, height: 1.0)
    }

    private var liftShadow: CGFloat {
        isDragged ? 8 : 0
    }

    private var showsFavicon: Bool {
        tabWidth >= 98 || isActive
    }

    private var contentSpacing: CGFloat {
        if !showsFavicon && !showCloseButton {
            return 0
        }
        return tabWidth < 95 ? 5 : 6
    }

    private var horizontalPadding: CGFloat {
        tabWidth < 95 ? 8 : 9
    }

    private var normalizedProgress: Double {
        min(max(readingProgress, 0), 1)
    }

    private var isReadComplete: Bool {
        normalizedProgress >= 0.995 || tab.currentArticle?.isRead == true
    }

    private var isKeyWindow: Bool {
        appearsActive
    }

    private var increasedContrast: Bool {
        accessibilityPersonalization.colorSchemeContrast == .increased
    }

    private var usesNativeGlass: Bool {
        MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
        ) && !accessibilityPersonalization.reduceTransparency
    }

    private var showsSavedMarker: Bool {
        showSavedMarker && matchingSavedArticle != nil
    }

    private var showsHighlightMarker: Bool {
        showHighlightMarker && hasHighlights
    }

    private var showsReadMarker: Bool {
        showReadMarker && isReadComplete
    }

    private var showsSemanticStatusCluster: Bool {
        !tab.isPlaceholder &&
        tabWidth >= 132 &&
        (showsSavedMarker || showsHighlightMarker || showsReadMarker)
    }

    private var showsProgressTrack: Bool {
        showProgressTrack &&
        !tab.isPlaceholder &&
        tabWidth >= 132 &&
        (normalizedProgress > 0.12 || isReadComplete)
    }

    private var tabAccessibilityValue: String {
        TabAccessibilityStatus.value(
            isActive: isActive,
            isSaved: matchingSavedArticle != nil,
            hasHighlights: hasHighlights,
            isRead: isReadComplete,
            showsProgress: !tab.isPlaceholder && normalizedProgress > 0,
            progress: normalizedProgress
        )
    }

    private var tabHeight: CGFloat {
        ReaderTabLaneMetrics.tabHeight
    }

    private var tabCornerRadius: CGFloat {
        ReaderTabLaneMetrics.tabCornerRadius
    }

    private var closeButtonSize: CGFloat {
        18
    }

    private var closeGlyphSize: CGFloat {
        9
    }

    private var hasMicroLift: Bool {
        !reduceMotion &&
        showActiveDepth &&
        isKeyWindow && isActive && !isDragged
    }

    private var restingShadowOpacity: Double {
        hasMicroLift ? TabChromeHierarchy.activeShadowOpacity(darkMode: colorScheme == .dark) : 0
    }

    private var restingShadowRadius: CGFloat {
        hasMicroLift ? TabChromeHierarchy.activeShadowRadius() : 0
    }

    private var restingShadowYOffset: CGFloat {
        hasMicroLift ? TabChromeHierarchy.activeShadowYOffset() : 0
    }

    private var activeLiftYOffset: CGFloat {
        hasMicroLift ? TabChromeHierarchy.activeLiftYOffset() : 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: contentSpacing) {
                    if showsFavicon {
                        faviconView
                    }
                    titleView
                    if showsSemanticStatusCluster {
                        semanticStatusCluster
                    }
                    if showCloseButton {
                        Color.clear
                            .frame(width: closeButtonSize, height: closeButtonSize)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .frame(height: tabHeight)
                .frame(width: tabWidth)
                .background {
                    if !isDragged {
                        tabSelectionBackground
                    } else {
                        RoundedRectangle(cornerRadius: tabCornerRadius)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    }
                }
                .overlay {
                    if isDragged {
                        RoundedRectangle(cornerRadius: tabCornerRadius)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if showsProgressTrack {
                        progressTrackOverlay
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: tabCornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tab.title)
            .accessibilityValue(tabAccessibilityValue)
            .accessibilityHint("Opens this tab")
            .accessibilityAction(named: Text("Close Tab")) {
                onClose()
            }

            closeButtonView
                .padding(.trailing, horizontalPadding)
        }
        // Apply visual effects for drag
        .scaleEffect(liftScale)
        .shadow(
            color: .black.opacity(isDragged ? 0.18 : restingShadowOpacity),
            radius: isDragged ? liftShadow : restingShadowRadius,
            y: isDragged ? 3 : restingShadowYOffset
        )
        .offset(x: isDragged ? dragOffset : shiftAmount, y: activeLiftYOffset)
        .zIndex(isDragged ? 100 : 0)
        .modifier(
            TabReorderDragModifier(
                minimumDistance: interactionProfile.dragStartDistance,
                onChanged: onDragChanged,
                onEnded: onDragEnded
            )
        )
        .onHover { hovering in
            withAnimation(interactionProfile.hover) {
                isHovered = hovering
            }
            syncCloseButton()
        }
        .onAppear {
            syncCloseButton(animated: false)
        }
        .onChange(of: isActive) { _, _ in
            syncCloseButton()
        }
        .onChange(of: isDragged) { _, _ in
            syncCloseButton()
        }
        .contextMenu {
            ReaderTabContextMenuContent(
                tab: tab,
                lists: lists,
                allLabels: allLabels,
                matchingSavedArticle: matchingSavedArticle,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onClose: onClose
            )
        }
    }

    @ViewBuilder
    private var tabSelectionBackground: some View {
        let darkMode = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)

        if accessibilityPersonalization.reduceTransparency {
            shape
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    if isActive {
                        shape.fill(
                            (isKeyWindow ? Color.accentColor : Color.primary)
                                .opacity(isKeyWindow ? 0.14 : 0.07)
                        )
                    } else {
                        shape.fill(
                            Color.primary.opacity(
                                TabChromeHierarchy.inactiveSurfaceOpacity(
                                    darkMode: darkMode,
                                    isHovered: isHovered
                                )
                            )
                        )
                    }
                }
                .overlay { tabBorder(shape: shape, darkMode: darkMode) }
        } else if #available(macOS 26, *), usesNativeGlass {
            shape
                .fill(.clear)
                .glassEffect(
                    .regular
                        .tint(nativeGlassTint)
                        .interactive(),
                    in: .rect(cornerRadius: tabCornerRadius)
                )
                .overlay { tabBorder(shape: shape, darkMode: darkMode) }
        } else if liquidGlassChrome {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(isActive ? (darkMode ? 0.16 : 0.32) : (darkMode ? 0.08 : 0.20))
                    )
                }
                .overlay {
                    if isActive {
                        shape.fill(
                            Color.accentColor.opacity(isKeyWindow ? (darkMode ? 0.12 : 0.09) : 0.04)
                        )
                    }
                }
                .overlay { tabBorder(shape: shape, darkMode: darkMode) }
        } else {
            shape
                .fill(
                    isActive
                        ? Color(nsColor: .selectedContentBackgroundColor)
                            .opacity(isKeyWindow ? (darkMode ? 0.24 : 0.18) : 0.09)
                        : Color.primary.opacity(
                            TabChromeHierarchy.inactiveSurfaceOpacity(
                                darkMode: darkMode,
                                isHovered: isHovered
                            )
                        )
                )
                .overlay { tabBorder(shape: shape, darkMode: darkMode) }
        }
    }

    private var nativeGlassTint: Color {
        if isActive && isKeyWindow {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.14)
        }
        if isActive {
            return Color.primary.opacity(0.055)
        }
        if isHovered {
            return Color.primary.opacity(0.035)
        }
        return .clear
    }

    private func tabBorder(
        shape: RoundedRectangle,
        darkMode: Bool
    ) -> some View {
        shape.strokeBorder(
            isActive
                ? Color.accentColor.opacity(
                    TabChromeHierarchy.borderOpacity(
                        isActive: true,
                        isHovered: isHovered,
                        isKeyWindow: isKeyWindow,
                        darkMode: darkMode,
                        increasedContrast: increasedContrast
                    )
                )
                : Color(nsColor: .separatorColor).opacity(
                    TabChromeHierarchy.borderOpacity(
                        isActive: false,
                        isHovered: isHovered,
                        isKeyWindow: isKeyWindow,
                        darkMode: darkMode,
                        increasedContrast: increasedContrast
                    )
                ),
            lineWidth: increasedContrast ? 1 : 0.5
        )
    }

    private var faviconView: some View {
        CachedThumbnailImage(url: tab.currentArticle?.thumbnailURL, targetSize: CGSize(width: 16, height: 16)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            AppLoadingThumbnailPlaceholder(
                width: 16,
                height: 16,
                cornerRadius: 3,
                tone: .neutral,
                symbol: "doc.text.fill"
            )
        } failure: {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.tertiary)
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var semanticStatusCluster: some View {
        HStack(spacing: 3) {
            if showsHighlightMarker {
                if accessibilityPersonalization.differentiateWithoutColor {
                    Image(systemName: "highlighter")
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(isKeyWindow ? 0.58 : 0.42))
                } else {
                    Circle()
                        .fill(Color.yellow.opacity(colorScheme == .dark ? 0.78 : 0.70))
                        .frame(width: 4.5, height: 4.5)
                }
            }

            if showsSavedMarker {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.48 : 0.42))
            }

            if showsReadMarker {
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.46 : 0.40))
            }
        }
        .padding(.trailing, 1)
        .opacity(isActive ? 1 : 0.82)
        .accessibilityHidden(true)
    }

    private var progressTrackOverlay: some View {
        GeometryReader { proxy in
            let trackWidth = max(10, proxy.size.width - (horizontalPadding * 2))
            let fillWidth = max(1.5, trackWidth * normalizedProgress)
            let darkMode = colorScheme == .dark

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(
                        Color.primary.opacity(
                            TabChromeHierarchy.progressTrackOpacity(
                                darkMode: darkMode,
                                isActive: isActive
                            )
                        )
                    )

                Capsule(style: .continuous)
                    .fill(
                        Color.primary
                            .opacity(
                                TabChromeHierarchy.progressFillOpacity(
                                    darkMode: darkMode,
                                    isActive: isActive
                                )
                            )
                    )
                    .frame(width: fillWidth)
            }
            .frame(width: trackWidth, height: 1.0, alignment: .leading)
            .offset(x: horizontalPadding, y: -2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .opacity(isKeyWindow ? 1 : 0.62)
        }
    }

    private var titleView: some View {
        Text(tab.title)
            .font(
                .system(
                    size: tabWidth < 95 ? 12 : 12.5,
                    weight: isActive ? .medium : .regular
                )
            )
            .foregroundStyle(titleForegroundStyle)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleForegroundStyle: AnyShapeStyle {
        let darkMode = colorScheme == .dark
        let titleColor = darkMode ? Color.white : Color.black
        let windowActivityScale = isKeyWindow ? 1.0 : 0.72
        if isActive {
            return AnyShapeStyle(
                titleColor.opacity(
                    TabChromeHierarchy.titleActiveOpacity(darkMode: darkMode) * windowActivityScale
                )
            )
        }
        if isHovered {
            return AnyShapeStyle(
                titleColor.opacity(
                    TabChromeHierarchy.titleHoverOpacity(darkMode: darkMode) * windowActivityScale
                )
            )
        }
        return AnyShapeStyle(
            titleColor.opacity(
                TabChromeHierarchy.titleInactiveOpacity(darkMode: darkMode) * windowActivityScale
            )
        )
    }

    @ViewBuilder
    private var closeButtonView: some View {
        if showCloseButton {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: closeGlyphSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: closeButtonSize, height: closeButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Tab")
            .accessibilityHint("Closes \(tab.title)")
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: 0.92))
            )
        }
    }

    private func syncCloseButton(animated: Bool = true) {
        let shouldShow = (isHovered || isActive) && !isDragged
        guard shouldShow != showCloseButton else { return }
        if animated {
            let animation = shouldShow ? interactionProfile.closeButtonShow : interactionProfile.closeButtonHide
            withAnimation(animation) {
                showCloseButton = shouldShow
            }
        } else {
            showCloseButton = shouldShow
        }
    }
}
