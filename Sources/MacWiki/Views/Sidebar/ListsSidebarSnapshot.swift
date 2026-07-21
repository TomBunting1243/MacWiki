import Foundation

enum ListSortOrder: String, CaseIterable {
    case manual = "Manual"
    case name = "Name"
    case createdDate = "Created"
    case updatedDate = "Updated"
    case articleCount = "Articles"
}

@MainActor
struct ListsSidebarSnapshot {
    static let empty = ListsSidebarSnapshot(
        lists: [],
        areas: [],
        labels: [],
        tags: [],
        savedArticles: [],
        highlights: [],
        articleStates: [],
        sortOrder: .updatedDate
    )

    let sortedLists: [ReadingList]
    let rootLevelLists: [ReadingList]
    let rootAreas: [Area]
    let sortedLabels: [Label]
    let sortedTags: [Tag]
    let labelArticleCounts: [UUID: Int]
    let tagArticleCounts: [UUID: Int]
    let areaListCounts: [UUID: Int]
    let areaIndexByID: [UUID: Area]
    let parentAreaByID: [UUID: UUID?]

    private let listsByAreaID: [UUID: [ReadingList]]
    private let childAreasByParentID: [UUID: [Area]]

    init(
        lists: [ReadingList],
        areas: [Area],
        labels: [Label],
        tags: [Tag],
        savedArticles: [SavedArticle],
        highlights: [Highlight],
        articleStates: [ArticleState],
        sortOrder: ListSortOrder
    ) {
        sortedLists = Self.sortLists(lists, by: sortOrder)
        rootLevelLists = sortedLists.filter { $0.areaId == nil }
        listsByAreaID = Dictionary(grouping: sortedLists.compactMap { list in
            guard list.areaId != nil else { return nil }
            return list
        }) { $0.areaId! }

        let sortedAreas = areas.sorted(by: Self.compareAreasForSortOrder)
        rootAreas = sortedAreas.filter { $0.parentId == nil }
        childAreasByParentID = Dictionary(grouping: sortedAreas.compactMap { area in
            guard area.parentId != nil else { return nil }
            return area
        }) { $0.parentId! }

        sortedLabels = labels.sorted(by: Self.compareLabelsForSortOrder)
        sortedTags = tags.sorted(by: Self.compareTagsForSortOrder)
        labelArticleCounts = Self.buildLabelArticleCounts(savedArticles: savedArticles)
        tagArticleCounts = Self.buildTagArticleCounts(
            highlights: highlights,
            articleStates: articleStates
        )
        areaListCounts = Self.buildAreaListCounts(
            areas: areas,
            listsByAreaID: listsByAreaID,
            childAreasByParentID: childAreasByParentID
        )
        areaIndexByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        parentAreaByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0.parentId) })
    }

    func lists(in area: Area) -> [ReadingList] {
        listsByAreaID[area.id] ?? []
    }

    func childAreas(of area: Area) -> [Area] {
        childAreasByParentID[area.id] ?? []
    }

    func totalListCount(in area: Area) -> Int {
        areaListCounts[area.id] ?? 0
    }

    static func compareListsForManualSort(_ lhs: ReadingList, _ rhs: ReadingList) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func compareAreasForSortOrder(_ lhs: Area, _ rhs: Area) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func compareLabelsForSortOrder(_ lhs: Label, _ rhs: Label) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    static func compareTagsForSortOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func sortLists(_ lists: [ReadingList], by sortOrder: ListSortOrder) -> [ReadingList] {
        switch sortOrder {
        case .manual:
            return lists.sorted(by: compareListsForManualSort)
        case .name:
            return lists.sorted(by: compareListsByName)
        case .createdDate:
            return lists.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return compareListsByName($0, $1)
            }
        case .updatedDate:
            return lists.sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return compareListsByName($0, $1)
            }
        case .articleCount:
            return lists.sorted {
                if $0.articles.count != $1.articles.count {
                    return $0.articles.count > $1.articles.count
                }
                return compareListsByName($0, $1)
            }
        }
    }

    private static func compareListsByName(_ lhs: ReadingList, _ rhs: ReadingList) -> Bool {
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame { return comparison == .orderedAscending }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func buildAreaListCounts(
        areas: [Area],
        listsByAreaID: [UUID: [ReadingList]],
        childAreasByParentID: [UUID: [Area]]
    ) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: areas.map { area in
            var visitedAreaIDs: Set<UUID> = []
            var pendingAreaIDs = [area.id]
            var count = 0

            while let areaID = pendingAreaIDs.popLast() {
                guard visitedAreaIDs.insert(areaID).inserted else { continue }
                count += listsByAreaID[areaID]?.count ?? 0
                pendingAreaIDs.append(contentsOf: childAreasByParentID[areaID, default: []].map(\.id))
            }

            return (area.id, count)
        })
    }

    private static func buildLabelArticleCounts(savedArticles: [SavedArticle]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(savedArticles.count)

        for article in savedArticles {
            guard let labelId = article.labelId else { continue }
            counts[labelId, default: 0] += 1
        }

        return counts
    }

    private static func buildTagArticleCounts(
        highlights: [Highlight],
        articleStates: [ArticleState]
    ) -> [UUID: Int] {
        var titlesByTag: [UUID: Set<String>] = [:]
        titlesByTag.reserveCapacity(highlights.count + articleStates.count)

        for highlight in highlights {
            for tag in highlight.tags {
                titlesByTag[tag.id, default: []].insert(highlight.articleTitle)
            }
        }

        for state in articleStates {
            for tag in state.tags {
                titlesByTag[tag.id, default: []].insert(state.articleTitle)
            }
        }

        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(titlesByTag.count)
        for (tagId, titles) in titlesByTag {
            counts[tagId] = titles.count
        }
        return counts
    }
}

