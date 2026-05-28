import SwiftUI

struct MetadataView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let items: [WikipediaService.MetadataItem]
    var onRowBottomsChange: (([CGFloat]) -> Void)? = nil

    private enum MetadataLayout {
        static let markdownParseByteLimit = 8_192
        static let rowAnimation = Animation.easeOut(duration: 0.18)
    }

    private var displayItems: [MetadataDisplayItem] {
        var labelOccurrences: [String: Int] = [:]
        return items.enumerated().map { index, item in
            let occurrence = labelOccurrences[item.label, default: 0]
            labelOccurrences[item.label] = occurrence + 1
            let displayID = occurrence == 0 ? item.label : "\(item.label)#\(occurrence)"

            return MetadataDisplayItem(
                id: displayID,
                sourceIndex: index,
                item: item,
                isLast: index == items.indices.last
            )
        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }
    
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "list.bullet.clipboard",
                    description: Text("No infobox metadata found for this article.")
                )
                .padding(.top, 40)
            } else {
                ForEach(displayItems) { displayItem in
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayItem.item.label)
                                .font(MacWikiTypography.metadataLabel)
                                .foregroundStyle(.secondary)

                            metadataValueText(displayItem.item.value)
                                .font(MacWikiTypography.metadataValue)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .contentTransition(.opacity)
                        }

                        if !displayItem.isLast {
                            Divider()
                                .opacity(0.38)
                                .padding(.top, 12)
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MetadataRowBoundaryPreferenceKey.self,
                                value: [IndexedBoundary(index: displayItem.sourceIndex, value: proxy.frame(in: .named("MetadataRows")).maxY)]
                            )
                        }
                    }
                    .transition(rowTransition)
                }
            }
        }
        .animation(reduceMotion ? nil : MetadataLayout.rowAnimation, value: displayItems.map(\.id))
        .animation(reduceMotion ? nil : MetadataLayout.rowAnimation, value: displayItems.map(\.valueFingerprint))
        .coordinateSpace(name: "MetadataRows")
        .onPreferenceChange(MetadataRowBoundaryPreferenceKey.self) { boundaries in
            guard let onRowBottomsChange else { return }
            let rowBottoms = boundaries
                .sorted { $0.index < $1.index }
                .map(\.value)
                .filter { $0.isFinite && $0 > 0 }
            onRowBottomsChange(rowBottoms)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func metadataValueText(_ value: String) -> Text {
        if value.utf8.count <= MetadataLayout.markdownParseByteLimit,
           let attributed = try? AttributedString(
            markdown: value,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
           ) {
            return Text(attributed)
        }
        return Text(verbatim: value)
    }
}

private struct MetadataDisplayItem: Identifiable {
    let id: String
    let sourceIndex: Int
    let item: WikipediaService.MetadataItem
    let isLast: Bool

    var valueFingerprint: String {
        "\(id)=\(item.value)"
    }
}

private struct IndexedBoundary: Equatable {
    let index: Int
    let value: CGFloat
}

private struct MetadataRowBoundaryPreferenceKey: PreferenceKey {
    static let defaultValue: [IndexedBoundary] = []

    static func reduce(value: inout [IndexedBoundary], nextValue: () -> [IndexedBoundary]) {
        value.append(contentsOf: nextValue())
    }
}

#Preview {
    MetadataView(items: [
        .init(label: "Word count", value: "2,543 words"),
        .init(label: "Last edited", value: "Oct 24, 2025"),
        .init(label: "Born", value: "August 17, 1985 (age 40)\nSacramento, California, U.S."),
        .init(label: "Occupation", value: "Rock climber")
    ])
}
