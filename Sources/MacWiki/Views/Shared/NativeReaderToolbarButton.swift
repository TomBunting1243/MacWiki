import AppKit
import SwiftUI

/// A standard AppKit toolbar-style action used only where SwiftUI's macOS 27
/// accessibility bridge does not dispatch the button's default action.
struct NativeReaderToolbarButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let isEnabled: Bool
    let action: () -> Void

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
        button.title = title
        button.image = configuredImage()
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .regular
        button.isEnabled = isEnabled
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.toolTip = title
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        button.setAccessibilityLabel(title)
        button.setAccessibilityRole(.button)
    }

    private func configuredImage() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: systemImage, accessibilityDescription: title)?
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