@MainActor
func listsSidebarSnapshotFingerprint(
    lists: [ReadingList],
    areas: [Area],
    labels: [Label],
    tags: [Tag],
    savedArticles: [SavedArticle],
    highlights: [Highlight],
    articleStates: [ArticleState],
    sortOrder: ListSortOrder
) -> Int {
    var hasher = Hasher()
    hasher.combine(sortOrder.rawValue)

    for list in lists.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        hasher.combine(list.id)
        hasher.combine(list.name)
        hasher.combine(list.icon)
        hasher.combine(list.areaId)
        hasher.combine(list.sortOrder)
        hasher.combine(list.createdAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(list.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(list.articles.count)
    }

    for area in areas.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        hasher.combine(area.id)
        hasher.combine(area.name)
        hasher.combine(area.icon)
        hasher.combine(area.parentId)
        hasher.combine(area.isExpanded)
        hasher.combine(area.sortOrder)
        hasher.combine(area.createdAt.timeIntervalSinceReferenceDate.bitPattern)
    }

    for label in labels.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        hasher.combine(label.id)
        hasher.combine(label.name)
        hasher.combine(label.colorRaw)
        hasher.combine(label.sortOrder)
        hasher.combine(label.createdAt.timeIntervalSinceReferenceDate.bitPattern)
    }

    for tag in tags.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        hasher.combine(tag.id)
        hasher.combine(tag.name)
        hasher.combine(tag.sortOrder)
        hasher.combine(tag.createdAt.timeIntervalSinceReferenceDate.bitPattern)
    }

    for article in savedArticles.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        hasher.combine(article.id)
        hasher.combine(article.labelId)
    }

    for highlight in highlights.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        hasher.combine(highlight.id)
        hasher.combine(highlight.articleTitle)
        for tag in highlight.tags.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(tag.id)
        }
    }

    for state in articleStates.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
        hasher.combine(state.id)
        hasher.combine(state.articleTitle)
        for tag in state.tags.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            hasher.combine(tag.id)
        }
    }

    return hasher.finalize()
}
