import SwiftUI

struct ArticleQuickActionsMenuContent: View {
    let title: String
    var onOpen: (() -> Void)? = nil
    var onOpenInNewTab: (() -> Void)? = nil
    var onShowPageViews: (() -> Void)? = nil

    private var hasPrimaryActions: Bool {
        onOpen != nil || onOpenInNewTab != nil || onShowPageViews != nil
    }

    var body: some View {
        if let onOpen {
            Button(action: onOpen) {
                SwiftUI.Label("Open", systemImage: "doc.text")
            }
        }

        if let onOpenInNewTab {
            Button(action: onOpenInNewTab) {
                SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
            }
        }

        if let onShowPageViews {
            Button(action: onShowPageViews) {
                SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
            }
        }

        if hasPrimaryActions {
            Divider()
        }

        Button {
            ArticleLinkActions.copyTitle(title)
        } label: {
            SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
        }

        Button {
            ArticleLinkActions.copyWikipediaLink(forTitle: title)
        } label: {
            SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
        }
    }
}
