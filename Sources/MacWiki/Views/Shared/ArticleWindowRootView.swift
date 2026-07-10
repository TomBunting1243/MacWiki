import SwiftUI

@MainActor
struct ArticleWindowRootView: View {
    let initialArticle: Article
    @AppStorage(AppStorageKey.ArticleWindow.inspectorWidth) private var inspectorWidth = AppStorageKey.ArticleWindow.inspectorWidthDefault
    @State private var appState: AppState
    @State private var showNewLabelSheet = false
    @State private var editingLabel: Label?
    @State private var articleForNewLabel: SavedArticle?
    @State private var showNewTagSheet = false
    @State private var articleForNewTag: Article?

    init(initialArticle: Article) {
        self.initialArticle = initialArticle
        _appState = State(initialValue: AppState(persistenceMode: .ephemeral))
    }

    var body: some View {
        HSplitView {
            ReaderView()
                .frame(minWidth: 520)

            InspectorColumnView(
                showNewLabelSheet: $showNewLabelSheet,
                articleForNewLabel: $articleForNewLabel
            )
            .frame(
                minWidth: MainWindowColumnWidth.inspectorRange.lowerBound,
                idealWidth: CGFloat(inspectorWidth),
                maxWidth: MainWindowColumnWidth.inspectorRange.upperBound
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
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .configuredMacWikiWindowChrome()
            .focusedSceneValue(\.macWikiCommandAppState, appState)
            .environment(appState)
            .task(id: initialArticle) {
                appState.inspectorVisible = true
                appState.openArticle(initialArticle, inNewTab: false)
            }
    }
}
