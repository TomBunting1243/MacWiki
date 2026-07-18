import SwiftUI

struct InspectorHeaderBar: View {
    @Binding var selection: InspectorMode
    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let horizontalPadding: CGFloat = 10
    }

    var body: some View {
        inspectorModePicker
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, 2)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .top
            )
            .frame(height: ColumnChromeMetrics.secondaryBarHeight)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                    .frame(height: 0.5)
            }
    }

    @ViewBuilder
    private var inspectorModePicker: some View {
        if #available(macOS 27, *) {
            picker
                .pickerStyle(.tabs)
        } else {
            picker
                .pickerStyle(.segmented)
        }
    }

    private var picker: some View {
        Picker("Inspector mode", selection: $selection) {
            Text("Info").tag(InspectorMode.info)
            Text("Notes").tag(InspectorMode.notes)
            Text("References").tag(InspectorMode.references)
        }
        .labelsHidden()
        .accessibilityLabel("Inspector mode")
    }
}
