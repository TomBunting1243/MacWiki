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
        areaIndexByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
        parentAreaByID = Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0.parentId) })
    }

    func lists(in area: Area) -> [ReadingList] {
        listsByAreaID[area.id] ?? []
    }

    func childAreas(of area: Area) -> [Area] {
        childAreasByParentID[area.id] ?? []
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
            return lists.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .createdDate:
            return lists.sorted { $0.createdAt > $1.createdAt }
        case .updatedDate:
            return lists.sorted { $0.updatedAt > $1.updatedAt }
        case .articleCount:
            return lists.sorted { $0.articles.count > $1.articles.count }
        }
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

    for list in lists {
        hasher.combine(list.id)
        hasher.combine(list.name)
        hasher.combine(list.icon)
        hasher.combine(list.areaId)
        hasher.combine(list.sortOrder)
        hasher.combine(list.createdAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(list.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(list.articles.count)
    }

    for area in areas {
        hasher.combine(area.id)
        hasher.combine(area.name)
        hasher.combine(area.icon)
        hasher.combine(area.parentId)
        hasher.combine(area.isExpanded)
        hasher.combine(area.sortOrder)
        hasher.combine(area.createdAt.timeIntervalSinceReferenceDate.bitPattern)
    }

    for label in labels {
        hasher.combine(label.id)
        hasher.combine(label.name)
        hasher.combine(label.colorRaw)
        hasher.combine(label.sortOrder)
        hasher.combine(label.createdAt.timeIntervalSinceReferenceDate.bitPattern)
    }

    for tag in tags {
        hasher.combine(tag.id)
        hasher.combine(tag.name)
        hasher.combine(tag.sortOrder)
        hasher.combine(tag.createdAt.timeIntervalSinceReferenceDate.bitPattern)
    }

    for article in savedArticles {
        hasher.combine(article.id)
        hasher.combine(article.labelId)
    }

    for highlight in highlights {
        hasher.combine(highlight.id)
        hasher.combine(highlight.articleTitle)
        for tag in highlight.tags {
            hasher.combine(tag.id)
        }
    }

    for state in articleStates {
        hasher.combine(state.id)
        hasher.combine(state.articleTitle)
        for tag in state.tags {
            hasher.combine(tag.id)
        }
    }

    return hasher.finalize()
}
