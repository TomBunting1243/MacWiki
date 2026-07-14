import AppKit

/// Retains the native sharing picker for command-driven presentation. Toolbar
/// share items keep their own AppKit-managed picker; this presenter gives the
/// Article menu an equivalent action even when the toolbar item was removed.
@MainActor
final class ReaderSharePresenter {
    static let shared = ReaderSharePresenter()

    private var picker: NSSharingServicePicker?

    private init() {}

    func show(_ url: URL, in window: NSWindow? = NSApp.keyWindow) {
        guard let contentView = window?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        self.picker = picker

        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.maxY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }
}
