import Foundation

enum DiscoverStartMode: String, CaseIterable, Identifiable {
    case discoverFeed = "Discover Feed"
    case wikiHop = "Wiki-Hop"
    
    var id: String { rawValue }

    static let storageKey = "discoverStartMode"
}
