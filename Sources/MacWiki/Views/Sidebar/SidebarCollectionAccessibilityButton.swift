import AppKit
import SwiftUI

struct SidebarCollectionAccessibilityButton: NSViewRepresentable {
    let title: String
    let identifier: String
    let isSelected: Bool
    let onPress: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    var onColorChange: ((LabelColor) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.press))
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        configure(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        configure(button, coordinator: context.coordinator)
    }

    private func configure(_ button: NSButton, coordinator: Coordinator) {
        button.title = title
        button.target = coordinator
        button.action = #selector(Coordinator.press)
        button.menu = coordinator.makeMenu()
        button.setAccessibilityLabel(title)
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityValue(isSelected ? "Selected" : "")
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SidebarCollectionAccessibilityButton

        init(parent: SidebarCollectionAccessibilityButton) {
            self.parent = parent
        }

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.addItem(menuItem(title: "Rename", action: #selector(rename)))

            if parent.onColorChange != nil {
                let colorItem = NSMenuItem(title: "Change Color", action: nil, keyEquivalent: "")
                let colorMenu = NSMenu()
                for color in LabelColor.allCases {
                    let item = menuItem(title: color.rawValue, action: #selector(changeColor(_:)))
                    item.representedObject = color.rawValue
                    colorMenu.addItem(item)
                }
                menu.setSubmenu(colorMenu, for: colorItem)
                menu.addItem(colorItem)
            }

            menu.addItem(.separator())
            let deleteItem = menuItem(title: "Delete", action: #selector(deleteCollection))
            deleteItem.isAlternate = false
            menu.addItem(deleteItem)
            return menu
        }

        private func menuItem(title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        @objc func press() {
            parent.onPress()
        }

        @objc private func rename() {
            parent.onRename()
        }

        @objc private func deleteCollection() {
            parent.onDelete()
        }

        @objc private func changeColor(_ sender: NSMenuItem) {
            guard let rawValue = sender.representedObject as? String,
                  let color = LabelColor(rawValue: rawValue) else {
                return
            }
            parent.onColorChange?(color)
        }
    }
}
