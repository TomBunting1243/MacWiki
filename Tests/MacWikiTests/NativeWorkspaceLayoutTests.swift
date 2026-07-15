import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct NativeWorkspaceLayoutTests {
    @Test func nativeVisibilityBindingsRoundTripIndependently() {
        let appState = AppState(persistenceMode: .ephemeral)

        appState.listsSplitViewVisibility = .detailOnly
        #expect(!appState.listsSidebarVisible)
        #expect(appState.directoryColumnVisible)

        appState.directorySplitViewVisibility = .detailOnly
        #expect(!appState.listsSidebarVisible)
        #expect(!appState.directoryColumnVisible)

        appState.listsSplitViewVisibility = .all
        #expect(appState.listsSidebarVisible)
        #expect(!appState.directoryColumnVisible)

        appState.directorySplitViewVisibility = .all
        #expect(appState.listsSidebarVisible)
        #expect(appState.directoryColumnVisible)
    }

    @Test func automaticVisibilityCountsAsAVisibleTwoColumnSidebar() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.setNavigationColumnVisibility(
            listsVisible: false,
            directoryVisible: true
        )

        appState.directorySplitViewVisibility = .automatic

        #expect(!appState.listsSidebarVisible)
        #expect(appState.directoryColumnVisible)
    }

    @Test func columnWidthStorageRejectsInvalidValuesAndClampsExtremes() {
        #expect(MainWindowColumnWidth.clampedStorageValue(.nan, range: MainWindowColumnWidth.sidebarRange) == nil)
        #expect(MainWindowColumnWidth.clampedStorageValue(120, range: MainWindowColumnWidth.sidebarRange) == 176)
        #expect(MainWindowColumnWidth.clampedStorageValue(480, range: MainWindowColumnWidth.directoryRange) == 420)
        #expect(MainWindowColumnWidth.clampedStorageValue(260, range: MainWindowColumnWidth.inspectorRange) == 270)
    }
}
