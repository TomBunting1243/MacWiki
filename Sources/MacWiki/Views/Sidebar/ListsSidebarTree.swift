import Foundation

enum ListsSidebarTreeSectionKind: Hashable {
    case explore
    case lists
    case labels
    case tags
}

struct ListsSidebarTreeSection: Identifiable {
    let kind: ListsSidebarTreeSectionKind
    let nodes: [ListsSidebarTreeNode]

    var id: ListsSidebarTreeSectionKind { kind }
}

struct ListsSidebarTreeNode: Identifiable {
    enum Kind {
        case search(isDisabled: Bool)
        case root(SidebarRootSelection)
        case list(ReadingList)
        case label(Label)
        case tag(Tag)
        case area(Area)
    }

    let kind: Kind
    let children: [ListsSidebarTreeNode]

    var id: String {
        switch kind {
        case .search:
            return "search"
        case .root(let selection):
            return "root:\(selection.rawValue)"
        case .list(let list):
            return "list:\(list.id.uuidString)"
        case .label(let label):
            return "label:\(label.id.uuidString)"
        case .tag(let tag):
            return "tag:\(tag.id.uuidString)"
        case .area(let area):
            return "area:\(area.id.uuidString)"
        }
    }
}

@MainActor
enum ListsSidebarTreeBuilder {
    static func build(
        snapshot: ListsSidebarSnapshot,
        isSearchDisabled: Bool,
        isWikiHopAvailable: Bool
    ) -> [ListsSidebarTreeSection] {
        [
            ListsSidebarTreeSection(
                kind: .explore,
                nodes: exploreNodes(
                    isSearchDisabled: isSearchDisabled,
                    isWikiHopAvailable: isWikiHopAvailable
                )
            ),
            ListsSidebarTreeSection(
                kind: .lists,
                nodes: listNodes(snapshot: snapshot)
            ),
            ListsSidebarTreeSection(
                kind: .labels,
                nodes: snapshot.sortedLabels.map { ListsSidebarTreeNode(kind: .label($0), children: []) }
            ),
            ListsSidebarTreeSection(
                kind: .tags,
                nodes: snapshot.sortedTags.map { ListsSidebarTreeNode(kind: .tag($0), children: []) }
            )
        ]
    }

    private static func exploreNodes(
        isSearchDisabled: Bool,
        isWikiHopAvailable: Bool
    ) -> [ListsSidebarTreeNode] {
        var nodes: [ListsSidebarTreeNode] = [
            ListsSidebarTreeNode(kind: .root(.discover), children: []),
            ListsSidebarTreeNode(kind: .search(isDisabled: isSearchDisabled), children: []),
            ListsSidebarTreeNode(kind: .root(.recents), children: [])
        ]

        if isWikiHopAvailable {
            nodes.append(ListsSidebarTreeNode(kind: .root(.wikiHop), children: []))
        }

        return nodes
    }

    private static func listNodes(snapshot: ListsSidebarSnapshot) -> [ListsSidebarTreeNode] {
        let areaNodes = snapshot.rootAreas.map { areaNode(for: $0, snapshot: snapshot) }
        let listNodes = snapshot.rootLevelLists.map { list in
            ListsSidebarTreeNode(kind: .list(list), children: [])
        }
        return areaNodes + listNodes
    }

    private static func areaNode(
        for area: Area,
        snapshot: ListsSidebarSnapshot
    ) -> ListsSidebarTreeNode {
        let childAreaNodes = snapshot.childAreas(of: area).map { areaNode(for: $0, snapshot: snapshot) }
        let childListNodes = snapshot.lists(in: area).map { list in
            ListsSidebarTreeNode(kind: .list(list), children: [])
        }
        return ListsSidebarTreeNode(
            kind: .area(area),
            children: childAreaNodes + childListNodes
        )
    }
}
