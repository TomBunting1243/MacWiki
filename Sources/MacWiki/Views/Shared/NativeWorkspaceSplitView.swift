import AppKit
import Observation
import SwiftUI

/// A stable SwiftUI-to-AppKit bridge for the main window's four native panes.
/// SwiftUI owns pane content and application state; AppKit owns the semantic
/// split items, dividers, collapse interactions, and point-based sizing.
struct NativeWorkspaceSplitView<Sidebar: View, Directory: View, Reader: View, Inspector: View>:
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
    let readerToolbarEnvironment: ReaderToolbarEnvironment
    let sidebar: Sidebar
    let directory: Directory
    let reader: Reader
    let inspector: Inspector

    func makeCoordinator() -> Coordinator {
        Coordinator(
            sidebarVisible: $sidebarVisible,
            directoryVisible: $directoryVisible,
            inspectorVisible: $inspectorVisible,
            sidebar: sidebar,
            directory: directory,
            reader: reader,
            inspector: inspector,
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
        controller.configureReaderToolbar(environment: readerToolbarEnvironment)
        controller.setPaneVisibility(
            sidebarVisible: sidebarVisible,
            directoryVisible: directoryVisible,
            inspectorVisible: inspectorVisible,
            animated: false
        )
        return controller
    }

    func updateNSViewController(_ controller: WorkspaceSplitViewController, context: Context) {
        controller.configureReaderToolbar(environment: readerToolbarEnvironment)
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
        controller.invalidateReaderToolbar()
    }

    @MainActor
    final class Coordinator {
        fileprivate let sidebarBox: HostingContentBox<Sidebar>
        fileprivate let directoryBox: HostingContentBox<Directory>
        fileprivate let readerBox: HostingContentBox<Reader>
        fileprivate let inspectorBox: HostingContentBox<Inspector>
        fileprivate let sidebarController: NSHostingController<HostingContentRoot<Sidebar>>
        fileprivate let directoryController: NSHostingController<HostingContentRoot<Directory>>
        fileprivate let readerController: NSHostingController<HostingContentRoot<Reader>>
        fileprivate let inspectorController: NSHostingController<HostingContentRoot<Inspector>>

        private var sidebarVisibility: Binding<Bool>
        private var directoryVisibility: Binding<Bool>
        private var inspectorVisibility: Binding<Bool>
        private var paneVisibilityUpdate: Task<Void, Never>?
        private var hostedContentUpdate: Task<Void, Never>?
        private var nativeVisibilityUpdate: Task<Void, Never>?
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
            self.sidebarBox = sidebarBox
            self.directoryBox = directoryBox
            self.readerBox = readerBox
            self.inspectorBox = inspectorBox
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
            }
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

        deinit {
            paneVisibilityUpdate?.cancel()
            hostedContentUpdate?.cancel()
            nativeVisibilityUpdate?.cancel()
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
