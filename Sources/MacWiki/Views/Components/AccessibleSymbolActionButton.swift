import AppKit
import SwiftUI

/// A native image-only action for SwiftUI compositions where the macOS
/// accessibility bridge omits the button title or current value.
struct AccessibleSymbolActionButton: NSViewRepresentable {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let tint: NSColor
    let pointSize: CGFloat
    let action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        tint: NSColor = .secondaryLabelColor,
        pointSize: CGFloat = 18,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.tint = tint
        self.pointSize = pointSize
        self.action = action
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            image: configuredImage(),
            target: context.coordinator,
            action: #selector(Coordinator.performAction)
        )
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        configure(button, coordinator: context.coordinator)
    }

    private func configure(_ button: NSButton, coordinator: Coordinator) {
        coordinator.action = action
        button.title = accessibilityLabel
        button.image = configuredImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .accessoryBarAction
        button.contentTintColor = tint
        button.toolTip = accessibilityLabel
        button.setAccessibilityTitle(accessibilityLabel)
        button.setAccessibilityLabel(accessibilityLabel)
        button.setAccessibilityValue(accessibilityValue)
        button.setAccessibilityRole(.button)
    }

    private func configuredImage() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        return NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
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
