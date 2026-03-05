import Foundation

/// Top-level non-library sidebar modes.
enum SidebarRootSelection: String, Codable, Hashable {
    case recents = "recents"
    case discover = "discover"
    case wikiHop = "wikiHop"
}
