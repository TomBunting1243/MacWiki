import SwiftUI

struct ReferenceSectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(MacWikiTypography.metadataLabel)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}
