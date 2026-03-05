import SwiftUI

struct SearchResultContextMenuContent: View {
    let result: WikipediaService.SearchResult
    let allLists: [ReadingList]
    let onOpen: (Bool) -> Void
    let onSaveToList: (ReadingList) -> Void
    var onShowPageViews: (() -> Void)? = nil

    var body: some View {
        Button {
            onOpen(false)
        } label: {
            SwiftUI.Label("Open", systemImage: "doc.text")
        }

        Button {
            onOpen(true)
        } label: {
            SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
        }

        if let onShowPageViews {
            Button {
                onShowPageViews()
            } label: {
                SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
            }
        }

        if !allLists.isEmpty {
            Divider()

            Menu {
                ForEach(allLists) { list in
                    Button {
                        onSaveToList(list)
                    } label: {
                        SwiftUI.Label(list.name, systemImage: list.icon)
                    }
                }
            } label: {
                SwiftUI.Label("Save to List", systemImage: "bookmark")
            }
        }

        Divider()

        Button {
            _ = SystemBridge.copyText(result.title)
        } label: {
            SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
        }

        Button {
            _ = SystemBridge.copyText(WikipediaURLBuilder.articleURLString(forTitle: result.title))
        } label: {
            SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
        }
    }
}
