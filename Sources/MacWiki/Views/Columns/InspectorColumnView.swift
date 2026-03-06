import SwiftUI

struct InspectorColumnView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 240

    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?
    let isExpanded: Bool

    private let expandedMinInspectorWidth: CGFloat = 220
    private let expandedMaxInspectorWidth: CGFloat = 380
    private let collapsedInspectorWidth: CGFloat = 0
    private let inspectorBackgroundOpacity: Double = 0.62

    private var clampedInspectorWidth: CGFloat {
        CGFloat(min(max(inspectorWidth, Double(expandedMinInspectorWidth)), Double(expandedMaxInspectorWidth)))
    }

    private var resolvedMinWidth: CGFloat {
        isExpanded ? expandedMinInspectorWidth : collapsedInspectorWidth
    }

    private var resolvedIdealWidth: CGFloat {
        isExpanded ? clampedInspectorWidth : collapsedInspectorWidth
    }

    private var resolvedMaxWidth: CGFloat {
        isExpanded ? expandedMaxInspectorWidth : collapsedInspectorWidth
    }

    private var glassSheenOpacity: Double {
        colorScheme == .dark ? 0.14 : 0.18
    }

    private var glassTintOpacity: Double {
        colorScheme == .dark ? 0.05 : 0.02
    }

    var body: some View {
        InspectorPanel(
            showNewLabelSheet: $showNewLabelSheet,
            articleForNewLabel: $articleForNewLabel,
            currentArticleTitle: appState.currentArticle?.title
        )
        .frame(
            minWidth: resolvedMinWidth,
            idealWidth: resolvedIdealWidth,
            maxWidth: resolvedMaxWidth,
            alignment: .trailing
        )
        .opacity(isExpanded ? 1 : 0)
        .allowsHitTesting(isExpanded)
        .background {
            SidebarPaneBackground()
                .opacity(inspectorBackgroundOpacity)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(glassSheenOpacity),
                            Color.white.opacity(glassSheenOpacity * 0.45),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)
                }
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(glassTintOpacity)
                }
                .ignoresSafeArea(.container, edges: .bottom)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        persistInspectorWidth(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        persistInspectorWidth(newWidth)
                    }
            }
        }
        .zIndex(30)
        .onAppear {
            inspectorWidth = Double(clampedInspectorWidth)
        }
        .accessibilityHidden(!isExpanded)
    }

    private func persistInspectorWidth(_ width: CGFloat) {
        guard isExpanded else { return }
        guard width.isFinite else { return }
        let clamped = min(max(width, expandedMinInspectorWidth), expandedMaxInspectorWidth)
        if abs(clampedInspectorWidth - clamped) > 0.5 {
            inspectorWidth = Double(clamped)
        }
    }
}
