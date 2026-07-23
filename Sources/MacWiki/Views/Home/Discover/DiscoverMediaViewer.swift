import Foundation
import SwiftUI

enum DiscoverMediaPresentation {
    static func displayTitle(for rawTitle: String) -> String {
        var cleaned = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("file:") {
            cleaned = String(cleaned.dropFirst("file:".count))
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        cleaned = cleaned.replacingOccurrences(
            of: #"\.(jpe?g|png|gif|webp|tiff?|svg)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Media image" : cleaned
    }
}

struct DiscoverMediaViewer: View {
    let title: String
    let description: String?
    let imageURL: URL
    let filePageURL: URL?
    let onOpenURL: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Visual Context")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                    .help("Close image viewer")
            }

            CachedThumbnailImage(
                url: imageURL,
                targetSize: CGSize(width: 1_280, height: 820),
                animatesNetworkSuccess: !reduceMotion
            ) { image in
                ZStack {
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor))
                    image
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                }
            } placeholder: {
                AppLoadingThumbnailPlaceholder(
                    width: 960,
                    height: 560,
                    cornerRadius: 12,
                    tone: .accent
                )
            } failure: {
                ContentUnavailableView(
                    "Image Unavailable",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("MacWiki could not load this image.")
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let description,
                   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 12)

                if let filePageURL {
                    Button("Open Commons in Browser", systemImage: "safari") {
                        onOpenURL(filePageURL)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 920, minHeight: 520, idealHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }
}
