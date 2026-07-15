import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct NativeWorkspaceLayoutTests {
    @Test func nativeVisibilityBindingRoundTripsEverySupportedHierarchy() {
        let appState = AppState(persistenceMode: .ephemeral)

        appState.navigationSplitViewVisibility = .doubleColumn
        #expect(appState.workspaceNavigationColumns == .listContentsAndReader)
        #expect(appState.navigationSplitViewVisibility == .doubleColumn)

        appState.navigationSplitViewVisibility = .detailOnly
        #expect(appState.workspaceNavigationColumns == .readerOnly)
        #expect(appState.navigationSplitViewVisibility == .detailOnly)

        appState.navigationSplitViewVisibility = .all
        #expect(appState.workspaceNavigationColumns == .all)
        #expect(appState.navigationSplitViewVisibility == .all)
    }

    @Test func automaticVisibilityDoesNotOverwriteExplicitWorkspaceState() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.setNavigationColumnVisibility(
            listsVisible: false,
            directoryVisible: true
        )

        appState.navigationSplitViewVisibility = .automatic

        #expect(appState.workspaceNavigationColumns == .listContentsAndReader)
    }

    @Test func columnWidthStorageRejectsInvalidValuesAndClampsExtremes() {
        #expect(MainWindowColumnWidth.clampedStorageValue(.nan, range: MainWindowColumnWidth.sidebarRange) == nil)
        #expect(MainWindowColumnWidth.clampedStorageValue(120, range: MainWindowColumnWidth.sidebarRange) == 176)
        #expect(MainWindowColumnWidth.clampedStorageValue(480, range: MainWindowColumnWidth.directoryRange) == 420)
        #expect(MainWindowColumnWidth.clampedStorageValue(260, range: MainWindowColumnWidth.inspectorRange) == 270)
    }
}
