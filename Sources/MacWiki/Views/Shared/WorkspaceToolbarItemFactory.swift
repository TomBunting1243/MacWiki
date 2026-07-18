import AppKit

@MainActor
enum WorkspaceToolbarItemFactory {
    static func trackingSeparator(
        identifier: NSToolbarItem.Identifier,
        splitView: NSSplitView,
        dividerIndex: Int
    ) -> NSTrackingSeparatorToolbarItem {
        let item = NSTrackingSeparatorToolbarItem(
            identifier: identifier,
            splitView: splitView,
            dividerIndex: dividerIndex
        )
        item.visibilityPriority = .high
        return item
    }

    static func button(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbol: String,
        target: AnyObject,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )
        item.isBordered = true
        item.style = .plain
        item.target = target
        item.action = action
        return item
    }
}
