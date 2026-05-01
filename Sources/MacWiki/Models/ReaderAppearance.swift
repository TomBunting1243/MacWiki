import Foundation

enum ReaderFontPreset: String, CaseIterable, Codable {
    case system = "System"
    case newYork = "New York"
    case charter = "Charter"
    case iowan = "Iowan Old Style"
    case palatino = "Palatino"

    var cssBodyFontFamily: String {
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"
        case .newYork:
            return "'New York', 'Times New Roman', serif"
        case .charter:
            return "'Charter', 'Bitstream Charter', 'Times New Roman', serif"
        case .iowan:
            return "'Iowan Old Style', 'Palatino Linotype', 'Times New Roman', serif"
        case .palatino:
            return "'Palatino', 'Palatino Linotype', 'Book Antiqua', serif"
        }
    }

    var cssHeadingFontFamily: String {
        switch self {
        case .system:
            return "-apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif"
        case .newYork, .charter, .iowan, .palatino:
            return cssBodyFontFamily
        }
    }
}

struct ReaderAppearance: Equatable {
    var fontPreset: ReaderFontPreset
    var fontSize: Double
    var lineHeight: Double
    var paragraphSpacing: Double
    var contentWidth: Double
    var horizontalPadding: Double
    var headingScale: Double

    static let fontSizeRange: ClosedRange<Double> = 13...30
    static let lineHeightRange: ClosedRange<Double> = 1.2...2.2
    static let paragraphSpacingRange: ClosedRange<Double> = 6...36
    static let contentWidthRange: ClosedRange<Double> = 420...1400
    static let horizontalPaddingRange: ClosedRange<Double> = 12...120
    static let headingScaleRange: ClosedRange<Double> = 0.85...1.3
    static let minimumReadableColumnWidth: Double = 360

    static let `default` = ReaderAppearance(
        fontPreset: .newYork,
        fontSize: 17,
        lineHeight: 1.65,
        paragraphSpacing: 16,
        contentWidth: 860,
        horizontalPadding: 40,
        headingScale: 1.0
    )

    private static let cssLocale = Locale(identifier: "en_US_POSIX")

    var webPayload: [String: String] {
        let cssNumberStyle = FloatingPointFormatStyle<Double>.number
            .locale(Self.cssLocale)
            .precision(.fractionLength(3))

        return [
            "bodyFontFamily": fontPreset.cssBodyFontFamily,
            "headingFontFamily": fontPreset.cssHeadingFontFamily,
            "fontSize": "\(fontSize)px",
            "lineHeight": lineHeight.formatted(cssNumberStyle),
            "paragraphSpacing": "\(paragraphSpacing)px",
            "contentWidth": "\(contentWidth)px",
            "inlinePadding": "\(horizontalPadding)px",
            "headingScale": headingScale.formatted(cssNumberStyle)
        ]
    }

    /// Resolves width/padding for the current viewport so narrow windows stay readable.
    func resolvedForViewportWidth(_ viewportWidth: Double) -> ReaderAppearance {
        guard viewportWidth.isFinite, viewportWidth > 0 else { return self }

        let minimumPadding = max(Self.horizontalPaddingRange.lowerBound, 0)
        let maxPaddingForReadability = max(
            minimumPadding,
            (viewportWidth - Self.minimumReadableColumnWidth) / 2
        )
        let resolvedPadding = min(max(horizontalPadding, minimumPadding), maxPaddingForReadability)
        let availableContentWidth = max(viewportWidth - (resolvedPadding * 2), 0)
        let resolvedContentWidth = min(contentWidth, availableContentWidth)

        return ReaderAppearance(
            fontPreset: fontPreset,
            fontSize: fontSize,
            lineHeight: lineHeight,
            paragraphSpacing: paragraphSpacing,
            contentWidth: resolvedContentWidth,
            horizontalPadding: resolvedPadding,
            headingScale: headingScale
        )
    }
}

enum ReaderAppearancePreset: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case balanced = "Balanced"
    case immersive = "Immersive"

    var id: String { rawValue }

    var appearance: ReaderAppearance {
        switch self {
        case .compact:
            return ReaderAppearance(
                fontPreset: .system,
                fontSize: 15,
                lineHeight: 1.5,
                paragraphSpacing: 12,
                contentWidth: 840,
                horizontalPadding: 28,
                headingScale: 0.95
            )
        case .balanced:
            return .default
        case .immersive:
            return ReaderAppearance(
                fontPreset: .newYork,
                fontSize: 19,
                lineHeight: 1.8,
                paragraphSpacing: 20,
                contentWidth: 980,
                horizontalPadding: 56,
                headingScale: 1.08
            )
        }
    }

    var summary: String {
        switch self {
        case .compact:
            return "Denser layout with tighter spacing."
        case .balanced:
            return "Default profile tuned for mixed reading."
        case .immersive:
            return "Larger typography with generous spacing."
        }
    }
}

enum ReaderAppearanceStorageKey {
    static let fontPreset = "reader.fontPreset"
    static let fontSize = "reader.fontSize"
    static let lineHeight = "reader.lineHeight"
    static let paragraphSpacing = "reader.paragraphSpacing"
    static let contentWidth = "reader.contentWidth"
    static let horizontalPadding = "reader.horizontalPadding"
    static let headingScale = "reader.headingScale"
}
