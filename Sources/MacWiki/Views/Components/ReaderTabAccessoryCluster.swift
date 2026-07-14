import SwiftUI

struct ReaderTabAccessoryCluster: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true

    let showsOverflowMenu: Bool
    let interactionProfile: TabInteractionProfile

    var body: some View {
        trailingAccessoryCluster
    }

    private var stripAccessoryCornerRadius: CGFloat {
        TopChromeControlMetrics.accessoryCornerRadius(compact: true)
    }

    private func performAnimation(_ animation: Animation?, _ updates: () -> Void) {
        if accessibilityPersonalization.reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    @ViewBuilder
    private func stripAccessoryBackground() -> some View {
        let darkMode = colorScheme == .dark
        let cornerRadius = stripAccessoryCornerRadius
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if accessibilityPersonalization.reduceTransparency {
            shape
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    shape.strokeBorder(
                        Color.primary.opacity(
                            accessibilityPersonalization.colorSchemeContrast == .increased ? 0.28 : 0.12
                        ),
                        lineWidth: accessibilityPersonalization.colorSchemeContrast == .increased ? 1 : 0.5
                    )
                }
        } else if #available(macOS 26, *), usesNativeGlassAccessories {
            nativeStripAccessoryBackground(cornerRadius: cornerRadius)
        } else if liquidGlassChrome {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.14 : 0.085))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(darkMode ? 0.052 : 0.044), lineWidth: 0.44)
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.68 : 0.82))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(darkMode ? 0.08 : 0.06), lineWidth: 0.50)
                )
        }
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(appState.openTabs) { tab in
                Button {
                    performAnimation(interactionProfile.tabSelect) {
                        appState.selectTab(tab.id)
                    }
                } label: {
                    SwiftUI.Label {
                        Text(tab.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: appState.activeTabId == tab.id ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        } label: {
            stripAccessoryLabel(
                systemImage: "chevron.down",
                imageScale: .small
            )
            .accessibilityLabel("All Tabs")
        }
        .menuStyle(.borderlessButton)
        .help("All Tabs")
        .accessibilityLabel("All Tabs")
        .accessibilityHint("Shows open tabs")
    }

    private var trailingAccessoryCluster: some View {
        MacWikiGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                if showsOverflowMenu {
                    overflowMenu
                }

                Button {
                    performAnimation(interactionProfile.tabCreateClose) {
                        appState.createNewTab()
                    }
                } label: {
                    stripAccessoryLabel(systemImage: "plus", imageScale: .medium)
                }
                .buttonStyle(.plain)
                .help("New Tab (⌘T)")
                .accessibilityLabel("New Tab")
                .accessibilityHint("Creates a new tab")
            }
        }
    }

    @ViewBuilder
    private func stripAccessoryLabel(systemImage: String, imageScale: Image.Scale) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
            .imageScale(imageScale)
            .foregroundStyle(
                Color.primary.opacity(
                    TabChromeHierarchy.iconPrimaryOpacity(darkMode: colorScheme == .dark)
                )
            )
            .frame(
                width: ChromeIconMetrics.compactButtonSize,
                height: ChromeIconMetrics.compactButtonSize
            )
            .background(stripAccessoryBackground())
            .contentShape(RoundedRectangle(cornerRadius: stripAccessoryCornerRadius, style: .continuous))
    }

    private var usesNativeGlassAccessories: Bool {
        MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
        ) && !accessibilityPersonalization.reduceTransparency
    }

    @available(macOS 26, *)
    private func nativeStripAccessoryBackground(cornerRadius: CGFloat) -> some View {
        let darkMode = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let increasedContrast = accessibilityPersonalization.colorSchemeContrast == .increased

        return shape
            .fill(.thinMaterial)
            .overlay {
                shape
                    .fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(
                                TabChromeHierarchy.nativeAccessoryTintOpacity(
                                    darkMode: darkMode,
                                    compactAccessory: true
                                )
                            )
                    )
            }
            .overlay {
                shape
                    .strokeBorder(
                        Color.primary.opacity(
                            TabChromeHierarchy.nativeAccessoryStrokeOpacity(
                                darkMode: darkMode,
                                compactAccessory: true
                            ) + (increasedContrast ? 0.12 : 0)
                        ),
                        lineWidth: increasedContrast ? 1 : 0.5
                    )
            }
    }
}
