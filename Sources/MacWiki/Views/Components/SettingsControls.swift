import AppKit
import SwiftUI

struct SettingsPaneContainer<Content: View>: View {
    let title: String
    let summary: String
    let systemImage: String
    private let content: Content

    init(
        title: String,
        summary: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsPaneHeader(
                    title: title,
                    summary: summary,
                    systemImage: systemImage
                )

                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct SettingsPaneHeader: View {
    let title: String
    let summary: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let systemImage: String
    private let content: Content

    init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            SwiftUI.Label(title, systemImage: systemImage)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsHelpText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(MacWikiTypography.settingsHelp)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 12)
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            AccessibleSettingsSlider(
                title: title,
                value: $value,
                range: range,
                step: step,
                valueText: valueText
            )
        }
    }
}

private struct AccessibleSettingsSlider: NSViewRepresentable {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, step: step, range: range)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.altIncrementValue = step
        applyAccessibility(to: slider)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.step = step
        context.coordinator.range = range
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.altIncrementValue = step
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
        applyAccessibility(to: slider)
    }

    private func applyAccessibility(to slider: NSSlider) {
        slider.setAccessibilityTitle(title)
        slider.setAccessibilityLabel(title)
        slider.setAccessibilityValue(valueText)
        slider.setAccessibilityValueDescription(valueText)
    }

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>
        var step: Double
        var range: ClosedRange<Double>

        init(value: Binding<Double>, step: Double, range: ClosedRange<Double>) {
            self.value = value
            self.step = step
            self.range = range
        }

        @objc func valueChanged(_ sender: NSSlider) {
            let steppedValue = (sender.doubleValue / step).rounded() * step
            let clampedValue = min(max(steppedValue, range.lowerBound), range.upperBound)
            value.wrappedValue = clampedValue
            if sender.doubleValue != clampedValue {
                sender.doubleValue = clampedValue
            }
        }
    }
}

struct ReaderTypographyPreviewView: View {
    let appearance: ReaderAppearance

    var body: some View {
        GeometryReader { proxy in
            let viewportWidth = max(Double(proxy.size.width), 1)
            let resolved = appearance.resolvedForViewportWidth(viewportWidth)
            let previewInlinePadding = max(10, min(42, resolved.horizontalPadding * 0.45))
            let availableTextWidth = max(proxy.size.width - (previewInlinePadding * 2), 0)
            let previewColumnWidth = min(
                CGFloat(max(resolved.contentWidth, 0)),
                availableTextWidth
            )

            VStack(alignment: .leading, spacing: max(8, resolved.paragraphSpacing * 0.35)) {
                Text("Article Heading")
                    .font(previewHeadingFont(for: resolved))

                Text("This is a live preview of your reading typography settings for the article renderer.")
                    .font(previewBodyFont(for: resolved))
                    .lineSpacing(previewBodyLineSpacing(for: resolved))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: previewColumnWidth, alignment: .leading)
            .padding(.horizontal, previewInlinePadding)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 152)
    }

    private func previewFont(for preset: ReaderFontPreset, size: Double) -> Font {
        switch preset {
        case .system:
            .system(size: size)
        case .newYork:
            .custom("New York", size: size)
        case .charter:
            .custom("Charter", size: size)
        case .iowan:
            .custom("Iowan Old Style", size: size)
        case .palatino:
            .custom("Palatino", size: size)
        }
    }

    private func previewBodyFont(for appearance: ReaderAppearance) -> Font {
        previewFont(for: appearance.fontPreset, size: appearance.fontSize)
    }

    private func previewHeadingFont(for appearance: ReaderAppearance) -> Font {
        let headingSize = appearance.fontSize * 1.7 * appearance.headingScale
        return previewFont(for: appearance.fontPreset, size: headingSize).weight(.semibold)
    }

    private func previewBodyLineSpacing(for appearance: ReaderAppearance) -> CGFloat {
        max(0, (appearance.lineHeight - 1.0) * appearance.fontSize)
    }
}
