import Foundation

enum DiscoverSupplementalWork: Hashable, Sendable {
    case cancel
    case load
}

struct DiscoverTodayMostReadLoadPlan: Hashable, Sendable {
    let isExpanded: Bool
    let refreshGeneration: Int

    var work: DiscoverSupplementalWork {
        isExpanded ? .load : .cancel
    }

    var forceRefresh: Bool {
        refreshGeneration > 0
    }
}

struct DiscoverAllTimeMostReadLoadPlan: Hashable, Sendable {
    let showsMostRead: Bool
    let showsLongestReads: Bool
    let requestedLimit: Int
    let refreshGeneration: Int

    var work: DiscoverSupplementalWork {
        showsMostRead || showsLongestReads ? .load : .cancel
    }

    var forceRefresh: Bool {
        refreshGeneration > 0
    }
}

struct DiscoverTrendPulseLoadPlan: Hashable, Sendable {
    enum Scope: String, Hashable, Sendable {
        case todayMostRead
        case allTimeMostRead
    }

    let scope: Scope
    let isExpanded: Bool
    let feedDateKey: String
    let titleFingerprint: Int
    let refreshGeneration: Int

    var work: DiscoverSupplementalWork {
        isExpanded ? .load : .cancel
    }
}

struct DiscoverWordCountLoadPlan: Hashable, Sendable {
    let isExpanded: Bool
    let titleFingerprint: Int
    let refreshGeneration: Int

    var work: DiscoverSupplementalWork {
        isExpanded ? .load : .cancel
    }

    var retriesFailedLoads: Bool {
        refreshGeneration > 0
    }
}

struct DiscoverFeaturedArticleLoadPlan: Hashable, Sendable {
    let title: String?
    let refreshGeneration: Int
}

struct DiscoverTodayMostReadFailureActionPlan: Sendable {
    enum Kind: Hashable, Sendable {
        case tryAgain
    }

    let kind: Kind
    let title: LocalizedStringResource
    let forceRefresh: Bool
}
