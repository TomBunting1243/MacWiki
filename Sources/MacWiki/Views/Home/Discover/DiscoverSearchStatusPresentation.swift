enum DiscoverSearchStatusPresentation: Equatable, Sendable {
    case searching
    case updating(resultCount: Int)
    case unavailable
    case matches(resultCount: Int)

    init(resultCount: Int, isLoading: Bool, hasError: Bool) {
        if isLoading {
            self = resultCount == 0 ? .searching : .updating(resultCount: resultCount)
        } else if hasError && resultCount == 0 {
            self = .unavailable
        } else {
            self = .matches(resultCount: resultCount)
        }
    }

    var subtitle: String {
        switch self {
        case .searching:
            "Searching Wikipedia"
        case .updating(let resultCount):
            "\(resultCount) found · Updating"
        case .unavailable:
            "Search unavailable"
        case .matches(let resultCount):
            "\(resultCount) \(resultCount == 1 ? "match" : "matches")"
        }
    }
}
