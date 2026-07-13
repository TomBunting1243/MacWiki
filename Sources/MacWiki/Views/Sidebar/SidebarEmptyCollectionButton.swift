import AppKit
import SwiftUI

/// A native unbordered sidebar action used where SwiftUI drops button titles
/// from the macOS accessibility tree inside an otherwise empty `List` section.
struct SidebarEmptyCollectionButton: NSViewRepresentable {
    let title: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        let button = NSButton(
            title: title,
            image: image ?? NSImage(),
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
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.alignment = .left
        button.controlSize = .small
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityLabel(title)
        button.setAccessibilityRole(.button)
        button.setAccessibilityIdentifier(identifier)
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
