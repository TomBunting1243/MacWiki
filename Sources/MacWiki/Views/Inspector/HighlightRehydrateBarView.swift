import SwiftUI

struct HighlightRehydrateBarView: View {
    let staleCount: Int
    let isRefreshing: Bool
    let onRefreshArticle: () -> Void
    let onArchiveMissing: () -> Void

    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization

    private var surfacePolicy: AppLoadingSurfacePolicy {
        AppLoadingSurfacePolicy(personalization: accessibilityPersonalization)
    }

    private var statusText: String {
        if isRefreshing {
            return "Refreshing article"
        }
        return staleCount == 1 ? "1 stale highlight" : "\(staleCount) stale highlights"
    }

    var body: some View {
        HStack(spacing: 10) {
            if isRefreshing {
                AppLoadingActivityMark(
                    tone: .accent,
                    accessibilityLabel: "Refreshing article highlights"
                )
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button("Refresh") {
                onRefreshArticle()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .disabled(isRefreshing)

            if staleCount > 0 {
                Button("Archive Missing") {
                    onArchiveMissing()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .disabled(isRefreshing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            if surfacePolicy.usesOpaqueBackground {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.02),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .blendMode(.screen)
                    }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(
                        accessibilityPersonalization.colorSchemeContrast == .increased ? 0.28 : 0.12
                    ),
                    lineWidth: surfacePolicy.statusBorderWidth
                )
        }
        .shadow(
            color: .black.opacity(0.18 * surfacePolicy.shadowMultiplier),
            radius: 14,
            y: 6
        )
        .shadow(
            color: .black.opacity(0.08 * surfacePolicy.shadowMultiplier),
            radius: 4,
            y: 2
        )
    }
}
