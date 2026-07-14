import AppKit

extension NSToolbar.Identifier {
    /// Bumped when the four-pane, reader-scoped toolbar replaced the former
    /// SwiftUI toolbar. A new identifier prevents an older saved layout from
    /// restoring without the three structural tracking separators.
    static let macWikiReaderScoped = Self("main-window-reader-scoped-toolbar-v15")
}

extension NSToolbarItem.Identifier {
    static let macWikiSidebarToggle = Self("macwiki.pane.sidebar")
    static let macWikiSidebarDirectoryBoundary = Self("macwiki.boundary.sidebar-directory")
    static let macWikiListContents = Self("macwiki.pane.list-contents")
    static let macWikiSearch = Self("macwiki.search")
    static let macWikiDirectoryReaderBoundary = Self("macwiki.boundary.directory-reader")
    static let macWikiHistory = Self("reader.history")
    static let macWikiArticleState = Self("reader.article-state")
    static let macWikiFind = Self("reader.find")
    static let macWikiStyle = Self("reader.style")
    static let macWikiPageViews = Self("reader.page-views")
    static let macWikiOpenInBrowser = Self("reader.open-in-browser")
    static let macWikiShare = Self("reader.share")
    static let macWikiReaderInspectorBoundary = Self("macwiki.boundary.reader-inspector")
    static let macWikiInspectorToggle = Self("macwiki.pane.inspector")
}

/// The toolbar is one native structure with three fixed pane boundaries. Only
/// controls inside the article-reader zone may be customized by the user.
enum ReaderToolbarLayout {
    static let fixedIdentifiers: Set<NSToolbarItem.Identifier> = [
        .macWikiSidebarToggle,
        .macWikiSidebarDirectoryBoundary,
        .macWikiListContents,
        .macWikiSearch,
        .macWikiDirectoryReaderBoundary,
        .macWikiReaderInspectorBoundary,
        .macWikiInspectorToggle
    ]

    static let readerIdentifiers: Set<NSToolbarItem.Identifier> = [
        .macWikiHistory,
        .macWikiArticleState,
        .macWikiFind,
        .macWikiStyle,
        .macWikiPageViews,
        .macWikiOpenInBrowser,
        .macWikiShare
    ]

    static let defaultIdentifiers: [NSToolbarItem.Identifier] = [
        .macWikiSidebarToggle,
        .macWikiSidebarDirectoryBoundary,
        .macWikiListContents,
        .macWikiSearch,
        .macWikiDirectoryReaderBoundary,
        .macWikiHistory,
        .space,
        .macWikiArticleState,
        .macWikiFind,
        .macWikiStyle,
        .macWikiPageViews,
        .flexibleSpace,
        .macWikiOpenInBrowser,
        .macWikiShare,
        .macWikiReaderInspectorBoundary,
        .macWikiInspectorToggle
    ]

    static let allowedIdentifiers: [NSToolbarItem.Identifier] = [
        .macWikiSidebarToggle,
        .macWikiSidebarDirectoryBoundary,
        .macWikiListContents,
        .macWikiSearch,
        .macWikiDirectoryReaderBoundary,
        .macWikiHistory,
        .macWikiArticleState,
        .macWikiFind,
        .macWikiStyle,
        .macWikiPageViews,
        .macWikiOpenInBrowser,
        .macWikiShare,
        .macWikiReaderInspectorBoundary,
        .macWikiInspectorToggle,
        .space,
        .flexibleSpace
    ]

    /// AppKit overflows lower-priority items first. Pane controls and their
    /// split-view boundaries stay reachable at narrow widths; article
    /// luxuries yield before navigation and document actions.
    static func visibilityPriority(
        for identifier: NSToolbarItem.Identifier
    ) -> NSToolbarItem.VisibilityPriority {
        if fixedIdentifiers.contains(identifier) {
            return .high
        }
        switch identifier {
        case .macWikiStyle, .macWikiPageViews, .macWikiOpenInBrowser, .macWikiShare:
            return .low
        default:
            return .standard
        }
    }

    static func canInsert(
        _ identifier: NSToolbarItem.Identifier,
        at index: Int,
        currentIdentifiers: [NSToolbarItem.Identifier]
    ) -> Bool {
        guard isReaderCustomizable(identifier) else { return false }

        // AppKit asks with NSNotFound when checking whether an existing item
        // may be removed. Reader controls and spaces remain removable.
        guard index != NSNotFound else { return true }
        guard
            let leftBoundary = currentIdentifiers.firstIndex(of: .macWikiDirectoryReaderBoundary),
            let rightBoundary = currentIdentifiers.firstIndex(of: .macWikiReaderInspectorBoundary)
        else {
            return false
        }

        return index > leftBoundary && index <= rightBoundary
    }

    static func isStructurallyValid(
        _ identifiers: [NSToolbarItem.Identifier]
    ) -> Bool {
        let requiredOrder: [NSToolbarItem.Identifier] = [
            .macWikiSidebarToggle,
            .macWikiSidebarDirectoryBoundary,
            .macWikiListContents,
            .macWikiSearch,
            .macWikiDirectoryReaderBoundary,
            .macWikiReaderInspectorBoundary,
            .macWikiInspectorToggle
        ]
        let requiredPositions = requiredOrder.compactMap { identifiers.firstIndex(of: $0) }
        guard requiredPositions.count == requiredOrder.count,
              requiredPositions == requiredPositions.sorted(),
              requiredOrder.allSatisfy({ required in
                  identifiers.filter { $0 == required }.count == 1
              }),
              let leftBoundary = identifiers.firstIndex(of: .macWikiDirectoryReaderBoundary),
              let rightBoundary = identifiers.firstIndex(of: .macWikiReaderInspectorBoundary)
        else {
            return false
        }

        for (index, identifier) in identifiers.enumerated() {
            if fixedIdentifiers.contains(identifier) {
                continue
            }
            guard isReaderCustomizable(identifier),
                  index > leftBoundary,
                  index < rightBoundary else {
                return false
            }
        }
        return true
    }

    private static func isReaderCustomizable(
        _ identifier: NSToolbarItem.Identifier
    ) -> Bool {
        readerIdentifiers.contains(identifier)
            || identifier == .space
            || identifier == .flexibleSpace
    }
}
