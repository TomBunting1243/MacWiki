import AppKit
import Observation
import SwiftUI

/// A stable SwiftUI-to-AppKit bridge for the main window's four native panes.
/// SwiftUI owns pane content and application state; AppKit owns the semantic
/// split items, dividers, collapse interactions, and point-based sizing.
struct NativeWorkspaceSplitView<Sidebar: View, Directory: View, Reader: View, Inspector: View, ReaderTopAccessory: View>:
    NSViewControllerRepresentable
{
    @Binding var sidebarVisible: Bool
    @Binding var directoryVisible: Bool
    @Binding var inspectorVisible: Bool

    let reduceMotion: Bool
    let initialSidebarWidth: CGFloat
    let initialDirectoryWidth: CGFloat
    let initialInspectorWidth: CGFloat
    let sidebarRevision: String
    let directoryRevision: String
    let readerRevision: String
    let inspectorRevision: String
    let readerChromeVisible: Bool
    let sidebar: Sidebar
    let directory: Directory
    let reader: Reader
    let inspector: Inspector
    let readerTopAccessory: ReaderTopAccessory

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sidebarVisible: $sidebarVisible,
            directoryVisible: $directoryVisible,
            inspectorVisible: $inspectorVisible,
            sidebar: sidebar,
            directory: directory,
            reader: reader,
            inspector: inspector,
            readerTopAccessory: readerTopAccessory,
            sidebarRevision: sidebarRevision,
            directoryRevision: directoryRevision,
            readerRevision: readerRevision,
            inspectorRevision: inspectorRevision
        )
    }

    func makeNSViewController(context: Context) -> WorkspaceSplitViewController {
        let controller = WorkspaceSplitViewController(
            sidebarController: context.coordinator.sidebarController,
            directoryController: context.coordinator.directoryController,
            readerController: context.coordinator.readerController,
            inspectorController: context.coordinator.inspectorController,
            initialSidebarWidth: initialSidebarWidth,
            initialDirectoryWidth: initialDirectoryWidth,
            initialInspectorWidth: initialInspectorWidth
        )
        controller.onPaneVisibilityChange = { [weak coordinator = context.coordinator] visibility in
            coordinator?.receiveNativeVisibility(visibility)
        }
        controller.setReaderTopAccessoryViewControllers([
            context.coordinator.readerTopAccessoryController
        ])
        controller.setReaderTopAccessoryVisible(readerChromeVisible, animated: false)
        controller.setPaneVisibility(
            sidebarVisible: sidebarVisible,
            directoryVisible: directoryVisible,
            inspectorVisible: inspectorVisible,
            animated: false
        )
        return controller
    }

    func updateNSViewController(_ controller: WorkspaceSplitViewController, context: Context) {
        context.coordinator.updateReaderChromeVisibility(
            readerChromeVisible,
            controller: controller,
            animated: !reduceMotion
        )
        context.coordinator.updateBindings(
            sidebarVisible: $sidebarVisible,
            directoryVisible: $directoryVisible,
            inspectorVisible: $inspectorVisible
        )
        context.coordinator.updateWorkspace(
            sidebar: sidebar,
            directory: directory,
            reader: reader,
            inspector: inspector,
            readerTopAccessory: readerTopAccessory,
            sidebarRevision: sidebarRevision,
            directoryRevision: directoryRevision,
            readerRevision: readerRevision,
            inspectorRevision: inspectorRevision,
            controller: controller,
            visibility: WorkspacePaneVisibility(
                sidebarVisible: sidebarVisible,
                directoryVisible: directoryVisible,
                inspectorVisible: inspectorVisible
            ),
            animated: !reduceMotion
        )
    }

    static func dismantleNSViewController(
        _ controller: WorkspaceSplitViewController,
        coordinator: Coordinator
    ) {
        controller.setReaderTopAccessoryViewControllers([])
    }

    @MainActor
    final class Coordinator {
        fileprivate let sidebarBox: HostingContentBox<Sidebar>
        fileprivate let directoryBox: HostingContentBox<Directory>
        fileprivate let readerBox: HostingContentBox<Reader>
        fileprivate let inspectorBox: HostingContentBox<Inspector>
        fileprivate let readerTopAccessoryBox: HostingContentBox<ReaderTopAccessory>
        fileprivate let sidebarController: NSHostingController<HostingContentRoot<Sidebar>>
        fileprivate let directoryController: NSHostingController<HostingContentRoot<Directory>>
        fileprivate let readerController: NSHostingController<HostingContentRoot<Reader>>
        fileprivate let inspectorController: NSHostingController<HostingContentRoot<Inspector>>
        fileprivate let readerTopAccessoryHostingController: NSHostingController<HostingContentRoot<ReaderTopAccessory>>
        fileprivate let readerTopAccessoryController: NSSplitViewItemAccessoryViewController

        private var sidebarVisibility: Binding<Bool>
        private var directoryVisibility: Binding<Bool>
        private var inspectorVisibility: Binding<Bool>
        private var paneVisibilityUpdate: Task<Void, Never>?
        private var hostedContentUpdate: Task<Void, Never>?
        private var nativeVisibilityUpdate: Task<Void, Never>?
        private var readerChromeVisibilityUpdate: Task<Void, Never>?
        private var lastSidebarRevision: String
        private var lastDirectoryRevision: String
        private var lastReaderRevision: String
        private var lastInspectorRevision: String
        private var lastRequestedVisibility: WorkspacePaneVisibility

        init(
            sidebarVisible: Binding<Bool>,
            directoryVisible: Binding<Bool>,
            inspectorVisible: Binding<Bool>,
            sidebar: Sidebar,
            directory: Directory,
            reader: Reader,
            inspector: Inspector,
            readerTopAccessory: ReaderTopAccessory,
            sidebarRevision: String,
            directoryRevision: String,
            readerRevision: String,
            inspectorRevision: String
        ) {
            sidebarVisibility = sidebarVisible
            directoryVisibility = directoryVisible
            inspectorVisibility = inspectorVisible

            let sidebarBox = HostingContentBox(content: sidebar)
            let directoryBox = HostingContentBox(content: directory)
            let readerBox = HostingContentBox(content: reader)
            let inspectorBox = HostingContentBox(content: inspector)
            let readerTopAccessoryBox = HostingContentBox(content: readerTopAccessory)
            self.sidebarBox = sidebarBox
            self.directoryBox = directoryBox
            self.readerBox = readerBox
            self.inspectorBox = inspectorBox
            self.readerTopAccessoryBox = readerTopAccessoryBox
            lastSidebarRevision = sidebarRevision
            lastDirectoryRevision = directoryRevision
            lastReaderRevision = readerRevision
            lastInspectorRevision = inspectorRevision
            lastRequestedVisibility = WorkspacePaneVisibility(
                sidebarVisible: sidebarVisible.wrappedValue,
                directoryVisible: directoryVisible.wrappedValue,
                inspectorVisible: inspectorVisible.wrappedValue
            )
            sidebarController = NSHostingController(rootView: HostingContentRoot(box: sidebarBox))
            directoryController = NSHostingController(rootView: HostingContentRoot(box: directoryBox))
            readerController = NSHostingController(rootView: HostingContentRoot(box: readerBox))
            inspectorController = NSHostingController(rootView: HostingContentRoot(box: inspectorBox))
            readerTopAccessoryHostingController = NSHostingController(
                rootView: HostingContentRoot(box: readerTopAccessoryBox)
            )
            readerTopAccessoryController = Self.makeReaderTopAccessoryController(
                hostingController: readerTopAccessoryHostingController
            )
        }

        func updateBindings(
            sidebarVisible: Binding<Bool>,
            directoryVisible: Binding<Bool>,
            inspectorVisible: Binding<Bool>
        ) {
            sidebarVisibility = sidebarVisible
            directoryVisibility = directoryVisible
            inspectorVisibility = inspectorVisible
        }

        func updateWorkspace(
            sidebar: Sidebar,
            directory: Directory,
            reader: Reader,
            inspector: Inspector,
            readerTopAccessory: ReaderTopAccessory,
            sidebarRevision: String,
            directoryRevision: String,
            readerRevision: String,
            inspectorRevision: String,
            controller: WorkspaceSplitViewController,
            visibility: WorkspacePaneVisibility,
            animated: Bool
        ) {
            let sidebarChanged = lastSidebarRevision != sidebarRevision
            let directoryChanged = lastDirectoryRevision != directoryRevision
            let readerChanged = lastReaderRevision != readerRevision
            let inspectorChanged = lastInspectorRevision != inspectorRevision
            let visibilityChanged = lastRequestedVisibility != visibility
            guard sidebarChanged
                    || directoryChanged
                    || readerChanged
                    || inspectorChanged
                    || visibilityChanged else {
                return
            }

            if visibilityChanged {
                // Starting an AppKit split animation inside a representable
                // update can re-enter SwiftUI's layout graph. Publish the
                // request on the next MainActor turn and keep it independent
                // from hosted-content work so revisions cannot cancel it.
                lastRequestedVisibility = visibility
                paneVisibilityUpdate?.cancel()
                paneVisibilityUpdate = Task { @MainActor [weak self, weak controller] in
                    await Task.yield()
                    guard let self, let controller, !Task.isCancelled,
                          lastRequestedVisibility == visibility else {
                        return
                    }
                    controller.setPaneVisibility(
                        sidebarVisible: visibility.sidebarVisible,
                        directoryVisible: visibility.directoryVisible,
                        inspectorVisible: visibility.inspectorVisible,
                        animated: animated
                    )
                }
            }

            hostedContentUpdate?.cancel()
            hostedContentUpdate = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                if sidebarChanged {
                    lastSidebarRevision = sidebarRevision
                    sidebarBox.content = sidebar
                }
                if directoryChanged {
                    lastDirectoryRevision = directoryRevision
                    directoryBox.content = directory
                }
                if readerChanged {
                    lastReaderRevision = readerRevision
                    readerBox.content = reader
                }
                if inspectorChanged {
                    lastInspectorRevision = inspectorRevision
                    inspectorBox.content = inspector
                }
                if readerChanged {
                    readerTopAccessoryBox.content = readerTopAccessory
                }
            }
        }

        private static func makeReaderTopAccessoryController(
            hostingController: NSHostingController<HostingContentRoot<ReaderTopAccessory>>
        ) -> NSSplitViewItemAccessoryViewController {
            let controller = NSSplitViewItemAccessoryViewController()
            let containerView = NSView()
            controller.view = containerView
            controller.addChild(hostingController)
            let hostedView = hostingController.view
            hostedView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(hostedView)
            NSLayoutConstraint.activate([
                hostedView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                hostedView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                hostedView.topAnchor.constraint(equalTo: containerView.topAnchor),
                hostedView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]
            controller.automaticallyAppliesContentInsets = false
            if #available(macOS 26.1, *) {
                controller.preferredScrollEdgeEffectStyle = .soft
            }
            return controller
        }

        /// AppKit reports divider-driven collapse changes during its layout
        /// callback. Yield once before publishing into SwiftUI so native user
        /// interaction never mutates observable state during a representable update.
        func receiveNativeVisibility(_ visibility: WorkspacePaneVisibility) {
            nativeVisibilityUpdate?.cancel()
            nativeVisibilityUpdate = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled else { return }
                if sidebarVisibility.wrappedValue != visibility.sidebarVisible {
                    sidebarVisibility.wrappedValue = visibility.sidebarVisible
                }
                if directoryVisibility.wrappedValue != visibility.directoryVisible {
                    directoryVisibility.wrappedValue = visibility.directoryVisible
                }
                if inspectorVisibility.wrappedValue != visibility.inspectorVisible {
                    inspectorVisibility.wrappedValue = visibility.inspectorVisible
                }
            }
        }

        func updateReaderChromeVisibility(
            _ visible: Bool,
            controller: WorkspaceSplitViewController,
            animated: Bool
        ) {
            readerChromeVisibilityUpdate?.cancel()
            readerChromeVisibilityUpdate = Task { @MainActor [weak controller] in
                await Task.yield()
                guard let controller, !Task.isCancelled else { return }
                controller.setReaderTopAccessoryVisible(visible, animated: animated)
            }
        }

        deinit {
            paneVisibilityUpdate?.cancel()
            hostedContentUpdate?.cancel()
            nativeVisibilityUpdate?.cancel()
            readerChromeVisibilityUpdate?.cancel()
        }
    }
}

@MainActor
@Observable
private final class HostingContentBox<Content: View> {
    var content: Content

    init(content: Content) {
        self.content = content
    }
}

private struct HostingContentRoot<Content: View>: View {
    let box: HostingContentBox<Content>

    var body: some View {
        box.content
    }
}
