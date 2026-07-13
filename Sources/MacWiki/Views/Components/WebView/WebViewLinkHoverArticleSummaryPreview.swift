import SwiftUI

struct LinkHoverArticleSummaryPreview: View {
    let articleTitle: String
    let fallbackURL: URL
    let previewWidth: CGFloat
    var onPreferredHeightChange: (CGFloat) -> Void = { _ in }

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var descriptionText: String?
    @State private var extractText: String?
    @State private var thumbnailURL: URL?
    @State private var thumbnailPixelSize: CGSize?
    @State private var summaryTitle: String?
    @State private var isLoading = false
    @State private var hasLoaded = false

    private enum PresentationState {
        case loading
        case content
        case unavailable
    }

    private var hasContent: Bool {
        descriptionText != nil || extractText != nil || thumbnailURL != nil
    }

    private var hasTextualSummary: Bool {
        descriptionText != nil || extractText != nil
    }

    private var requestKey: String {
        let normalizedTitle = articleTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        if normalizedTitle.isEmpty {
            return fallbackURL.absoluteString
        }
        return normalizedTitle
    }

    private var previewArtworkTargetSize: CGSize {
        let estimatedWidth = previewWidth - (LinkHoverGlassMetrics.contentInset * 2) - 28
        return CGSize(
            width: max(220, estimatedWidth),
            height: artworkHeight
        )
    }

    private var resolvedArtworkAspectRatio: CGFloat {
        guard let thumbnailPixelSize,
              thumbnailPixelSize.width > 0,
              thumbnailPixelSize.height > 0 else {
            return LinkHoverSummaryPreviewMetrics.defaultArtworkAspectRatio
        }

        let ratio = thumbnailPixelSize.width / thumbnailPixelSize.height
        guard ratio.isFinite, ratio > 0 else {
            return LinkHoverSummaryPreviewMetrics.defaultArtworkAspectRatio
        }
        return min(
            max(ratio, LinkHoverSummaryPreviewMetrics.minimumArtworkAspectRatio),
            LinkHoverSummaryPreviewMetrics.maximumArtworkAspectRatio
        )
    }

    private var artworkHeight: CGFloat {
        let estimatedWidth = max(220, previewWidth - (LinkHoverGlassMetrics.contentInset * 2) - 28)
        let rawHeight = estimatedWidth / resolvedArtworkAspectRatio
        return min(
            max(rawHeight, LinkHoverSummaryPreviewMetrics.minimumArtworkHeight),
            LinkHoverSummaryPreviewMetrics.maximumArtworkHeight
        )
    }

    private var artworkMonogram: String {
        let source = (summaryTitle ?? articleTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = source.first else { return "W" }
        return String(character).uppercased()
    }

    private var presentationState: PresentationState {
        if isLoading {
            return .loading
        }
        if hasContent {
            return .content
        }
        if hasLoaded {
            return .unavailable
        }
        return .loading
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            currentStateView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: presentationState)
        .task(id: requestKey) {
            await loadSummary()
        }
        .onAppear(perform: publishPreferredHeight)
        .onChange(of: previewWidth) { _, _ in
            publishPreferredHeight()
        }
    }

    @ViewBuilder
    private var currentStateView: some View {
        switch presentationState {
        case .loading:
            loadingStateView
                .transition(.opacity)
        case .content:
            contentView
                .transition(.opacity)
        case .unavailable:
            unavailableStateView
                .transition(.opacity)
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewArtwork

            VStack(alignment: .leading, spacing: 10) {
                if let descriptionText {
                    Text(descriptionText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let extractText {
                    Text(extractText)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !hasTextualSummary {
                    Text("A visual preview is available for this link.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 2)
        }
    }

    private var loadingStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            loadingArtwork

            AppLoadingInlineLabel(
                text: "Loading preview...",
                tone: .neutral,
                font: .caption.weight(.medium)
            )

            VStack(alignment: .leading, spacing: 8) {
                AppLoadingSkeletonBar(width: 110, height: 10, cornerRadius: 5, tone: .neutral)
                AppLoadingSkeletonBar(width: nil, height: 12, cornerRadius: 6, tone: .neutral)
                AppLoadingSkeletonBar(width: nil, height: 12, cornerRadius: 6, tone: .neutral)
                AppLoadingSkeletonBar(width: 224, height: 12, cornerRadius: 6, tone: .neutral)
            }
        }
    }

    private var unavailableStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            fallbackArtwork

            Text("Summary unavailable")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("A clean preview was not available for this link right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
    }

    private var previewArtwork: some View {
        Group {
            if let thumbnailURL {
                CachedThumbnailImage(
                    url: thumbnailURL,
                    targetSize: previewArtworkTargetSize
                ) { image in
                    ZStack {
                        artworkBackground
                        image
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(8)
                    }
                } placeholder: {
                    loadingArtwork
                } failure: {
                    fallbackArtwork
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.042), lineWidth: 0.5)
        }
    }

    private var fallbackArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.92 : 0.98),
                    Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.82 : 0.92),
                    Color(nsColor: .underPageBackgroundColor).opacity(colorScheme == .dark ? 0.72 : 0.82)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.022))
                .frame(width: 164, height: 98)
                .rotationEffect(.degrees(-14))
                .blur(radius: 2)
                .offset(x: 56, y: -18)

            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)

                Text(artworkMonogram)
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.68 : 0.52))
            }
            .padding(16)
        }
    }

    private var loadingArtwork: some View {
        ZStack {
            AppLoadingSkeletonBar(
                width: nil,
                height: artworkHeight,
                cornerRadius: 12,
                tone: .neutral
            )

            Image(systemName: "globe.americas.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: artworkHeight)
    }

    private var artworkBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.02 : 0.08),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.06 : 0.015))
            }
    }

    @MainActor
    private func loadSummary() async {
        isLoading = true
        hasLoaded = false
        summaryTitle = nil
        thumbnailURL = nil
        thumbnailPixelSize = nil
        descriptionText = nil
        extractText = nil

        let trimmedTitle = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            isLoading = false
            hasLoaded = true
            return
        }

        do {
            let summary = try await WikipediaService.shared.fetchSummary(trimmedTitle)
            guard !Task.isCancelled else { return }

            summaryTitle = normalize(summary.title)
            let normalizedDescription = normalize(summary.description)
            let normalizedExtract = normalize(summary.extract)
            thumbnailURL = summary.thumbnailURL
            thumbnailPixelSize = summary.thumbnailPixelSize
            descriptionText = normalizedDescription
            extractText = normalizedExtract
        } catch {
            guard !Task.isCancelled else { return }
        }

        isLoading = false
        hasLoaded = true
        publishPreferredHeight()
    }

    private func normalize(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    @MainActor
    private func publishPreferredHeight() {
        guard presentationState == .content else { return }
        onPreferredHeightChange(
            LinkHoverPreviewLayoutMetrics.preferredPaneHeight(
                title: articleTitle,
                previewWidth: previewWidth,
                artworkHeight: artworkHeight,
                descriptionText: descriptionText,
                extractText: extractText,
                hasTextualSummary: hasTextualSummary
            )
        )
    }
}
