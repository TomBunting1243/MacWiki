import Foundation
import SwiftUI

struct DiscoverVisualContextStrip: View {
    let images: [WikipediaService.VisualContextImage]
    let isCompactLayout: Bool
    var showsSurface: Bool = true
    let onOpenURL: (URL) -> Void

    private var cardWidth: CGFloat {
        isCompactLayout ? 168 : 194
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("PLACEHOLDER")
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                Text("PLACEHOLDER")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(images) { image in
                        DiscoverVisualContextCard(
                            image: image,
                            onOpenURL: onOpenURL
                        )
                        .frame(width: cardWidth)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }

        if showsSurface {
            content
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                }
        } else {
            content
        }
    }
}

struct DiscoverVisualContextCard: View {
    let image: WikipediaService.VisualContextImage
    let onOpenURL: (URL) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var displayTitle: String {
        var cleaned = image.mediaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
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

    var body: some View {
        Button {
            if let filePageURL = image.filePageURL {
                onOpenURL(filePageURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CachedThumbnailImage(
                    url: image.thumbnailURL,
                    targetSize: CGSize(width: 180, height: 108),
                    animatesNetworkSuccess: !reduceMotion
                ) { loadedImage in
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    AppLoadingThumbnailPlaceholder(
                        width: 180,
                        height: 108,
                        cornerRadius: 10,
                        tone: .accent
                    )
                } failure: {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                }
                .frame(height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(displayTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(2)

                if let caption = image.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .disabled(image.filePageURL == nil)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.13 : 0.05), lineWidth: 0.8)
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.01 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct DiscoverThumbnailSlot: View {
    let thumbnailURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let imagePadding: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let thumbnailURL {
                CachedThumbnailImage(
                    url: thumbnailURL,
                    targetSize: CGSize(width: size, height: size),
                    animatesNetworkSuccess: !reduceMotion
                ) { image in
                    ZStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(imagePadding)
                    }
                } placeholder: {
                    AppLoadingThumbnailPlaceholder(
                        width: size,
                        height: size,
                        cornerRadius: cornerRadius,
                        tone: .accent
                    )
                } failure: {
                    emptySlot
                }
            } else {
                emptySlot
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var emptySlot: some View {
        Color.clear
    }
}

struct DiscoverFeaturedImageCard: View {
    let image: WikipediaService.DiscoverFeed.FeaturedImage
    var prefersHorizontalLayout: Bool = false
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var displayImageURL: URL? {
        image.thumbnailURL ?? image.imageURL
    }

    private var displayTitle: String {
        let rawTitle = image.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTitle.isEmpty else { return "Image of the Day" }

        var cleaned = rawTitle
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

        return cleaned.isEmpty ? rawTitle : cleaned
    }

    private var displayDescription: String? {
        guard let description = image.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty else {
            return nil
        }
        return description
    }

    private var creditsText: String? {
        let pieces = [image.artist, image.credit]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return nil }

        var seen = Set<String>()
        let uniquePieces = pieces.filter { piece in
            let key = piece.lowercased()
            let inserted = seen.insert(key).inserted
            return inserted
        }
        guard !uniquePieces.isEmpty else { return nil }
        return uniquePieces.joined(separator: " \u{00B7} ")
    }

    private var licenseText: String? {
        switch (image.licenseName, image.licenseCode) {
        case let (.some(name), .some(code)):
            return "\(name) (\(code))"
        case let (.some(name), nil):
            return name
        case let (nil, .some(code)):
            return code
        default:
            return nil
        }
    }

    var body: some View {
        Group {
            if prefersHorizontalLayout {
                HStack(alignment: .top, spacing: 16) {
                    imagePanel
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 352, maxHeight: 352)

                    detailsPanel
                        .frame(width: 280, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    imagePanel
                        .frame(maxWidth: .infinity)
                        .frame(height: 280)

                    detailsPanel
                }
            }
        }
        .padding(prefersHorizontalLayout ? 16 : 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.14 : 0.08), lineWidth: 0.8)
        }
        .scaleEffect(reduceMotion ? 1 : (isHovered ? 1.004 : 1))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button {
                _ = SystemBridge.copyText(displayTitle)
            } label: {
                SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
            }

            if let filePageURL = image.filePageURL {
                Button {
                    _ = SystemBridge.copyText(filePageURL.absoluteString)
                } label: {
                    SwiftUI.Label("Copy Commons Link", systemImage: "link")
                }
            }
        }
    }

    @ViewBuilder
    private var imagePanel: some View {
        Group {
            if let displayImageURL {
                CachedThumbnailImage(
                    url: displayImageURL,
                    targetSize: prefersHorizontalLayout
                        ? CGSize(width: 480, height: 352)
                        : CGSize(width: 300, height: 280),
                    animatesNetworkSuccess: !reduceMotion
                ) { loadedImage in
                    ZStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                        loadedImage
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .padding(prefersHorizontalLayout ? 12 : 8)
                    }
                } placeholder: {
                    AppLoadingThumbnailPlaceholder(
                        width: prefersHorizontalLayout ? 480 : 300,
                        height: prefersHorizontalLayout ? 352 : 180,
                        cornerRadius: 12,
                        tone: .accent
                    )
                } failure: {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                }
            } else {
                Rectangle().fill(.quaternary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: prefersHorizontalLayout ? 10 : 6) {
            if prefersHorizontalLayout {
                Text("PLACEHOLDER")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.9)
                    .foregroundStyle(.tertiary)
            }

            Text(displayTitle)
                .font(DiscoverTypography.mediaTitle)
                .lineLimit(prefersHorizontalLayout ? 4 : 3)
                .lineSpacing(1.2)

            if let displayDescription {
                Text(displayDescription)
                    .font(DiscoverTypography.mediaDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(prefersHorizontalLayout ? 4 : 2)
                    .lineSpacing(1.2)
            }

            if let creditsText, !creditsText.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    Text(creditsText)
                        .font(DiscoverTypography.mediaMeta)
                        .foregroundStyle(.secondary)
                        .lineLimit(prefersHorizontalLayout ? 3 : 2)
                }
            }

            HStack(spacing: 8) {
                if let filePageURL = image.filePageURL {
                    Button {
                        openURL(filePageURL)
                    } label: {
                        SwiftUI.Label("View on Commons", systemImage: "arrow.up.right.square")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(DiscoverInteractivePressStyle())
                }

                if let licenseText {
                    Text(licenseText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
                Spacer(minLength: 0)
            }
        }
    }
}
