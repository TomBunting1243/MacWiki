import SwiftUI

struct ReaderStylePopover: View {
    @AppStorage(ReaderAppearanceStorageKey.fontPreset) private var readerFontPreset: ReaderFontPreset = ReaderAppearance.default.fontPreset
    @AppStorage(ReaderAppearanceStorageKey.fontSize) private var readerFontSize: Double = ReaderAppearance.default.fontSize
    @AppStorage(ReaderAppearanceStorageKey.lineHeight) private var readerLineHeight: Double = ReaderAppearance.default.lineHeight
    @AppStorage(ReaderAppearanceStorageKey.paragraphSpacing) private var readerParagraphSpacing: Double = ReaderAppearance.default.paragraphSpacing
    @AppStorage(ReaderAppearanceStorageKey.contentWidth) private var readerContentWidth: Double = ReaderAppearance.default.contentWidth
    @AppStorage(ReaderAppearanceStorageKey.horizontalPadding) private var readerHorizontalPadding: Double = ReaderAppearance.default.horizontalPadding
    @AppStorage(ReaderAppearanceStorageKey.headingScale) private var readerHeadingScale: Double = ReaderAppearance.default.headingScale

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Text Styles")
                    .font(.headline)
                Spacer()
                Menu {
                    ForEach(ReaderAppearancePreset.allCases) { preset in
                        Button(preset.rawValue) {
                            applyPreset(preset)
                        }
                    }
                } label: {
                    SwiftUI.Label("Apply Preset", systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .help("Apply Preset")
                .accessibilityLabel("Apply Reader Preset")
            }

            Picker("Font", selection: $readerFontPreset) {
                ForEach(ReaderFontPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.menu)

            sliderRow(
                title: "Size",
                value: $readerFontSize,
                range: ReaderAppearance.fontSizeRange,
                step: 1,
                valueText: "\(Int(readerFontSize))"
            )
            sliderRow(
                title: "Line Height",
                value: $readerLineHeight,
                range: ReaderAppearance.lineHeightRange,
                step: 0.05,
                valueText: readerLineHeight.formatted(.number.precision(.fractionLength(2)))
            )
            sliderRow(
                title: "Paragraph Spacing",
                value: $readerParagraphSpacing,
                range: ReaderAppearance.paragraphSpacingRange,
                step: 1,
                valueText: "\(Int(readerParagraphSpacing))"
            )
            sliderRow(
                title: "Content Width",
                value: $readerContentWidth,
                range: ReaderAppearance.contentWidthRange,
                step: 10,
                valueText: "\(Int(readerContentWidth))"
            )
            sliderRow(
                title: "Side Margin",
                value: $readerHorizontalPadding,
                range: ReaderAppearance.horizontalPaddingRange,
                step: 2,
                valueText: "\(Int(readerHorizontalPadding))"
            )
            sliderRow(
                title: "Heading Scale",
                value: $readerHeadingScale,
                range: ReaderAppearance.headingScaleRange,
                step: 0.01,
                valueText: readerHeadingScale.formatted(.number.precision(.fractionLength(2))) + "x"
            )
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(valueText))
        }
    }

    private func applyPreset(_ preset: ReaderAppearancePreset) {
        let appearance = preset.appearance
        readerFontPreset = appearance.fontPreset
        readerFontSize = appearance.fontSize
        readerLineHeight = appearance.lineHeight
        readerParagraphSpacing = appearance.paragraphSpacing
        readerContentWidth = appearance.contentWidth
        readerHorizontalPadding = appearance.horizontalPadding
        readerHeadingScale = appearance.headingScale
    }
}
