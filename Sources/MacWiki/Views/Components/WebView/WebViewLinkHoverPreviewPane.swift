import AppKit
import SwiftUI

enum LinkHoverPreviewMetrics {
    static let width: CGFloat = 476
    static let height: CGFloat = 364
}

enum LinkHoverGlassMetrics {
    static let cornerRadius: CGFloat = 20
    static let contentInset: CGFloat = 10
}

enum LinkHoverSummaryPreviewMetrics {
    static let defaultArtworkAspectRatio: CGFloat = 1.6
    static let minimumArtworkAspectRatio: CGFloat = 0.82
    static let maximumArtworkAspectRatio: CGFloat = 1.9
    static let minimumArtworkHeight: CGFloat = 132
    static let maximumArtworkHeight: CGFloat = 176
}

enum LinkHoverPreviewLayoutMetrics {
    static let headerHorizontalInset: CGFloat = 16
    static let headerTopInset: CGFloat = 14
    static let headerBottomInset: CGFloat = 13
    static let bodyHorizontalInset: CGFloat = 16
    static let bodyTopInset: CGFloat = 14
    static let bodyBottomInset: CGFloat = 16
    static let bodySectionSpacing: CGFloat = 12
    static let textBlockSpacing: CGFloat = 10
    static let titleLineLimit = 3
    static let descriptionLineLimit = 3
    static let actionRailEstimatedWidth: CGFloat = 96
    static let titleActionsGap: CGFloat = 20
    static let separatorHeight: CGFloat = 0.5

    static func preferredPaneHeight(
        title: String,
        previewWidth: CGFloat,
        artworkHeight: CGFloat,
        descriptionText: String?,
        extractText: String?,
        hasTextualSummary: Bool
    ) -> CGFloat {
        let headerHeight = estimatedHeaderHeight(title: title, previewWidth: previewWidth)
        let bodyHeight = estimatedBodyHeight(
            previewWidth: previewWidth,
            artworkHeight: artworkHeight,
            descriptionText: descriptionText,
            extractText: extractText,
            hasTextualSummary: hasTextualSummary
        )
        return max(LinkHoverPreviewMetrics.height, headerHeight + bodyHeight + (LinkHoverGlassMetrics.contentInset * 2))
    }

    private static func estimatedHeaderHeight(title: String, previewWidth: CGFloat) -> CGFloat {
        let titleWidth = max(
            160,
            previewWidth -
                (headerHorizontalInset * 2) -
                actionRailEstimatedWidth -
                titleActionsGap
        )
        let titleFont = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize,
            weight: .semibold
        )
        let titleHeight = textHeight(
            title,
            font: titleFont,
            width: titleWidth,
            lineLimit: titleLineLimit
        )

        return headerTopInset +
            titleHeight +
            headerBottomInset +
            separatorHeight
    }

    private static func estimatedBodyHeight(
        previewWidth: CGFloat,
        artworkHeight: CGFloat,
        descriptionText: String?,
        extractText: String?,
        hasTextualSummary: Bool
    ) -> CGFloat {
        let textWidth = max(180, previewWidth - (bodyHorizontalInset * 2))
        let descriptionFont = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .subheadline).pointSize,
            weight: .semibold
        )
        let extractFont = NSFont.preferredFont(forTextStyle: .body)
        let fallbackFont = NSFont.preferredFont(forTextStyle: .callout)

        var textHeightTotal: CGFloat = 0

        if let descriptionText, !descriptionText.isEmpty {
            textHeightTotal += textHeight(
                descriptionText,
                font: descriptionFont,
                width: textWidth,
                lineLimit: descriptionLineLimit
            )
        }

        if let extractText, !extractText.isEmpty {
            if textHeightTotal > 0 {
                textHeightTotal += textBlockSpacing
            }
            textHeightTotal += textHeight(
                extractText,
                font: extractFont,
                width: textWidth,
                lineSpacing: 4
            )
        } else if !hasTextualSummary {
            textHeightTotal += textHeight(
                "A visual preview is available for this link.",
                font: fallbackFont,
                width: textWidth,
                lineSpacing: 2
            )
        }

        return bodyTopInset +
            artworkHeight +
            bodySectionSpacing +
            textHeightTotal +
            bodyBottomInset
    }

    private static func textHeight(
        _ text: String,
        font: NSFont,
        width: CGFloat,
        lineSpacing: CGFloat = 0,
        lineLimit: Int? = nil
    ) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return 0 }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = lineSpacing

        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraphStyle
            ]
        )
        let naturalHeight = ceil(
            attributed.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
        )

        guard let lineLimit else { return naturalHeight }

        let baseLineHeight = ceil(NSLayoutManager().defaultLineHeight(for: font))
        let limitedHeight =
            (baseLineHeight * CGFloat(lineLimit)) +
            (lineSpacing * CGFloat(max(0, lineLimit - 1)))
        return min(naturalHeight, limitedHeight)
    }
}

