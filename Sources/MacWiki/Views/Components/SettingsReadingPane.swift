import SwiftUI
import MacWikiSettingsCatalog

struct SettingsReadingPane: View {
    @AppStorage(ReaderAppearanceStorageKey.fontPreset) private var readerFontPreset: ReaderFontPreset = ReaderAppearance.default.fontPreset
    @AppStorage(ReaderAppearanceStorageKey.fontSize) private var readerFontSize: Double = ReaderAppearance.default.fontSize
    @AppStorage(ReaderAppearanceStorageKey.lineHeight) private var readerLineHeight: Double = ReaderAppearance.default.lineHeight
    @AppStorage(ReaderAppearanceStorageKey.paragraphSpacing) private var readerParagraphSpacing: Double = ReaderAppearance.default.paragraphSpacing
    @AppStorage(ReaderAppearanceStorageKey.contentWidth) private var readerContentWidth: Double = ReaderAppearance.default.contentWidth
    @AppStorage(ReaderAppearanceStorageKey.horizontalPadding) private var readerHorizontalPadding: Double = ReaderAppearance.default.horizontalPadding
    @AppStorage(ReaderAppearanceStorageKey.headingScale) private var readerHeadingScale: Double = ReaderAppearance.default.headingScale
    @AppStorage(AppStorageKey.Reader.linkPreviewImmediateModifier) private var linkPreviewImmediateModifier: ReaderLinkPreviewImmediateModifier = .default

    var body: some View {
        let section = SettingsCatalog.section(.reading)

        SettingsPaneContainer(
            title: section.title,
            summary: section.summary,
            systemImage: section.systemImage
        ) {
            SettingsGroup("Typography", systemImage: "textformat") {
                LabeledContent("Preset") {
                    Menu("Apply Preset") {
                        ForEach(ReaderAppearancePreset.allCases) { preset in
                            Button {
                                applyPreset(preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.rawValue)
                                    Text(preset.summary)
                                        .font(MacWikiTypography.settingsHelp)
                                }
                            }
                        }
                    }
                }

                Picker("Font", selection: $readerFontPreset) {
                    ForEach(ReaderFontPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)

                SettingsSliderRow(
                    title: "Font Size",
                    value: $readerFontSize,
                    range: ReaderAppearance.fontSizeRange,
                    step: 1,
                    valueText: "\(Int(readerFontSize)) pt"
                )

                SettingsSliderRow(
                    title: "Line Height",
                    value: $readerLineHeight,
                    range: ReaderAppearance.lineHeightRange,
                    step: 0.05,
                    valueText: readerLineHeight.formatted(.number.precision(.fractionLength(2)))
                )

                SettingsSliderRow(
                    title: "Paragraph Spacing",
                    value: $readerParagraphSpacing,
                    range: ReaderAppearance.paragraphSpacingRange,
                    step: 1,
                    valueText: "\(Int(readerParagraphSpacing)) px"
                )

                Divider()

                SettingsSliderRow(
                    title: "Content Width",
                    value: $readerContentWidth,
                    range: ReaderAppearance.contentWidthRange,
                    step: 10,
                    valueText: "\(Int(readerContentWidth)) px"
                )

                SettingsSliderRow(
                    title: "Side Margin",
                    value: $readerHorizontalPadding,
                    range: ReaderAppearance.horizontalPaddingRange,
                    step: 2,
                    valueText: "\(Int(readerHorizontalPadding)) px"
                )

                SettingsSliderRow(
                    title: "Heading Scale",
                    value: $readerHeadingScale,
                    range: ReaderAppearance.headingScaleRange,
                    step: 0.01,
                    valueText: "\(readerHeadingScale.formatted(.number.precision(.fractionLength(2))))x"
                )

                HStack {
                    Spacer()
                    Button("Reset Reader Defaults") {
                        resetReaderAppearance()
                    }
                }
            }

            SettingsGroup("Preview", systemImage: "doc.richtext") {
                ReaderTypographyPreviewView(appearance: configuredReaderAppearance)
            }

            SettingsGroup("Link Previews", systemImage: "link") {
                Picker("Immediate Reveal", selection: $linkPreviewImmediateModifier) {
                    ForEach(ReaderLinkPreviewImmediateModifier.allCases) { modifier in
                        Text(modifier.title).tag(modifier)
                    }
                }
                .pickerStyle(.menu)

                SettingsHelpText("Command reveals a linked article preview immediately while preserving Command-click for opening the linked article in a new tab.")
            }
        }
    }

    private var configuredReaderAppearance: ReaderAppearance {
        ReaderAppearance(
            fontPreset: readerFontPreset,
            fontSize: readerFontSize,
            lineHeight: readerLineHeight,
            paragraphSpacing: readerParagraphSpacing,
            contentWidth: readerContentWidth,
            horizontalPadding: readerHorizontalPadding,
            headingScale: readerHeadingScale
        )
    }

    private func resetReaderAppearance() {
        let defaults = ReaderAppearance.default
        readerFontPreset = defaults.fontPreset
        readerFontSize = defaults.fontSize
        readerLineHeight = defaults.lineHeight
        readerParagraphSpacing = defaults.paragraphSpacing
        readerContentWidth = defaults.contentWidth
        readerHorizontalPadding = defaults.horizontalPadding
        readerHeadingScale = defaults.headingScale
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
