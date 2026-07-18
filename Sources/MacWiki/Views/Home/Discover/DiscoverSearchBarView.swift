import Observation
import SwiftUI

struct DiscoverSearchBarView: View {
    let searchCoordinator: SearchCoordinator
    let discoverFeedStore: DiscoverFeedStore
    let onOpenSelectedResult: () -> Void
    let onMoveSelection: (MoveCommandDirection) -> Void
    let onRefreshDiscover: () -> Void
    let onClearSearch: () -> Void

    @FocusState.Binding var isSearchFocused: Bool
    var body: some View {
        @Bindable var searchCoordinator = searchCoordinator

        HStack(spacing: 8) {
            TextField("Search Wikipedia", text: $searchCoordinator.searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($isSearchFocused)
                .onSubmit(onOpenSelectedResult)
                .accessibilityLabel("Search Wikipedia")

            if searchCoordinator.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching Discover")
            } else if searchCoordinator.hasInput {
                Button("Clear Search", systemImage: "xmark.circle.fill", action: onClearSearch)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear Search")
                    .help("Clear Search")
            } else if discoverFeedStore.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing Discover")
            } else {
                Button("Refresh Discover", systemImage: "arrow.clockwise", action: onRefreshDiscover)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh Discover")
                    .help("Refresh Discover")
                    .accessibilityValue(discoverFeedStore.isLoading ? "Refreshing" : "Ready")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onMoveCommand(perform: onMoveSelection)
    }
}
