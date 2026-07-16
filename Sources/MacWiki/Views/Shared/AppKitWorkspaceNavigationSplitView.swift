import AppKit
import Observation
import SwiftUI

struct WorkspaceNavigationPaneVisibility: Equatable, Sendable {
    let listsVisible: Bool
    let directoryVisible: Bool
    let inspectorVisible: Bool
}

/// A narrow SwiftUI/AppKit boundary for the three independently collapsible
/// auxiliary panes. SwiftUI owns pane content; AppKit owns the semantic
/// sidebar, content-list, Reader, and full-height Inspector split items.
/// The Reader remains mounted in one stable hosting controller.
struct AppKitWorkspaceNavigationSplitView<
    Lists: View,
    Directory: View,
    Reader: View,
    Inspector: View,
    ReaderAccessory: View,
    InspectorAccessory: View
>:
    NSViewControllerRepresentable
{
    @Binding var listsVisible: Bool
    @Binding var directoryVisible: Bool
    @Binding var inspectorVisible: Bool

    let reduceMotion: Bool
    let initialListsWidth: CGFloat
    let initialDirectoryWidth: CGFloat
    let initialInspectorWidth: CGFloat
    var widthDefaults: UserDefaults = MacWikiDefaults.current
    let listsRevision: String
    let directoryRevision: String
    let readerRevision: String
    let inspectorRevision: String
    let readerAccessoryRevision: String
    let inspectorAccessoryRevision: String
    let lists: Lists
    let directory: Directory
    let reader: Reader
    let inspector: Inspector
    let readerAccessory: ReaderAccessory
    let inspectorAccessory: InspectorAccessory

    func makeCoordinator() -> Coordinator {
        Coordinator(
            listsVisible: $listsVisible,
            directoryVisible: $directoryVisible,
            inspectorVisible: $inspectorVisible,
            listsRevision: listsRevision,
            directoryRevision: directoryRevision,
            readerRevision: readerRevision,
            inspectorRevision: inspectorRevision,
            readerAccessoryRevision: readerAccessoryRevision,
            inspectorAccessoryRevision: inspectorAccessoryRevision,
            lists: lists,
            directory: directory,
            reader: reader,
            inspector: inspector,
            readerAccessory: readerAccessory,
            inspectorAccessory: inspectorAccessory
        )
    }

    func makeNSViewController(context: Context) -> AppKitWorkspaceNavigationController {
        let controller = AppKitWorkspaceNavigationController(
            listsController: context.coordinator.listsController,
            directoryController: context.coordinator.directoryController,
            readerController: context.coordinator.readerController,
            inspectorController: context.coordinator.inspectorController,
            readerAccessoryController: context.coordinator.readerAccessoryController,
            inspectorAccessoryController: context.coordinator.inspectorAccessoryController,
            initialListsWidth: initialListsWidth,
            initialDirectoryWidth: initialDirectoryWidth,
            initialInspectorWidth: initialInspectorWidth,
            widthDefaults: widthDefaults
        )
        controller.onPaneVisibilityChange = { [weak coordinator = context.coordinator] visibility in
            coordinator?.receiveNativeVisibility(visibility)
        }
        _ = controller.view
        controller.setPaneVisibility(
            listsVisible: listsVisible,
            directoryVisible: directoryVisible,
            inspectorVisible: inspectorVisible,
            animated: false
        )
        return controller
    }

    func updateNSViewController(
        _ controller: AppKitWorkspaceNavigationController,
        context: Context
    ) {
        context.coordinator.updateBindings(
            listsVisible: $listsVisible,
            directoryVisible: $directoryVisible,
            inspectorVisible: $inspectorVisible
        )
        context.coordinator.updateContent(
            lists: lists,
            directory: directory,
            reader: reader,
            inspector: inspector,
            readerAccessory: readerAccessory,
            inspectorAccessory: inspectorAccessory,
            listsRevision: listsRevision,
            directoryRevision: directoryRevision,
            readerRevision: readerRevision,
            inspectorRevision: inspectorRevision,
            readerAccessoryRevision: readerAccessoryRevision,
            inspectorAccessoryRevision: inspectorAccessoryRevision
        )
        context.coordinator.requestVisibility(
            WorkspaceNavigationPaneVisibility(
                listsVisible: listsVisible,
                directoryVisible: directoryVisible,
                inspectorVisible: inspectorVisible
            ),
            controller: controller,
            animated: !reduceMotion
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: AppKitWorkspaceNavigationController,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height,
              width.isFinite,
              height.isFinite else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSViewController(
        _ controller: AppKitWorkspaceNavigationController,
        coordinator: Coordinator
    ) {
        controller.onPaneVisibilityChange = nil
        coordinator.cancelPendingWork()
    }

    @MainActor
    final class Coordinator {
        fileprivate let listsController: NSHostingController<WorkspaceHostingRoot<Lists>>
        fileprivate let directoryController: NSHostingController<WorkspaceHostingRoot<Directory>>
        fileprivate let readerController: NSHostingController<WorkspaceHostingRoot<Reader>>
        fileprivate let inspectorController: NSHostingController<WorkspaceHostingRoot<Inspector>>
        fileprivate let readerAccessoryController: WorkspaceSplitItemAccessoryController<ReaderAccessory>
        fileprivate let inspectorAccessoryController: WorkspaceSplitItemAccessoryController<InspectorAccessory>

        private let listsBox: WorkspaceHostingBox<Lists>
        private let directoryBox: WorkspaceHostingBox<Directory>
        private let readerBox: WorkspaceHostingBox<Reader>
        private let inspectorBox: WorkspaceHostingBox<Inspector>
        private let readerAccessoryBox: WorkspaceHostingBox<ReaderAccessory>
        private let inspectorAccessoryBox: WorkspaceHostingBox<InspectorAccessory>
        private var listsVisibility: Binding<Bool>
        private var directoryVisibility: Binding<Bool>
        private var inspectorVisibility: Binding<Bool>
        private var lastListsRevision: String
        private var lastDirectoryRevision: String
        private var lastReaderRevision: String
        private var lastInspectorRevision: String
        private var lastReaderAccessoryRevision: String
        private var lastInspectorAccessoryRevision: String
        private var lastRequestedVisibility: WorkspaceNavigationPaneVisibility
        private var contentUpdate: Task<Void, Never>?
        private var visibilityUpdate: Task<Void, Never>?
        private var nativeVisibilityUpdate: Task<Void, Never>?

        init(
            listsVisible: Binding<Bool>,
            directoryVisible: Binding<Bool>,
            inspectorVisible: Binding<Bool>,
            listsRevision: String,
            directoryRevision: String,
            readerRevision: String,
            inspectorRevision: String,
            readerAccessoryRevision: String,
            inspectorAccessoryRevision: String,
            lists: Lists,
            directory: Directory,
            reader: Reader,
            inspector: Inspector,
            readerAccessory: ReaderAccessory,
            inspectorAccessory: InspectorAccessory
        ) {
            listsVisibility = listsVisible
            directoryVisibility = directoryVisible
            inspectorVisibility = inspectorVisible
            lastListsRevision = listsRevision
            lastDirectoryRevision = directoryRevision
            lastReaderRevision = readerRevision
            lastInspectorRevision = inspectorRevision
            lastReaderAccessoryRevision = readerAccessoryRevision
            lastInspectorAccessoryRevision = inspectorAccessoryRevision
            lastRequestedVisibility = WorkspaceNavigationPaneVisibility(
                listsVisible: listsVisible.wrappedValue,
                directoryVisible: directoryVisible.wrappedValue,
                inspectorVisible: inspectorVisible.wrappedValue
            )

            let listsBox = WorkspaceHostingBox(content: lists)
            let directoryBox = WorkspaceHostingBox(content: directory)
            let readerBox = WorkspaceHostingBox(content: reader)
            let inspectorBox = WorkspaceHostingBox(content: inspector)
            let readerAccessoryBox = WorkspaceHostingBox(content: readerAccessory)
            let inspectorAccessoryBox = WorkspaceHostingBox(content: inspectorAccessory)
            self.listsBox = listsBox
            self.directoryBox = directoryBox
            self.readerBox = readerBox
            self.inspectorBox = inspectorBox
            self.readerAccessoryBox = readerAccessoryBox
            self.inspectorAccessoryBox = inspectorAccessoryBox
            listsController = NSHostingController(rootView: WorkspaceHostingRoot(box: listsBox))
            directoryController = NSHostingController(rootView: WorkspaceHostingRoot(box: directoryBox))
            readerController = NSHostingController(rootView: WorkspaceHostingRoot(box: readerBox))
            inspectorController = NSHostingController(rootView: WorkspaceHostingRoot(box: inspectorBox))
            readerAccessoryController = WorkspaceSplitItemAccessoryController(
                box: readerAccessoryBox,
                height: ColumnChromeMetrics.secondaryBarHeight
            )
            inspectorAccessoryController = WorkspaceSplitItemAccessoryController(
                box: inspectorAccessoryBox,
                height: ColumnChromeMetrics.secondaryBarHeight
            )
            listsController.sizingOptions = []
            directoryController.sizingOptions = []
            readerController.sizingOptions = []
            inspectorController.sizingOptions = []
        }

        func updateBindings(
            listsVisible: Binding<Bool>,
            directoryVisible: Binding<Bool>,
            inspectorVisible: Binding<Bool>
        ) {
            listsVisibility = listsVisible
            directoryVisibility = directoryVisible
            inspectorVisibility = inspectorVisible
        }

        func updateContent(
            lists: Lists,
            directory: Directory,
            reader: Reader,
            inspector: Inspector,
            readerAccessory: ReaderAccessory,
            inspectorAccessory: InspectorAccessory,
            listsRevision: String,
            directoryRevision: String,
            readerRevision: String,
            inspectorRevision: String,
            readerAccessoryRevision: String,
            inspectorAccessoryRevision: String
        ) {
            let listsChanged = lastListsRevision != listsRevision
            let directoryChanged = lastDirectoryRevision != directoryRevision
            let readerChanged = lastReaderRevision != readerRevision
            let inspectorChanged = lastInspectorRevision != inspectorRevision
            let readerAccessoryChanged = lastReaderAccessoryRevision != readerAccessoryRevision
            let inspectorAccessoryChanged = lastInspectorAccessoryRevision != inspectorAccessoryRevision
            guard listsChanged || directoryChanged || readerChanged || inspectorChanged
                    || readerAccessoryChanged || inspectorAccessoryChanged else {
                return
            }

            contentUpdate?.cancel()
            contentUpdate = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled else { return }
                if listsChanged {
                    lastListsRevision = listsRevision
                    listsBox.content = lists
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
                if readerAccessoryChanged {
                    lastReaderAccessoryRevision = readerAccessoryRevision
                    readerAccessoryBox.content = readerAccessory
                }
                if inspectorAccessoryChanged {
                    lastInspectorAccessoryRevision = inspectorAccessoryRevision
                    inspectorAccessoryBox.content = inspectorAccessory
                }
            }
        }

        func requestVisibility(
            _ visibility: WorkspaceNavigationPaneVisibility,
            controller: AppKitWorkspaceNavigationController,
            animated: Bool
        ) {
            guard lastRequestedVisibility != visibility else { return }
            lastRequestedVisibility = visibility
            visibilityUpdate?.cancel()
            visibilityUpdate = Task { @MainActor [weak self, weak controller] in
                await Task.yield()
                guard let self, let controller, !Task.isCancelled,
                      lastRequestedVisibility == visibility else {
                    return
                }
                controller.setPaneVisibility(
                    listsVisible: visibility.listsVisible,
                    directoryVisible: visibility.directoryVisible,
                    inspectorVisible: visibility.inspectorVisible,
                    animated: animated
                )
            }
        }

        func receiveNativeVisibility(_ visibility: WorkspaceNavigationPaneVisibility) {
            lastRequestedVisibility = visibility
            nativeVisibilityUpdate?.cancel()
            nativeVisibilityUpdate = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled else { return }
                if listsVisibility.wrappedValue != visibility.listsVisible {
                    listsVisibility.wrappedValue = visibility.listsVisible
                }
                if directoryVisibility.wrappedValue != visibility.directoryVisible {
                    directoryVisibility.wrappedValue = visibility.directoryVisible
                }
                if inspectorVisibility.wrappedValue != visibility.inspectorVisible {
                    inspectorVisibility.wrappedValue = visibility.inspectorVisible
                }
            }
        }

        func cancelPendingWork() {
            contentUpdate?.cancel()
            visibilityUpdate?.cancel()
            nativeVisibilityUpdate?.cancel()
        }

        deinit {
            contentUpdate?.cancel()
            visibilityUpdate?.cancel()
            nativeVisibilityUpdate?.cancel()
        }
    }
}

@MainActor
@Observable
private final class WorkspaceHostingBox<Content: View> {
    var content: Content

    init(content: Content) {
        self.content = content
    }
}

private struct WorkspaceHostingRoot<Content: View>: View {
    let box: WorkspaceHostingBox<Content>

    var body: some View {
        box.content
    }
}

/// macOS 26 lets each semantic split item own top chrome without measuring its
/// x-position in the window toolbar. This container preserves a stable SwiftUI
/// host while AppKit owns accessory sizing, collapse, and divider alignment.
@MainActor
final class WorkspaceSplitItemAccessoryController<Content: View>:
    NSSplitViewItemAccessoryViewController
{
    private let hostingController: NSHostingController<WorkspaceHostingRoot<Content>>
    private let height: CGFloat

    fileprivate init(box: WorkspaceHostingBox<Content>, height: CGFloat) {
        hostingController = NSHostingController(rootView: WorkspaceHostingRoot(box: box))
        self.height = height
        super.init(nibName: nil, bundle: nil)
        automaticallyAppliesContentInsets = false
        preferredContentSize = NSSize(width: 0, height: height)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: .zero)
        hostingController.sizingOptions = []
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hostingController)
        container.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: height)
        ])
        view = container
    }
}

