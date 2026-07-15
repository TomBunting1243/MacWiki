import AppKit
import SwiftUI

/// AppKit's standard search control, kept inside the List Contents split pane.
/// This preserves native bezel, focus ring, clear action, and text-command
/// behavior without promoting search into the window toolbar.
struct NativeSidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = "Search Wikipedia"
        searchField.controlSize = .small
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = context.coordinator
        searchField.target = context.coordinator
        searchField.action = #selector(Coordinator.searchFieldChanged(_:))
        searchField.identifier = NSUserInterfaceItemIdentifier("sidebar-search-field")
        searchField.setAccessibilityIdentifier("sidebar-search-field")
        searchField.setAccessibilityLabel("Search Wikipedia")
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if searchField.stringValue != text {
            searchField.stringValue = text
        }

        guard isFocused,
              searchField.window?.firstResponder !== searchField.currentEditor() else {
            return
        }
        Task { @MainActor [weak searchField] in
            await Task.yield()
            guard let searchField, isFocused else { return }
            searchField.window?.makeFirstResponder(searchField)
            searchField.selectText(nil)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSidebarSearchField

        init(parent: NativeSidebarSearchField) {
            self.parent = parent
        }

        @objc func searchFieldChanged(_ sender: NSSearchField) {
            publish(sender.stringValue)
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            publish(searchField.stringValue)
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let searchField = control as? NSSearchField else { return false }

            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                if !searchField.stringValue.isEmpty {
                    searchField.stringValue = ""
                    publish("")
                } else {
                    parent.isFocused = false
                    parent.onCancel()
                }
                return true
            default:
                return false
            }
        }

        private func publish(_ value: String) {
            guard parent.text != value else { return }
            parent.text = value
        }
    }
}
