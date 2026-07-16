import SwiftUI

struct ReaderTabAccessoryCluster: View {
    @Environment(AppState.self) private var appState
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization

    let showsOverflowMenu: Bool
    let interactionProfile: TabInteractionProfile

    var body: some View {
        trailingAccessoryCluster
    }

    private func performAnimation(_ animation: Animation?, _ updates: () -> Void) {
        if accessibilityPersonalization.reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
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
            Image(systemName: "chevron.down")
                .imageScale(.small)
            .accessibilityLabel("All Tabs")
        }
        .help("All Tabs")
        .accessibilityLabel("All Tabs")
        .accessibilityHint("Shows open tabs")
    }

    private var trailingAccessoryCluster: some View {
        ControlGroup {
            if showsOverflowMenu {
                overflowMenu
            }

            Button("New Tab", systemImage: "plus") {
                performAnimation(interactionProfile.tabCreateClose) {
                    appState.createNewTab()
                }
            }
            .labelStyle(.iconOnly)
            .help("New Tab (⌘T)")
            .accessibilityHint("Creates a new tab")

            Button(
                appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.right"
            ) {
                appState.toggleInspectorVisibility()
            }
            .labelStyle(.iconOnly)
            .help(appState.inspectorVisible ? "Hide Inspector" : "Show Inspector")
            .accessibilityIdentifier("toggle-reader-inspector")
        }
        .controlSize(.regular)
    }
}
