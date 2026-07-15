import SwiftUI

struct MetadataView: View {
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    let items: [WikipediaService.MetadataItem]

    private enum MetadataLayout {
        static let markdownParseByteLimit = 8_192
        static let rowAnimation = Animation.easeOut(duration: 0.18)
    }

    private var displayItems: [MetadataDisplayItem] {
        var labelOccurrences: [String: Int] = [:]
        return items.map { item in
            let occurrence = labelOccurrences[item.label, default: 0]
            labelOccurrences[item.label] = occurrence + 1
            let displayID = occurrence == 0 ? item.label : "\(item.label)#\(occurrence)"

            return MetadataDisplayItem(
                id: displayID,
                item: item
            )
        }
    }

    private var rowTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }
    
    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "list.bullet.clipboard",
                    description: Text("No infobox metadata found for this article.")
                )
                .padding(.top, 40)
            } else {
                ForEach(displayItems) { displayItem in
                    LabeledContent {
                        metadataValueText(displayItem.item.value)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.opacity)
                    } label: {
                        Text(displayItem.item.label)
                            .foregroundStyle(.secondary)
                    }
                    .transition(rowTransition)
                }
            }
        }
        .animation(reduceMotion ? nil : MetadataLayout.rowAnimation, value: displayItems.map(\.id))
        .animation(reduceMotion ? nil : MetadataLayout.rowAnimation, value: displayItems.map(\.valueFingerprint))
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
    let item: WikipediaService.MetadataItem

    var valueFingerprint: String {
        "\(id)=\(item.value)"
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
