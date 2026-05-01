import SwiftUI

struct SidebarSearchLoadingRowsView: View {
    var rowCount: Int = 6
    let accessibilityLabel: String

    var body: some View {
        List {
            ForEach(0..<rowCount, id: \.self) { index in
                SidebarSearchLoadingRow(index: index)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SidebarSearchLoadingRow: View {
    let index: Int

    private var titleWidth: CGFloat {
        132 + CGFloat((index % 3) * 24)
    }

    private var descriptionWidth: CGFloat {
        210 - CGFloat((index % 3) * 18)
    }

    private var extractWidth: CGFloat {
        244 - CGFloat((index % 4) * 22)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            SidebarSearchLoadingBar(
                width: 10,
                height: 10,
                cornerRadius: 5
            )
            .padding(.top, 15)
            .padding(.leading, 4)
            .opacity(0.72)

            VStack(alignment: .leading, spacing: 7) {
                SidebarSearchLoadingBar(
                    width: nil,
                    height: 12,
                    cornerRadius: 6
                )
                .frame(maxWidth: titleWidth, alignment: .leading)
                .padding(.top, 5)

                SidebarSearchLoadingBar(
                    width: nil,
                    height: 9,
                    cornerRadius: 5
                )
                .frame(maxWidth: descriptionWidth, alignment: .leading)

                SidebarSearchLoadingBar(
                    width: nil,
                    height: 9,
                    cornerRadius: 5
                )
                .frame(maxWidth: extractWidth, alignment: .leading)

                SidebarSearchLoadingBar(
                    width: 64,
                    height: 7,
                    cornerRadius: 4
                )
                .padding(.top, 5)
                .opacity(0.72)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .accessibilityHidden(true)
    }
}

private struct SidebarSearchLoadingBar: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.065))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
