import AppKit
import SwiftUI

struct InspectorNotesModeView: View {
    let highlights: [InspectorHighlightSnapshot]
    @Binding var showStaleHighlights: Bool
    @Binding var showArchivedHighlights: Bool

    var body: some View {
        if highlights.isEmpty {
            ColumnEmptyStateView(
                title: "No Highlights Yet",
                systemImage: "highlighter",
                description: "Select text in the article to create highlights. Use ⌘H for quick highlighting.",
                style: .quiet
            )
        } else {
            HighlightListView(
                highlights: highlights,
                showStaleHighlights: $showStaleHighlights,
                showArchivedHighlights: $showArchivedHighlights
            )
        }
    }
}

struct InspectorReferencesModeView: View {
    let sections: [ArticleReferenceSection]
    @Binding var selectedReferenceIDs: Set<String>

    var body: some View {
        if sections.isEmpty {
            ColumnEmptyStateView(
                title: "No References Found",
                systemImage: "books.vertical",
                description: "Citations and sources from the article will appear here.",
                style: .quiet
            )
        } else {
            ReferenceListView(
                sections: sections,
                selectedReferenceIds: $selectedReferenceIDs
            )
        }
    }
}

struct HighlightRehydrateToast: Identifiable, Equatable {
    let id = UUID()
    let message: LocalizedStringResource
    let isSuccess: Bool
}

struct HighlightToastView: View {
    let toast: HighlightRehydrateToast
    var showsSpinner: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            if showsSpinner {
                AppLoadingActivityMark(tone: .accent)
            } else {
                Image(systemName: toast.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 12, weight: .semibold))
            }

            Text(toast.message)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08))
        }
        .foregroundStyle(toast.isSuccess ? .green : .orange)
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.12), radius: 8, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(toast.message))
        .onAppear {
            InspectorAccessibilityAnnouncement.post(
                toast.message,
                priority: showsSpinner || toast.isSuccess ? .medium : .high
            )
        }
    }
}

@MainActor
private enum InspectorAccessibilityAnnouncement {
    static func post(
        _ message: LocalizedStringResource,
        priority: NSAccessibilityPriorityLevel
    ) {
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: String(localized: message),
                .priority: priority.rawValue
            ]
        )
    }
}