/// The single platform-owned workspace split. Semantic AppKit items give the
/// leading Sidebar and trailing Inspector full-height native presentation
/// while keeping the Reader controller permanently mounted between them.
@MainActor
final class AppKitWorkspaceNavigationController: NSSplitViewController {
    private enum WidthPersistence {
        static let restoreDelay = Duration.milliseconds(40)
        static let animatedRestoreDelay = Duration.milliseconds(240)
        static let persistenceDelay = Duration.milliseconds(350)
        static let tolerance: CGFloat = 1
    }

    private enum WindowGeometry {
        static let reconciliationDelay = Duration.milliseconds(90)
        static let widthTolerance: CGFloat = 2
    }

    private enum PaneLayout {
        enum LeadingPane {
            case lists
            case directory
        }

        static let auxiliaryHoldingPriority = NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1
        )
    }

    var onPaneVisibilityChange: ((WorkspaceNavigationPaneVisibility) -> Void)?

    private let listsItem: NSSplitViewItem
    private let directoryItem: NSSplitViewItem
    private let readerItem: NSSplitViewItem
    private let inspectorItem: NSSplitViewItem
    private let readerAccessoryController: NSSplitViewItemAccessoryViewController?
    private let inspectorAccessoryController: NSSplitViewItemAccessoryViewController?
    private let initialListsWidth: CGFloat
    private let initialDirectoryWidth: CGFloat
    private let initialInspectorWidth: CGFloat
    private let widthDefaults: UserDefaults
    private var didRestoreListsWidth = false
    private var didRestoreDirectoryWidth = false
    private var didRestoreInspectorWidth = false
    private var requestedVisibility: WorkspaceNavigationPaneVisibility?
    private var lastReportedVisibility: WorkspaceNavigationPaneVisibility?
    private var visibilityTransitionGeneration = 0
    private var isApplyingRequestedVisibility = false
    private var isEnforcingReadableLayout = false
    private var pendingInitialWidthRestore: Task<Void, Never>?
    private var pendingWidthPersistence: Task<Void, Never>?
    private var pendingWindowGeometryReconciliation: Task<Void, Never>?
    private var windowGeometryVisibilitySnapshot: WorkspaceNavigationPaneVisibility?
    private var lastObservedWindowContentWidth: CGFloat?

    init(
        listsController: NSViewController,
        directoryController: NSViewController,
        readerController: NSViewController,
        inspectorController: NSViewController,
        readerAccessoryController: NSSplitViewItemAccessoryViewController? = nil,
        inspectorAccessoryController: NSSplitViewItemAccessoryViewController? = nil,
        initialListsWidth: CGFloat,
        initialDirectoryWidth: CGFloat,
        initialInspectorWidth: CGFloat,
        widthDefaults: UserDefaults = MacWikiDefaults.current
    ) {
        listsItem = NSSplitViewItem(sidebarWithViewController: listsController)
        directoryItem = NSSplitViewItem(contentListWithViewController: directoryController)
        readerItem = NSSplitViewItem(viewController: readerController)
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorController)
        self.readerAccessoryController = readerAccessoryController
        self.inspectorAccessoryController = inspectorAccessoryController
        self.initialListsWidth = Self.clamped(
            initialListsWidth,
            to: MainWindowColumnWidth.sidebarRange,
            fallback: AppStorageKey.MainWindow.sidebarWidthDefault
        )
        self.initialDirectoryWidth = Self.clamped(
            initialDirectoryWidth,
            to: MainWindowColumnWidth.directoryRange,
            fallback: AppStorageKey.MainWindow.directoryWidthDefault
        )
        self.initialInspectorWidth = Self.clamped(
            initialInspectorWidth,
            to: MainWindowColumnWidth.inspectorRange,
            fallback: AppStorageKey.MainWindow.inspectorWidthDefault
        )
        self.widthDefaults = widthDefaults
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        configure(
            listsItem,
            minimum: MainWindowColumnWidth.sidebarRange.lowerBound,
            maximum: MainWindowColumnWidth.sidebarRange.upperBound,
            holdingPriority: PaneLayout.auxiliaryHoldingPriority,
            canCollapse: true
        )
        // Preserve AppKit's native Sidebar behavior at compact window widths.
        // The Inspector remains pinned, so the two leading navigation panes
        // must be allowed to yield before the Reader is compressed.
        listsItem.canCollapseFromWindowResize = true
        listsItem.allowsFullHeightLayout = true
        configureAuxiliaryCollapseBehavior(listsItem)

        configure(
            directoryItem,
            minimum: MainWindowColumnWidth.directoryRange.lowerBound,
            maximum: MainWindowColumnWidth.directoryRange.upperBound,
            holdingPriority: PaneLayout.auxiliaryHoldingPriority,
            canCollapse: true
        )
        directoryItem.canCollapseFromWindowResize = true
        configureAuxiliaryCollapseBehavior(directoryItem)

        configure(
            readerItem,
            minimum: MainWindowLayout.minimumCompactReaderWidth,
            maximum: 10_000,
            holdingPriority: .defaultLow,
            canCollapse: false
        )

        configure(
            inspectorItem,
            minimum: MainWindowColumnWidth.inspectorRange.lowerBound,
            maximum: MainWindowColumnWidth.inspectorRange.upperBound,
            holdingPriority: PaneLayout.auxiliaryHoldingPriority,
            canCollapse: true
        )
        inspectorItem.canCollapseFromWindowResize = false
        inspectorItem.allowsFullHeightLayout = true
        configureAuxiliaryCollapseBehavior(inspectorItem)

        addSplitViewItem(listsItem)
        addSplitViewItem(directoryItem)
        addSplitViewItem(readerItem)
        addSplitViewItem(inspectorItem)
        if let readerAccessoryController {
            readerItem.addTopAlignedAccessoryViewController(readerAccessoryController)
        }
        if let inspectorAccessoryController {
            inspectorItem.addTopAlignedAccessoryViewController(inspectorAccessoryController)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let window = view.window {
            WorkspaceSplitControllerRegistry.register(self, in: window)
        }
        guard !observeWindowGeometryTransitionIfNeeded() else { return }
        if collapseLeadingPanesForReadableLayoutIfNeeded() {
            reportUserDrivenVisibilityIfNeeded()
        }
        scheduleInitialWidthRestore(after: WidthPersistence.restoreDelay)
    }

    override func viewWillDisappear() {
        if let window = view.window {
            WorkspaceSplitControllerRegistry.unregister(self, from: window)
        }
        super.viewWillDisappear()
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard pendingWindowGeometryReconciliation == nil,
              view.window?.inLiveResize != true else {
            return
        }
        reportUserDrivenVisibilityIfNeeded()
        scheduleWidthPersistence()
    }

    func setPaneVisibility(
        listsVisible: Bool,
        directoryVisible: Bool,
        inspectorVisible: Bool,
        animated: Bool
    ) {
        let requested = WorkspaceNavigationPaneVisibility(
            listsVisible: listsVisible,
            directoryVisible: directoryVisible,
            inspectorVisible: inspectorVisible
        )
        let target = readableVisibility(
            requested,
            preservingNewlyRevealedPaneComparedTo: currentVisibility
        )
        requestedVisibility = requested
        visibilityTransitionGeneration &+= 1
        let generation = visibilityTransitionGeneration

        let listsChanged = listsItem.isCollapsed == target.listsVisible
        let directoryChanged = directoryItem.isCollapsed == target.directoryVisible
        let inspectorChanged = inspectorItem.isCollapsed == target.inspectorVisible
        guard listsChanged || directoryChanged || inspectorChanged else {
            finishVisibilityUpdate(generation: generation, animated: false)
            return
        }

        isApplyingRequestedVisibility = true
        let apply = {
            if listsChanged {
                self.listsItem.isCollapsed = !target.listsVisible
            }
            if directoryChanged {
                self.directoryItem.isCollapsed = !target.directoryVisible
            }
            if inspectorChanged {
                self.inspectorItem.isCollapsed = !target.inspectorVisible
            }
        }

        guard animated, view.window != nil else {
            apply()
            finishVisibilityUpdate(generation: generation, animated: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            if listsChanged {
                listsItem.animator().isCollapsed = !target.listsVisible
            }
            if directoryChanged {
                directoryItem.animator().isCollapsed = !target.directoryVisible
            }
            if inspectorChanged {
                inspectorItem.animator().isCollapsed = !target.inspectorVisible
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.finishVisibilityUpdate(generation: generation, animated: true)
            }
        }
    }

    deinit {
        pendingInitialWidthRestore?.cancel()
        pendingWidthPersistence?.cancel()
        pendingWindowGeometryReconciliation?.cancel()
    }

    private var currentVisibility: WorkspaceNavigationPaneVisibility {
        WorkspaceNavigationPaneVisibility(
            listsVisible: !listsItem.isCollapsed,
            directoryVisible: !directoryItem.isCollapsed,
            inspectorVisible: !inspectorItem.isCollapsed
        )
    }

    private func finishVisibilityUpdate(generation: Int, animated: Bool) {
        guard visibilityTransitionGeneration == generation else { return }
        isApplyingRequestedVisibility = false
        let visibility = currentVisibility
        if visibility != requestedVisibility {
            requestedVisibility = visibility
            if visibility != lastReportedVisibility {
                lastReportedVisibility = visibility
                onPaneVisibilityChange?(visibility)
            }
        } else {
            lastReportedVisibility = visibility
        }
        scheduleInitialWidthRestore(
            after: animated
                ? WidthPersistence.animatedRestoreDelay
                : WidthPersistence.restoreDelay,
            replacingPending: true
        )
    }

    func restoreInitialVisibleWidthsIfFeasible() {
        let visibility = currentVisibility
        let visibleAuxiliaryWidth = (visibility.listsVisible ? initialListsWidth : 0)
            + (visibility.directoryVisible ? initialDirectoryWidth : 0)
            + (visibility.inspectorVisible ? initialInspectorWidth : 0)
        let visibleAuxiliaryCount = [
            visibility.listsVisible,
            visibility.directoryVisible,
            visibility.inspectorVisible
        ].filter { $0 }.count
        let required = MainWindowLayout.minimumReaderWidth
            + visibleAuxiliaryWidth
            + (CGFloat(visibleAuxiliaryCount) * splitView.dividerThickness)
        guard splitView.bounds.width.isFinite,
              splitView.bounds.width >= required else {
            establishAdaptiveWidthBaselineIfValid(visibility: visibility)
            return
        }

        let shouldRestoreLists = visibility.listsVisible && !didRestoreListsWidth
        let shouldRestoreDirectory = visibility.directoryVisible && !didRestoreDirectoryWidth
        let shouldRestoreInspector = visibility.inspectorVisible && !didRestoreInspectorWidth

        if shouldRestoreLists {
            listsItem.minimumThickness = initialListsWidth
            listsItem.maximumThickness = initialListsWidth
        }
        if shouldRestoreDirectory {
            directoryItem.minimumThickness = initialDirectoryWidth
            directoryItem.maximumThickness = initialDirectoryWidth
        }
        if shouldRestoreInspector {
            inspectorItem.minimumThickness = initialInspectorWidth
            inspectorItem.maximumThickness = initialInspectorWidth
        }
        if shouldRestoreLists || shouldRestoreDirectory || shouldRestoreInspector {
            splitView.adjustSubviews()
            splitView.layoutSubtreeIfNeeded()
        }
        if shouldRestoreLists {
            listsItem.maximumThickness = MainWindowColumnWidth.sidebarRange.upperBound
            listsItem.minimumThickness = MainWindowColumnWidth.sidebarRange.lowerBound
        }
        if shouldRestoreDirectory {
            directoryItem.maximumThickness = MainWindowColumnWidth.directoryRange.upperBound
            directoryItem.minimumThickness = MainWindowColumnWidth.directoryRange.lowerBound
        }
        if shouldRestoreInspector {
            inspectorItem.maximumThickness = MainWindowColumnWidth.inspectorRange.upperBound
            inspectorItem.minimumThickness = MainWindowColumnWidth.inspectorRange.lowerBound
        }

        if visibility.listsVisible {
            didRestoreListsWidth = Self.matches(
                listsItem.viewController.view.bounds.width,
                initialListsWidth
            )
        }
        if visibility.directoryVisible {
            didRestoreDirectoryWidth = Self.matches(
                directoryItem.viewController.view.bounds.width,
                initialDirectoryWidth
            )
        }
        if visibility.inspectorVisible {
            didRestoreInspectorWidth = Self.matches(
                inspectorItem.viewController.view.bounds.width,
                initialInspectorWidth
            )
        }
    }

    private func reportUserDrivenVisibilityIfNeeded() {
        guard !isApplyingRequestedVisibility, !isEnforcingReadableLayout else { return }
        let visibility = currentVisibility
        guard visibility != requestedVisibility else {
            lastReportedVisibility = visibility
            return
        }
        requestedVisibility = visibility
        guard visibility != lastReportedVisibility else { return }
        lastReportedVisibility = visibility
        onPaneVisibilityChange?(visibility)
    }

    private func scheduleInitialWidthRestore(
        after delay: Duration,
        replacingPending: Bool = false
    ) {
        guard (!listsItem.isCollapsed && !didRestoreListsWidth)
                || (!directoryItem.isCollapsed && !didRestoreDirectoryWidth)
                || (!inspectorItem.isCollapsed && !didRestoreInspectorWidth) else {
            return
        }
        if replacingPending {
            pendingInitialWidthRestore?.cancel()
            pendingInitialWidthRestore = nil
        } else {
            guard pendingInitialWidthRestore == nil else { return }
        }

        pendingInitialWidthRestore = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            pendingInitialWidthRestore = nil
            restoreInitialVisibleWidthsIfFeasible()
        }
    }

    private func readableVisibility(
        _ visibility: WorkspaceNavigationPaneVisibility,
        preservingNewlyRevealedPaneComparedTo current: WorkspaceNavigationPaneVisibility? = nil
    ) -> WorkspaceNavigationPaneVisibility {
        let availableWidth = splitView.bounds.width
        guard availableWidth.isFinite, availableWidth > 0 else { return visibility }

        let protectedLeadingPane: PaneLayout.LeadingPane? = if let current {
            if visibility.listsVisible, !current.listsVisible {
                .lists
            } else if visibility.directoryVisible, !current.directoryVisible {
                .directory
            } else {
                nil
            }
        } else {
            nil
        }

        var listsVisible = visibility.listsVisible
        var directoryVisible = visibility.directoryVisible
        let inspectorVisible = visibility.inspectorVisible

        func requiredWidth() -> CGFloat {
            MainWindowLayout.minimumCompactContentWidth(
                listsSidebarVisible: listsVisible,
                directoryVisible: directoryVisible,
                inspectorVisible: inspectorVisible
            )
        }

        while requiredWidth() > availableWidth {
            if listsVisible, protectedLeadingPane != .lists {
                listsVisible = false
            } else if directoryVisible, protectedLeadingPane != .directory {
                directoryVisible = false
            } else if listsVisible {
                listsVisible = false
            } else if directoryVisible {
                directoryVisible = false
            } else {
                break
            }
        }

        return WorkspaceNavigationPaneVisibility(
            listsVisible: listsVisible,
            directoryVisible: directoryVisible,
            inspectorVisible: inspectorVisible
        )
    }

    private func collapseLeadingPanesForReadableLayoutIfNeeded() -> Bool {
        guard !isApplyingRequestedVisibility,
              !isEnforcingReadableLayout,
              pendingWindowGeometryReconciliation == nil,
              view.window?.inLiveResize != true else {
            return false
        }
        let visibility = currentVisibility
        let target = readableVisibility(visibility)
        guard target != visibility else { return false }

        isEnforcingReadableLayout = true
        if visibility.listsVisible != target.listsVisible {
            listsItem.isCollapsed = !target.listsVisible
        }
        if visibility.directoryVisible != target.directoryVisible {
            directoryItem.isCollapsed = !target.directoryVisible
        }
        isEnforcingReadableLayout = false
        return true
    }

    /// AppKit can briefly publish a narrow split width while an NSWindow size
    /// change is being applied. Treating that frame as a divider gesture
    /// permanently ratchets leading panes closed even when the final window is
    /// wider. Snapshot the pre-resize visibility, wait for window and split
    /// geometry to agree, then apply the compact-width policy once.
    private func observeWindowGeometryTransitionIfNeeded() -> Bool {
        guard let window = view.window else { return false }
        let width = window.contentLayoutRect.width
        guard width.isFinite, width > 0 else { return false }

        guard let lastWidth = lastObservedWindowContentWidth else {
            self.lastObservedWindowContentWidth = width
            return false
        }
        let widthChanged = abs(lastWidth - width)
            > WindowGeometry.widthTolerance
        if widthChanged {
            lastObservedWindowContentWidth = width
            if windowGeometryVisibilitySnapshot == nil {
                windowGeometryVisibilitySnapshot = requestedVisibility ?? currentVisibility
            }
            scheduleWindowGeometryReconciliation(expectedWindowWidth: width)
        }
        return widthChanged
            || pendingWindowGeometryReconciliation != nil
            || window.inLiveResize
    }

    private func scheduleWindowGeometryReconciliation(
        expectedWindowWidth: CGFloat
    ) {
        pendingWindowGeometryReconciliation?.cancel()
        pendingWindowGeometryReconciliation = Task { @MainActor [weak self] in
            try? await Task.sleep(for: WindowGeometry.reconciliationDelay)
            guard let self, !Task.isCancelled, let window = view.window else { return }

            let currentWindowWidth = window.contentLayoutRect.width
            if window.inLiveResize {
                pendingWindowGeometryReconciliation = nil
                scheduleWindowGeometryReconciliation(expectedWindowWidth: currentWindowWidth)
                return
            }
            guard splitView.bounds.width.isFinite,
                  splitView.bounds.width > 0 else {
                pendingWindowGeometryReconciliation = nil
                return
            }
            guard abs(currentWindowWidth - expectedWindowWidth)
                    <= WindowGeometry.widthTolerance else {
                lastObservedWindowContentWidth = currentWindowWidth
                pendingWindowGeometryReconciliation = nil
                scheduleWindowGeometryReconciliation(expectedWindowWidth: currentWindowWidth)
                return
            }

            pendingWindowGeometryReconciliation = nil
            let snapshot = windowGeometryVisibilitySnapshot ?? requestedVisibility ?? currentVisibility
            windowGeometryVisibilitySnapshot = nil
            reconcileWindowGeometry(to: snapshot)
        }
    }

    private func reconcileWindowGeometry(
        to snapshot: WorkspaceNavigationPaneVisibility
    ) {
        let target = readableVisibility(snapshot)
        isEnforcingReadableLayout = true
        if currentVisibility.listsVisible != target.listsVisible {
            listsItem.isCollapsed = !target.listsVisible
        }
        if currentVisibility.directoryVisible != target.directoryVisible {
            directoryItem.isCollapsed = !target.directoryVisible
        }
        if currentVisibility.inspectorVisible != target.inspectorVisible {
            inspectorItem.isCollapsed = !target.inspectorVisible
        }
        splitView.layoutSubtreeIfNeeded()
        isEnforcingReadableLayout = false

        requestedVisibility = target
        if target != snapshot, target != lastReportedVisibility {
            lastReportedVisibility = target
            onPaneVisibilityChange?(target)
        } else if target == snapshot {
            lastReportedVisibility = target
        }
        scheduleInitialWidthRestore(
            after: WidthPersistence.restoreDelay,
            replacingPending: true
        )
    }

    private func scheduleWidthPersistence() {
        pendingWidthPersistence?.cancel()
        pendingWidthPersistence = Task { @MainActor [weak self] in
            try? await Task.sleep(for: WidthPersistence.persistenceDelay)
            guard let self, !Task.isCancelled else { return }
            persistVisibleWidths()
        }
    }

    private func establishAdaptiveWidthBaselineIfValid(
        visibility: WorkspaceNavigationPaneVisibility
    ) {
        let minimumAdaptiveWidth = MainWindowLayout.minimumContentWidth(
            listsSidebarVisible: visibility.listsVisible,
            directoryVisible: visibility.directoryVisible,
            inspectorVisible: visibility.inspectorVisible
        )
        guard splitView.bounds.width >= minimumAdaptiveWidth else { return }

        if visibility.listsVisible,
           Self.isPersistable(
               listsItem.viewController.view.bounds.width,
               in: MainWindowColumnWidth.sidebarRange
           ) {
            didRestoreListsWidth = true
        }
        if visibility.directoryVisible,
           Self.isPersistable(
               directoryItem.viewController.view.bounds.width,
               in: MainWindowColumnWidth.directoryRange
           ) {
            didRestoreDirectoryWidth = true
        }
        if visibility.inspectorVisible,
           Self.isPersistable(
               inspectorItem.viewController.view.bounds.width,
               in: MainWindowColumnWidth.inspectorRange
           ) {
            didRestoreInspectorWidth = true
        }
    }

    private func persistVisibleWidths() {
        persistWidth(
            of: listsItem,
            didRestoreInitialWidth: didRestoreListsWidth,
            key: AppStorageKey.MainWindow.sidebarWidth,
            range: MainWindowColumnWidth.sidebarRange
        )
        persistWidth(
            of: directoryItem,
            didRestoreInitialWidth: didRestoreDirectoryWidth,
            key: AppStorageKey.MainWindow.directoryWidth,
            range: MainWindowColumnWidth.directoryRange
        )
        persistWidth(
            of: inspectorItem,
            didRestoreInitialWidth: didRestoreInspectorWidth,
            key: AppStorageKey.MainWindow.inspectorWidth,
            range: MainWindowColumnWidth.inspectorRange
        )
    }

    private func persistWidth(
        of item: NSSplitViewItem,
        didRestoreInitialWidth: Bool,
        key: String,
        range: ClosedRange<CGFloat>
    ) {
        guard !item.isCollapsed,
              didRestoreInitialWidth,
              let value = MainWindowColumnWidth.clampedStorageValue(
                  item.viewController.view.bounds.width,
                  range: range
              ) else {
            return
        }

        let storedValue = widthDefaults.object(forKey: key) as? Double
        guard storedValue.map({ abs($0 - value) >= Double(WidthPersistence.tolerance) }) ?? true else {
            return
        }
        widthDefaults.set(value, forKey: key)
    }

    private func configureAuxiliaryCollapseBehavior(_ item: NSSplitViewItem) {
        item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        item.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
        item.automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension
    }

    private func configure(
        _ item: NSSplitViewItem,
        minimum: CGFloat,
        maximum: CGFloat,
        holdingPriority: NSLayoutConstraint.Priority,
        canCollapse: Bool
    ) {
        item.minimumThickness = minimum
        item.maximumThickness = maximum
        item.canCollapse = canCollapse
        item.holdingPriority = holdingPriority
    }

    private static func clamped(
        _ value: CGFloat,
        to range: ClosedRange<CGFloat>,
        fallback: CGFloat
    ) -> CGFloat {
        guard value.isFinite, value > 0 else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func matches(_ width: CGFloat, _ expected: CGFloat) -> Bool {
        abs(width - expected) < WidthPersistence.tolerance
    }

    private static func isPersistable(
        _ width: CGFloat,
        in range: ClosedRange<CGFloat>
    ) -> Bool {
        width.isFinite
            && width >= range.lowerBound - WidthPersistence.tolerance
            && width <= range.upperBound + WidthPersistence.tolerance
    }
}
