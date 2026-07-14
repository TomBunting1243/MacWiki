import SwiftUI

struct SidebarDiscoverFeedPresentation: Equatable, Sendable {
    let hasVisibleFeed: Bool
    let isLoadingSelectedDate: Bool
    let errorMessage: String?

    var showsSelectedDateLoadingStatus: Bool {
        hasVisibleFeed && isLoadingSelectedDate
    }

    var showsRetainedEditionWarning: Bool {
        hasVisibleFeed && errorMessage?.isEmpty == false
    }
}

struct SidebarDiscoverSelectedDateLoadingStatus: View {
    let selectedDate: Date

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 1) {
                Text("Loading selected date")
                    .font(.caption.weight(.medium))

                Text(selectedDate, format: .dateTime.month(.wide).day().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Loading selected date"))
        .accessibilityValue(Text(selectedDate, format: .dateTime.month(.wide).day().year()))
    }
}

struct SidebarDiscoverRetainedEditionWarning: View {
    let editionDateLabel: String
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("You can keep reading the \(editionDateLabel) edition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            SwiftUI.Label("Showing Last Available Edition", systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
        }
        .accessibilityElement(children: .contain)
    }
}
