import AppKit
import SwiftUI

/// A native unbordered sidebar action used where SwiftUI drops button titles
/// from the macOS accessibility tree inside an otherwise empty `List` section.
struct SidebarEmptyCollectionButton: NSViewRepresentable {
    fileprivate struct Configuration: Equatable {
        let title: String
        let systemImage: String
        let identifier: String
    }

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
        configureBaseAppearance(of: button)
        apply(configuration, to: button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        guard context.coordinator.configuration != configuration else { return }
        apply(configuration, to: button, coordinator: context.coordinator)
    }

    private var configuration: Configuration {
        Configuration(title: title, systemImage: systemImage, identifier: identifier)
    }

    private func configureBaseAppearance(of button: NSButton) {
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.isBordered = false
        button.alignment = .left
        button.controlSize = .small
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityRole(.button)
    }

    private func apply(
        _ configuration: Configuration,
        to button: NSButton,
        coordinator: Coordinator
    ) {
        let previous = coordinator.configuration
        coordinator.action = action

        if previous?.title != configuration.title {
            button.title = configuration.title
            button.setAccessibilityLabel(configuration.title)
        }
        if previous?.systemImage != configuration.systemImage {
            button.image = NSImage(
                systemSymbolName: configuration.systemImage,
                accessibilityDescription: nil
            )
        }
        if previous?.identifier != configuration.identifier {
            button.setAccessibilityIdentifier(configuration.identifier)
        }
        coordinator.configuration = configuration
    }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        fileprivate var configuration: Configuration?

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}
