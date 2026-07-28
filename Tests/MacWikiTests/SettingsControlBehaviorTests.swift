import AppKit
import Foundation
import Testing

@testable import MacWiki

@MainActor
struct SettingsControlBehaviorTests {
    @Test func accessibilityAdjustmentsHonorTheDeclaredSliderStep() {
        let slider = ExactStepSettingsSlider(
            value: 430,
            minValue: 420,
            maxValue: 1_400,
            target: nil,
            action: nil
        )
        slider.accessibilityStep = 10

        #expect(slider.accessibilityPerformIncrement())
        #expect(slider.doubleValue == 440)
        #expect(slider.accessibilityPerformDecrement())
        #expect(slider.doubleValue == 430)
    }

    @Test func accessibilityAdjustmentsStopAtSliderBounds() {
        let slider = ExactStepSettingsSlider(
            value: 30,
            minValue: 13,
            maxValue: 30,
            target: nil,
            action: nil
        )
        slider.accessibilityStep = 1

        #expect(!slider.accessibilityPerformIncrement())
        #expect(slider.doubleValue == 30)
        #expect(slider.accessibilityPerformDecrement())
        #expect(slider.doubleValue == 29)
    }

    @Test func everyReaderAppearanceConsumerUsesTheCanonicalFontDefault() throws {
        for path in [
            "Sources/MacWiki/Views/Reader/ReaderView.swift",
            "Sources/MacWiki/Views/Components/ReaderStylePopover.swift",
            "Sources/MacWiki/Views/Components/SettingsReadingPane.swift"
        ] {
            let source = try repositorySource(path)
            #expect(
                source.contains(
                    "@AppStorage(ReaderAppearanceStorageKey.fontPreset) private var readerFontPreset: ReaderFontPreset = ReaderAppearance.default.fontPreset"
                ),
                "Noncanonical reader font default in \(path)"
            )
        }
    }

    @Test func settingsUseNativeDestructiveSemanticsAndFlexiblePreviewHeight() throws {
        let source = try repositorySource(
            "Sources/MacWiki/Views/Components/SettingsControls.swift"
        )

        #expect(source.contains("button.hasDestructiveAction = isDestructive"))
        #expect(source.contains(".frame(maxWidth: .infinity, minHeight: 152"))
        #expect(!source.contains(".frame(height: 152)"))
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
