import SwiftData
import SwiftUI

@MainActor
struct ArticleWindowRootView: View {
    let initialArticle: Article
    @Environment(\.modelContext) private var modelContext
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
            .toolbar {
                ArticleWindowReaderToolbar(
                    appState: appState,
                    modelContext: modelContext,
                    showsSavePopover: $showsSavePopover,
                    showsReaderStylePopover: $showsReaderStylePopover,
                    showsPageViewsPopover: $showsPageViewsPopover
                )
            }
            .background {
                FixedWindowToolbarPolicy()
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .focusedSceneValue(\.macWikiCommandAppState, appState)
            .focusedSceneValue(\.macWikiInspectorCommandsAvailable, true)
            .focusedSceneValue(\.macWikiCommandCapabilities, .articleWindow)
            .focusedSceneValue(\.macWikiCommandModelContext, modelContext)
            .environment(appState)
            .onChange(of: appState.currentArticle?.id) { _, _ in
                showsSavePopover = false
                showsReaderStylePopover = false
                showsPageViewsPopover = false
            }
            .onChange(of: appState.readerStylePresentationRequestID) { _, requestID in
                guard requestID != nil, appState.currentArticle != nil else { return }
                showsSavePopover = false
                showsPageViewsPopover = false
                showsReaderStylePopover = true
            }
            .onChange(of: appState.readerPageViewsPresentationRequestID) { _, requestID in
                guard requestID != nil, appState.currentArticle != nil else { return }
                showsSavePopover = false
                showsReaderStylePopover = false
                showsPageViewsPopover = true
            }
            .task(id: initialArticle) {
                appState.inspectorVisible = true
                appState.openArticle(initialArticle, inNewTab: false)
            }
    }
}
