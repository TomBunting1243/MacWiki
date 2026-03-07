import SwiftUI

struct InspectorColumnView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 240

    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?
    let isExpanded: Bool

    private let expandedMinInspectorWidth: CGFloat = 220
    private let expandedMaxInspectorWidth: CGFloat = 380
    private let collapsedInspectorWidth: CGFloat = 0

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
                .ignoresSafeArea(.container, edges: [.top, .bottom])
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
