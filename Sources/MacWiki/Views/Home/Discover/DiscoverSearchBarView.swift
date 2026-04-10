import Observation
import SwiftUI

struct DiscoverSearchBarView: View {
    let searchCoordinator: SearchCoordinator
    let discoverFeedStore: DiscoverFeedStore
    let onOpenFirstResult: () -> Void
    let onRefreshDiscover: () -> Void
    let onClearSearch: () -> Void

    @FocusState.Binding var isSearchFocused: Bool

    var body: some View {
        @Bindable var searchCoordinator = searchCoordinator

        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search Wikipedia", text: $searchCoordinator.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .focused($isSearchFocused)
                .onSubmit(onOpenFirstResult)

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
            } else if searchCoordinator.hasInput {
                Button(action: onClearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(DiscoverInteractivePressStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4)
    }
}
