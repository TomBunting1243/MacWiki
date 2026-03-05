import SwiftUI

struct MetadataView: View {
    let items: [WikipediaService.MetadataItem]
    var onRowBottomsChange: (([CGFloat]) -> Void)? = nil

    private enum MetadataLayout {
        static let markdownParseByteLimit = 8_192
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
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)

                            metadataValueText(item.value)
                                .font(.footnote)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if item.id != items.last?.id {
                            Divider()
                                .opacity(0.38)
                                .padding(.top, 12)
                        }
                    }
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MetadataRowBoundaryPreferenceKey.self,
                                value: [IndexedBoundary(index: index, value: proxy.frame(in: .named("MetadataRows")).maxY)]
                            )
                        }
                    }
                }
            }
        }
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
