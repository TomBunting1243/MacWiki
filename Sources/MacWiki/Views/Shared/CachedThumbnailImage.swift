import AppKit
import SwiftUI

struct CachedThumbnailImage<Content: View, Placeholder: View, Failure: View>: View {
    private struct LoadRequest: Hashable {
        let url: URL?
        let maxPixelSize: Int
    }

    private enum Phase {
        case idle
        case loading
        case success(Image)
        case failure
    }

    let url: URL?
    let targetSize: CGSize?
    let animatesNetworkSuccess: Bool
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var phase: Phase = .idle

    init(
        url: URL?,
        targetSize: CGSize? = nil,
        animatesNetworkSuccess: Bool = true,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.targetSize = targetSize
        self.animatesNetworkSuccess = animatesNetworkSuccess
        self.content = content
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                placeholder()
            case .success(let image):
                content(image)
            case .failure:
                failure()
            }
        }
        .task(id: loadRequest) {
            await loadCurrentURL()
        }
    }

    private var loadRequest: LoadRequest {
        LoadRequest(url: url, maxPixelSize: maxPixelSize)
    }

    private var maxPixelSize: Int {
        guard let targetSize else { return 0 }
        let maxDimension = max(targetSize.width, targetSize.height)
        guard maxDimension.isFinite, maxDimension > 0 else { return 0 }
        return max(1, Int(ceil(maxDimension * max(displayScale, 1))))
    }

    private func loadCurrentURL() async {
        guard let url else {
            await MainActor.run {
                phase = .failure
            }
            return
        }

        let cacheKey = DecodedThumbnailImageKey(url: url, maxPixelSize: maxPixelSize)
        if let cachedImage = await MainActor.run(body: { DecodedThumbnailImageCache.shared.image(for: cacheKey) }) {
            guard !Task.isCancelled else { return }
            await MainActor.run {
                phase = .success(Image(nsImage: cachedImage))
            }
            return
        }

        await MainActor.run {
            phase = .loading
        }

        let shouldAnimate = animatesNetworkSuccess && !reduceMotion
        guard let result = await ThumbnailImagePipeline.shared.loadImageData(for: url), !Task.isCancelled else {
            return
        }
        let pixelSize = maxPixelSize
        let imageData = result.data
        let decodedImageBox = await Task.detached(priority: .utility) {
            ThumbnailImageDecoder.decode(imageData, maxPixelSize: pixelSize)
        }.value
        guard let decodedImageBox, !Task.isCancelled else {
            if !Task.isCancelled {
                await MainActor.run {
                    phase = .failure
                }
            }
            return
        }

        await MainActor.run {
            let decodedImage = NSImage(
                cgImage: decodedImageBox.cgImage,
                size: NSSize(
                    width: decodedImageBox.cgImage.width,
                    height: decodedImageBox.cgImage.height
                )
            )
            DecodedThumbnailImageCache.shared.store(decodedImage, for: cacheKey)
            let renderedImage = Image(nsImage: decodedImage)
            if shouldAnimate && result.source == .network {
                withAnimation(.easeOut(duration: 0.18)) {
                    phase = .success(renderedImage)
                }
            } else {
                phase = .success(renderedImage)
            }
        }
    }
}
