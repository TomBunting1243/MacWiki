import SwiftUI

struct InspectorHeaderBar: View {
    @Binding var selection: InspectorMode
    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let horizontalPadding: CGFloat = 10
    }

    var body: some View {
        Picker("Inspector mode", selection: $selection) {
            Text("Info").tag(InspectorMode.info)
            Text("Notes").tag(InspectorMode.notes)
            Text("References").tag(InspectorMode.references)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Inspector mode")
        .padding(.horizontal, Layout.horizontalPadding)
        .frame(height: ColumnChromeMetrics.secondaryBarHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
        }
    }
}