struct LinkHoverPreviewPane: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false

    let title: String
    let fallbackURL: URL
    let onOpen: () -> Void
    let onOpenInNewTab: () -> Void
    let onOpenInNewWindow: () -> Void
    let onSave: () -> Void
    var previewSize: CGSize = CGSize(width: LinkHoverPreviewMetrics.width, height: LinkHoverPreviewMetrics.height)
    var onPreferredHeightChange: (CGFloat) -> Void = { _ in }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    private var glassPolicy: MacWikiGlassRuntime.SurfacePolicy {
        MacWikiGlassRuntime.surfacePolicy(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback,
            personalization: accessibilityPersonalization
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            LinkHoverArticleSummaryPreview(
                articleTitle: title,
                fallbackURL: fallbackURL,
                previewWidth: previewSize.width,
                onPreferredHeightChange: onPreferredHeightChange
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glassPlane)
        .clipShape(RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous))
        .overlay(glassBorder)
        .shadow(
            color: .black.opacity(
                glassPolicy.allowsDepth
                    ? (isDarkMode ? 0.18 : 0.08)
                    : 0
            ),
            radius: 14,
            y: 6
        )
        .padding(LinkHoverGlassMetrics.contentInset)
        .frame(width: previewSize.width, height: previewSize.height)
        .background(Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
                .layoutPriority(1)

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                LinkHoverActionIcon(
                    systemImage: "arrow.up.forward",
                    helpText: "Open",
                    action: onOpen
                )

                LinkHoverActionIcon(
                    systemImage: "plus.square.on.square",
                    helpText: "Open in New Tab",
                    action: onOpenInNewTab
                )

                LinkHoverActionIcon(
                    systemImage: "macwindow.badge.plus",
                    helpText: "Open in New Window",
                    action: onOpenInNewWindow
                )

                LinkHoverActionIcon(
                    systemImage: "bookmark",
                    helpText: "Save Link",
                    action: onSave
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(actionRailBackground)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(isDarkMode ? 0.08 : 0.04))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var glassPlane: some View {
        let shape = RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
        if glassPolicy.usesOpaqueBackground {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *), glassPolicy.usesNativeGlass {
            shape
                .fill(.clear)
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: LinkHoverGlassMetrics.cornerRadius)
                )
                .overlay {
                    shape.fill(
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(isDarkMode ? 0.022 : 0.014)
                    )
                }
        } else {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(isDarkMode ? 0.11 : 0.074)
                    )
                }
        }
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
            .strokeBorder(
                Color.primary.opacity(
                    accessibilityPersonalization.colorSchemeContrast == .increased
                        ? 0.30
                        : (isDarkMode ? 0.080 : 0.050)
                ),
                lineWidth: accessibilityPersonalization.colorSchemeContrast == .increased ? 1 : 0.55
            )
    }

    private var actionRailBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                Color(
                    nsColor: glassPolicy.usesOpaqueBackground
                        ? .controlBackgroundColor
                        : .windowBackgroundColor
                )
                .opacity(glassPolicy.usesOpaqueBackground ? 1 : (isDarkMode ? 0.10 : 0.052))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isDarkMode ? 0.040 : 0.026),
                        lineWidth: 0.45
                    )
            }
    }
}

private struct LinkHoverActionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    let systemImage: String
    let helpText: String
    let action: () -> Void

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(helpText, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityLabel(helpText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: 28, height: 28)
            .background(iconBackground)
            .onHover { hovering in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }

    private var iconBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(isHovered ? (isDarkMode ? 0.12 : 0.065) : 0)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isHovered
                            ? Color.primary.opacity(isDarkMode ? 0.075 : 0.045)
                            : Color.primary.opacity(isDarkMode ? 0.028 : 0.018),
                        lineWidth: 0.45
                    )
            }
    }
}
