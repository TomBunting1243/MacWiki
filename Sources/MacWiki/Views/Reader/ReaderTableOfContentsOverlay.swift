import SwiftUI

struct ReaderTableOfContentsOverlay: View {
    let items: [ArticleTableOfContentsItem]
    let activeSectionID: String?
    let placement: ReaderTableOfContentsPlacement
    @Binding var isExpanded: Bool
    let onSelect: (String) -> Void

    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    private enum Metrics {
        static let panelWidth: CGFloat = 268
        static let panelHeight: CGFloat = 450
        static let panelCornerRadius: CGFloat = 20
        static let compactSize: CGFloat = 38
        static let compactCornerRadius: CGFloat = 13
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedPanel
                    .transition(panelTransition)
            } else {
                compactControl
                    .transition(panelTransition)
            }
        }
    }

    @ViewBuilder
    private var compactControl: some View {
        if personalization.reduceTransparency {
            compactControlButton
                .background {
                    let shape = compactShape
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                        .overlay { surfaceBorder(shape: shape) }
                }
        } else if #available(macOS 26, *), usesNativeGlass {
            compactControlButton
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.compactCornerRadius))
                .overlay { surfaceBorder(shape: compactShape) }
        } else {
            compactControlButton
                .background {
                    let shape = compactShape
                    shape.fill(.regularMaterial)
                        .overlay { surfaceBorder(shape: shape) }
                }
        }
    }

    private var compactControlButton: some View {
        Button {
            setExpanded(true)
        } label: {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: Metrics.compactSize, height: Metrics.compactSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show article contents")
        .accessibilityValue(placement.rawValue)
        .help("Show Contents")
    }

    @ViewBuilder
    private var expandedPanel: some View {
        if personalization.reduceTransparency {
            expandedPanelContent
                .background {
                    let shape = panelShape
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                        .overlay { surfaceBorder(shape: shape) }
                }
        } else if #available(macOS 26, *), usesNativeGlass {
            expandedPanelContent
                .glassEffect(.regular, in: .rect(cornerRadius: Metrics.panelCornerRadius))
                .overlay { surfaceBorder(shape: panelShape) }
        } else {
            expandedPanelContent
                .background {
                    let shape = panelShape
                    shape.fill(.regularMaterial)
                        .overlay { surfaceBorder(shape: shape) }
                }
        }
    }

    private var expandedPanelContent: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(personalization.colorSchemeContrast == .increased ? 0.8 : 0.48)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(items, id: \.id) { item in
                            row(item)
                                .id(item.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .onChange(of: activeSectionID) { _, newID in
                    guard let newID else { return }
                    withAnimation(personalization.reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
        .frame(width: Metrics.panelWidth, height: Metrics.panelHeight)
        .clipShape(panelShape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Article contents")
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "text.page.badge.magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("On This Page")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(items.count) sections")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Button {
                setExpanded(false)
            } label: {
                Image(systemName: collapseSymbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide article contents")
            .help("Hide Contents")
        }
        .padding(.leading, 14)
        .padding(.trailing, 9)
        .padding(.vertical, 10)
    }

    private func row(_ item: ArticleTableOfContentsItem) -> some View {
        let isActive = activeSectionID == item.id
        let indent = CGFloat(max(item.level - 2, 0)) * 12

        return Button {
            onSelect(item.id)
            setExpanded(false)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Capsule()
                    .fill(isActive ? Color.accentColor : Color.clear)
                    .frame(width: 2.5, height: isActive ? 18 : 8)

                Text(item.title)
                    .font(isActive ? .callout.weight(.semibold) : .callout)
                    .foregroundStyle(isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.leading, indent)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.12 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isActive ? "Current section" : "")
    }

    private var compactShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.compactCornerRadius, style: .continuous)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.panelCornerRadius, style: .continuous)
    }

    private func surfaceBorder(shape: RoundedRectangle) -> some View {
        shape.strokeBorder(
            Color.primary.opacity(
                personalization.colorSchemeContrast == .increased
                    ? 0.30
                    : (colorScheme == .dark ? 0.16 : 0.10)
            ),
            lineWidth: personalization.colorSchemeContrast == .increased ? 1.2 : 0.7
        )
    }

    private var usesNativeGlass: Bool {
        MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
        ) && !personalization.reduceTransparency
    }

    private var collapseSymbolName: String {
        placement == .readerLeading ? "chevron.left" : "chevron.right"
    }

    private var panelTransition: AnyTransition {
        guard !personalization.reduceMotion else { return .opacity }
        let edge: Edge = placement == .readerLeading ? .leading : .trailing
        return .move(edge: edge).combined(with: .opacity)
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(personalization.reduceMotion ? nil : .smooth(duration: 0.22)) {
            isExpanded = expanded
        }
    }
}
