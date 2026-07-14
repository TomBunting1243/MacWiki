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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var searchCoordinator = searchCoordinator

        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search Wikipedia", text: $searchCoordinator.searchText)
                .textFieldStyle(.plain)
                .font(DiscoverTypography.cardBody.weight(.medium))
                .focused($isSearchFocused)
                .onSubmit(onOpenSelectedResult)

            if searchCoordinator.isLoading {
                AppLoadingActivityMark(tone: .accent)
            } else if !searchCoordinator.hasQuery {
                Button(action: onRefreshDiscover) {
                    Group {
                        if discoverFeedStore.isLoading {
                            AppLoadingActivityMark(tone: .accent)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(DiscoverInteractivePressStyle())
                .disabled(discoverFeedStore.isLoading)
                .help(discoverFeedStore.isLoading ? "Refreshing Discover…" : "Refresh Discover")
                .accessibilityLabel("Refresh Discover")
                .accessibilityValue(discoverFeedStore.isLoading ? "Refreshing" : "Ready")
            } else if searchCoordinator.hasInput {
                Button(action: onClearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(DiscoverInteractivePressStyle())
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .discoverSurfaceChrome(
            cornerRadius: 12,
            tintColors: [
                Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.018 : 0.055)
            ],
            borderOpacity: 0.38,
            shadowOpacity: 0.035,
            shadowRadius: 6,
            shadowY: 2
        )
        .onMoveCommand(perform: onMoveSelection)
    }
}
