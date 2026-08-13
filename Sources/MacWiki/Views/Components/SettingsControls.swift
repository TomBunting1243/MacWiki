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

struct AccessibleSettingsToggle: NSViewRepresentable {
    let title: String
    @Binding var isOn: Bool
    let identifier: String?

    init(
        _ title: String,
        isOn: Binding<Bool>,
        identifier: String? = nil
    ) {
        self.title = title
        _isOn = isOn
        self.identifier = identifier
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isOn: $isOn)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            checkboxWithTitle: title,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        configure(button, coordinator: context.coordinator)
    }

    func configure(_ button: NSButton, coordinator: Coordinator) {
        coordinator.isOn = $isOn
        button.title = title
        button.allowsMixedState = false
        button.state = isOn ? .on : .off
        if let identifier {
            button.identifier = NSUserInterfaceItemIdentifier(identifier)
        } else {
            button.identifier = nil
        }
        button.setAccessibilityTitle(title)
        button.setAccessibilityLabel(title)
        button.setAccessibilityRole(.checkBox)
    }

    @MainActor
    final class Coordinator: NSObject {
        var isOn: Binding<Bool>

        init(isOn: Binding<Bool>) {
            self.isOn = isOn
        }

        @objc func valueChanged(_ sender: NSButton) {
            isOn.wrappedValue = sender.state == .on
        }
    }
}

struct AccessibleActionButton: NSViewRepresentable {
    let title: String
    let isDestructive: Bool
    let isEnabled: Bool
    let keyEquivalent: String
    let action: () -> Void

    init(
        _ title: String,
        isDestructive: Bool = false,
        isEnabled: Bool = true,
        keyEquivalent: String = "",
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.keyEquivalent = keyEquivalent
        self.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: title,
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        button.bezelStyle = .rounded
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        configure(button, coordinator: context.coordinator)
    }

    func configure(_ button: NSButton, coordinator: Coordinator) {
        coordinator.action = action
        button.title = title
        button.isEnabled = isEnabled
        button.keyEquivalent = keyEquivalent
        button.hasDestructiveAction = isDestructive
        button.setAccessibilityTitle(title)
        button.setAccessibilityLabel(title)
        button.setAccessibilityRole(.button)
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
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

    func makeNSView(context: Context) -> ExactStepSettingsSlider {
        let slider = ExactStepSettingsSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.altIncrementValue = step
        slider.accessibilityStep = step
        applyAccessibility(to: slider)
        return slider
    }

    func updateNSView(_ slider: ExactStepSettingsSlider, context: Context) {
        context.coordinator.value = $value
        context.coordinator.step = step
        context.coordinator.range = range
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.altIncrementValue = step
        slider.accessibilityStep = step
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
        applyAccessibility(to: slider)
    }

    private func applyAccessibility(to slider: NSSlider) {
        slider.setAccessibilityTitle(title)
        slider.setAccessibilityLabel(title)
        slider.setAccessibilityValue(value)
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

/// NSSlider's default accessibility increment is range-relative rather than
/// step-relative. Reader settings expose deliberate units (1 point, 10 pixels,
/// and so on), so Voice Control and accessibility clients must traverse the
/// exact same value grid as pointer and keyboard input.
final class ExactStepSettingsSlider: NSSlider {
    var accessibilityStep = 1.0

    override func accessibilityPerformIncrement() -> Bool {
        performAccessibilityAdjustment(direction: 1)
    }

    override func accessibilityPerformDecrement() -> Bool {
        performAccessibilityAdjustment(direction: -1)
    }

    private func performAccessibilityAdjustment(direction: Double) -> Bool {
        guard accessibilityStep.isFinite, accessibilityStep > 0 else { return false }
        let rawValue = doubleValue + (accessibilityStep * direction)
        let stepIndex = ((rawValue - minValue) / accessibilityStep).rounded()
        let adjustedValue = min(max(minValue + (stepIndex * accessibilityStep), minValue), maxValue)
        guard adjustedValue != doubleValue else { return false }
        doubleValue = adjustedValue
        sendAction(action, to: target)
        return true
    }
}

struct ReaderTypographyPreviewView: View {
    let appearance: ReaderAppearance
    @State private var viewportWidth: CGFloat = 320

    var body: some View {
        let resolved = appearance.resolvedForViewportWidth(max(Double(viewportWidth), 1))
        let previewInlinePadding = max(10, min(42, resolved.horizontalPadding * 0.45))
        let availableTextWidth = max(viewportWidth - (previewInlinePadding * 2), 0)
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
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            guard newWidth.isFinite, newWidth > 0, newWidth != viewportWidth else { return }
            viewportWidth = newWidth
        }
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
