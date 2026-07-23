import SwiftUI

struct DiscoverVisualContextStrip: View {
    let images: [WikipediaService.VisualContextImage]
    let isCompactLayout: Bool
    var showsSurface: Bool = true
    let onOpenURL: (URL) -> Void
    @State private var selectedImage: WikipediaService.VisualContextImage? = nil

    private var cardWidth: CGFloat {
        isCompactLayout ? 168 : 194
    }

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(DiscoverEditionCopy.visualContextTitle)
                    .font(DiscoverTypography.cardTitle)
                Text(DiscoverEditionCopy.visualContextSubtitle)
                    .font(DiscoverTypography.cardMetadata.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(images) { image in
                        DiscoverVisualContextCard(
                            image: image,
                            onOpen: { selectedImage = image }
                        )
                        .frame(width: cardWidth)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $selectedImage) { image in
            DiscoverMediaViewer(
                title: DiscoverMediaPresentation.displayTitle(for: image.mediaTitle),
                description: image.caption,
                imageURL: image.thumbnailURL,
                filePageURL: image.filePageURL,
                onOpenURL: onOpenURL
            )
        }

        if showsSurface {
            content
                .padding(12)
                .discoverSurfaceChrome(cornerRadius: 14, borderOpacity: 0.32)
        } else {
            content
        }
    }
}

struct DiscoverVisualContextCard: View {
    let image: WikipediaService.VisualContextImage
    let onOpen: () -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var displayTitle: String {
        DiscoverMediaPresentation.displayTitle(for: image.mediaTitle)
    }

    var body: some View {
        Button(action: onOpen) {
            cardContent
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .discoverSurfaceChrome(
            cornerRadius: 12,
            borderOpacity: isHovered ? 0.42 : 0.30
        )
        .discoverHoverEffect(.card, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .accessibilityLabel(displayTitle)
        .accessibilityHint("Open image in MacWiki")
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            CachedThumbnailImage(
                url: image.thumbnailURL,
                targetSize: CGSize(width: 180, height: 108),
                animatesNetworkSuccess: !reduceMotion
            ) { loadedImage in
                loadedImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
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
                .font(DiscoverTypography.cardMetadata.weight(.semibold))
                .lineLimit(2)

            if let caption = image.caption, !caption.isEmpty {
                Text(caption)
                    .font(DiscoverTypography.cardMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiscoverThumbnailSlot: View {
    let thumbnailURL: URL?
    let size: CGFloat
    let cornerRadius: CGFloat
    let imagePadding: CGFloat
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

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
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var emptySlot: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.08))

            Image(systemName: "photo")
                .font(.system(size: max(12, size * 0.26), weight: .regular))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No image available")
    }
}

struct DiscoverFeaturedImageCard: View {
    let image: WikipediaService.DiscoverFeed.FeaturedImage
    var prefersHorizontalLayout: Bool = false
    @Environment(\.openURL) private var openURL
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isImageHovered = false
    @State private var isViewerPresented = false

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .discoverSurfaceChrome(
            cornerRadius: 16,
            material: .regular,
            borderOpacity: 0.34
        )
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
        .sheet(isPresented: $isViewerPresented) {
            if let displayImageURL {
                DiscoverMediaViewer(
                    title: displayTitle,
                    description: displayDescription,
                    imageURL: displayImageURL,
                    filePageURL: image.filePageURL,
                    onOpenURL: { openURL($0) }
                )
            }
        }
    }

    @ViewBuilder
    private var imagePanel: some View {
        let panelHeight: CGFloat = prefersHorizontalLayout ? 352 : 280

        Button {
            isViewerPresented = true
        } label: {
            if let displayImageURL {
                CachedThumbnailImage(
                    url: displayImageURL,
                    targetSize: prefersHorizontalLayout
                        ? CGSize(width: 620, height: panelHeight)
                        : CGSize(width: 980, height: panelHeight),
                    animatesNetworkSuccess: !reduceMotion
                ) { loadedImage in
                    ZStack {
                        Rectangle()
                            .fill(Color.primary.opacity(0.04))
                        loadedImage
                            .resizable()
                            .scaledToFit()
                            .padding(prefersHorizontalLayout ? 12 : 8)
                    }
                } placeholder: {
                    AppLoadingThumbnailPlaceholder(
                        width: prefersHorizontalLayout ? 620 : 980,
                        height: panelHeight,
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
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(displayTitle)
        .accessibilityHint("Open image in MacWiki")
        .discoverHoverEffect(.card, isActive: isImageHovered, reduceMotion: reduceMotion)
        .onHover { isImageHovered = $0 }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: prefersHorizontalLayout ? 10 : 6) {
            if prefersHorizontalLayout {
                Text(DiscoverEditionCopy.commonsSpotlight)
                    .font(DiscoverTypography.editorialKicker)
                    .textCase(.uppercase)
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
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let licenseText {
                    Text(licenseText)
                        .font(DiscoverTypography.controlAuxiliary)
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
