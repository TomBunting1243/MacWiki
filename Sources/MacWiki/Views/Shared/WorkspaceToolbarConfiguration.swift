import SwiftData
import SwiftUI

/// The state that can legitimately change main-window toolbar presentation.
/// Inspector mode updates only the stable native item group's selection;
/// Reader/WebKit projection state remains deliberately absent.
struct WorkspaceToolbarSnapshot: Equatable {
    let articleID: String?
    let articleTitle: String?
    let articleURL: URL?
    let articleIsRead: Bool
    let canGoBack: Bool
    let canGoForward: Bool
    let navigationLocked: Bool
    let listsVisible: Bool
    let directoryVisible: Bool
    let inspectorVisible: Bool
    let readerStyleRequestID: UUID?
    let pageViewsRequestID: UUID?
}

/// A narrow bridge from SwiftUI-owned app state to the AppKit-owned toolbar.
/// The controller reads actions from the live `AppState`; `snapshot` is used
/// only to decide when native item presentation or validation needs refreshing.
@MainActor
struct WorkspaceToolbarConfiguration {
    let appState: AppState
    let modelContext: ModelContext
    let openURL: OpenURLAction
    let snapshot: WorkspaceToolbarSnapshot
    let inspectorMode: InspectorMode

    init(
        appState: AppState,
        modelContext: ModelContext,
        openURL: OpenURLAction
    ) {
        self.appState = appState
        self.modelContext = modelContext
        self.openURL = openURL
        inspectorMode = appState.inspectorMode

        let article = appState.currentArticle
        snapshot = WorkspaceToolbarSnapshot(
            articleID: article?.id,
            articleTitle: article?.title,
            articleURL: article?.url,
            articleIsRead: article?.isRead == true,
            canGoBack: appState.canGoBack,
            canGoForward: appState.canGoForward,
            navigationLocked: appState.isWikiHopNavigationLocked,
            listsVisible: appState.listsSidebarVisible,
            directoryVisible: appState.directoryColumnVisible,
            inspectorVisible: appState.inspectorVisible,
            readerStyleRequestID: appState.readerStylePresentationRequestID,
            pageViewsRequestID: appState.readerPageViewsPresentationRequestID
        )
    }
}
