import AppKit

extension NSToolbarItem.Identifier {
    static let workspaceLists = Self("com.macwiki.workspace.toolbar.lists")
    static let workspaceListsDirectoryBoundary = Self("com.macwiki.workspace.toolbar.boundary.lists-directory")
    static let workspaceDirectory = Self("com.macwiki.workspace.toolbar.directory")
    static let workspaceDirectoryReaderBoundary = Self("com.macwiki.workspace.toolbar.boundary.directory-reader")
    static let workspaceBack = Self("com.macwiki.workspace.toolbar.back")
    static let workspaceForward = Self("com.macwiki.workspace.toolbar.forward")
    static let workspaceSearch = Self("com.macwiki.workspace.toolbar.search")
    static let workspaceSave = Self("com.macwiki.workspace.toolbar.save")
    static let workspaceReadState = Self("com.macwiki.workspace.toolbar.read-state")
    static let workspaceFind = Self("com.macwiki.workspace.toolbar.find")
    static let workspaceReaderStyle = Self("com.macwiki.workspace.toolbar.reader-style")
    static let workspacePageViews = Self("com.macwiki.workspace.toolbar.page-views")
    static let workspaceOpenBrowser = Self("com.macwiki.workspace.toolbar.open-browser")
    static let workspaceShare = Self("com.macwiki.workspace.toolbar.share")
    static let workspaceInspectorModes = Self("com.macwiki.workspace.toolbar.inspector-modes")
}

enum WorkspaceToolbarLayout {
    static let toolbarIdentifier = NSToolbar.Identifier("main-window-native-reader-zones-v17")

    /// Reader commands and the Inspector toggle all precede divider 2. No
    /// Reader-owned item can therefore render over the Inspector plane.
    static let defaultItemIdentifiers: [NSToolbarItem.Identifier] = [
        .workspaceLists,
        .workspaceListsDirectoryBoundary,
        .workspaceDirectory,
        .workspaceDirectoryReaderBoundary,
        .workspaceBack,
        .workspaceForward,
        .workspaceSearch,
        .flexibleSpace,
        .workspaceSave,
        .workspaceReadState,
        .workspaceFind,
        .workspaceReaderStyle,
        .workspacePageViews,
        .workspaceOpenBrowser,
        .workspaceShare,
        .toggleInspector,
        .inspectorTrackingSeparator,
        .workspaceInspectorModes
    ]

    static let readerItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .workspaceBack,
        .workspaceForward,
        .workspaceSearch,
        .workspaceSave,
        .workspaceReadState,
        .workspaceFind,
        .workspaceReaderStyle,
        .workspacePageViews,
        .workspaceOpenBrowser,
        .workspaceShare,
        .toggleInspector
    ]
}
