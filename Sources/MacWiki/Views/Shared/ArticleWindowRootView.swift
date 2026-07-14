import SwiftData
import SwiftUI

@MainActor
struct ArticleWindowRootView: View {
    let initialArticle: Article
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(AppStorageKey.ArticleWindow.inspectorWidth) private var inspectorWidth = AppStorageKey.ArticleWindow.inspectorWidthDefault
    @State private var appState: AppState
    @State private var showNewLabelSheet = false
    @State private var editingLabel: Label?
    @State private var articleForNewLabel: SavedArticle?
    @State private var showNewTagSheet = false
    @State private var articleForNewTag: Article?
    @State private var showsSavePopover = false
    @State private var showsReaderStylePopover = false
    @State private var showsPageViewsPopover = false

    init(initialArticle: Article) {
        self.initialArticle = initialArticle
        _appState = State(initialValue: AppState(persistenceMode: .ephemeral))
    }

    var body: some View {
        @Bindable var appState = appState

        ReaderView()
            .frame(minWidth: MainWindowLayout.minimumReaderWidth)
            .inspector(isPresented: $appState.inspectorVisible) {
                InspectorColumnView()
                    .inspectorColumnWidth(
                        min: MainWindowColumnWidth.inspectorRange.lowerBound,
                        ideal: CGFloat(inspectorWidth),
                        max: MainWindowColumnWidth.inspectorRange.upperBound
                    )
                    .persistedColumnWidth(
                        key: AppStorageKey.ArticleWindow.inspectorWidth,
                        range: MainWindowColumnWidth.inspectorRange
                    )
            }
            .contentSheets(
                editingLabel: $editingLabel,
                showNewLabelSheet: $showNewLabelSheet,
                articleForNewLabel: $articleForNewLabel,
                showNewTagSheet: $showNewTagSheet,
                articleForNewTag: $articleForNewTag
            )
            .toolbar(removing: .title)
            .toolbar(removing: .sidebarToggle)
            .toolbar(id: ArticleWindowReaderToolbarIdentifier.configuration) {
                ArticleWindowReaderToolbar(
                    appState: appState,
                    modelContext: modelContext,
                    showsSavePopover: $showsSavePopover,
                    showsReaderStylePopover: $showsReaderStylePopover,
                    showsPageViewsPopover: $showsPageViewsPopover
                )
            }
            .focusedSceneValue(\.macWikiCommandAppState, appState)
            .focusedSceneValue(\.macWikiInspectorCommandsAvailable, true)
            .focusedSceneValue(\.macWikiCommandCapabilities, .articleWindow)
            .focusedSceneValue(\.macWikiCommandModelContext, modelContext)
            .environment(appState)
            .background {
                ArticleWindowReaderCommandPresenter(
                    appState: appState,
                    modelContext: modelContext,
                    openURL: openURL,
                    accessibilityPersonalization: accessibilityPersonalization,
                    readerStyleRequestID: appState.readerStylePresentationRequestID,
                    pageViewsRequestID: appState.readerPageViewsPresentationRequestID
                )
                .frame(width: 0, height: 0)
            }
            .task(id: initialArticle) {
                appState.inspectorVisible = true
                appState.openArticle(initialArticle, inNewTab: false)
            }
    }
}
