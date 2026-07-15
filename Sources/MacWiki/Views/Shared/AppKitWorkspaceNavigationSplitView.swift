import AppKit
import Observation
import SwiftUI

struct WorkspaceNavigationPaneVisibility: Equatable, Sendable {
    let listsVisible: Bool
    let directoryVisible: Bool
}

/// A narrow SwiftUI/AppKit boundary for the two independently collapsible
/// navigation panes. SwiftUI owns pane content and the Inspector; AppKit owns
/// the semantic sidebar/content-list split items, dividers, and collapse
/// animations. The Reader remains mounted in one stable hosting controller.
struct AppKitWorkspaceNavigationSplitView<Lists: View, Directory: View, Reader: View>:
    NSViewControllerRepresentable
{
    @Binding var listsVisible: Bool
    @Binding var directoryVisible: Bool

    let reduceMotion: Bool
    let initialListsWidth: CGFloat
    let initialDirectoryWidth: CGFloat
    var widthDefaults: UserDefaults = MacWikiDefaults.current
    let listsRevision: String
    let directoryRevision: String
    let readerRevision: String
    let lists: Lists
    let directory: Directory
    let reader: Reader

    func makeCoordinator() -> Coordinator {
        Coordinator(
            listsVisible: $listsVisible,
            directoryVisible: $directoryVisible,
            listsRevision: listsRevision,
            directoryRevision: directoryRevision,
            readerRevision: readerRevision,
            lists: lists,
            directory: directory,
            reader: reader
        )
    }

    func makeNSViewController(context: Context) -> AppKitWorkspaceNavigationController {
        let controller = AppKitWorkspaceNavigationController(
            listsController: context.coordinator.listsController,
            directoryController: context.coordinator.directoryController,
            readerController: context.coordinator.readerController,
            initialListsWidth: initialListsWidth,
            initialDirectoryWidth: initialDirectoryWidth,
            widthDefaults: widthDefaults
        )
        controller.onPaneVisibilityChange = { [weak coordinator = context.coordinator] visibility in
            coordinator?.receiveNativeVisibility(visibility)
        }
        _ = controller.view
        controller.setPaneVisibility(
            listsVisible: listsVisible,
            directoryVisible: directoryVisible,
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
            directoryVisible: $directoryVisible
        )
        context.coordinator.updateContent(
            lists: lists,
            directory: directory,
            reader: reader,
            listsRevision: listsRevision,
            directoryRevision: directoryRevision,
            readerRevision: readerRevision
        )
        context.coordinator.requestVisibility(
            WorkspaceNavigationPaneVisibility(
                listsVisible: listsVisible,
                directoryVisible: directoryVisible
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

        private let listsBox: WorkspaceHostingBox<Lists>
        private let directoryBox: WorkspaceHostingBox<Directory>
        private let readerBox: WorkspaceHostingBox<Reader>
        private var listsVisibility: Binding<Bool>
        private var directoryVisibility: Binding<Bool>
        private var lastListsRevision: String
        private var lastDirectoryRevision: String
        private var lastReaderRevision: String
        private var lastRequestedVisibility: WorkspaceNavigationPaneVisibility
        private var contentUpdate: Task<Void, Never>?
        private var visibilityUpdate: Task<Void, Never>?
        private var nativeVisibilityUpdate: Task<Void, Never>?

        init(
            listsVisible: Binding<Bool>,
            directoryVisible: Binding<Bool>,
            listsRevision: String,
            directoryRevision: String,
            readerRevision: String,
            lists: Lists,
            directory: Directory,
            reader: Reader
        ) {
            listsVisibility = listsVisible
            directoryVisibility = directoryVisible
            lastListsRevision = listsRevision
            lastDirectoryRevision = directoryRevision
            lastReaderRevision = readerRevision
            lastRequestedVisibility = WorkspaceNavigationPaneVisibility(
                listsVisible: listsVisible.wrappedValue,
                directoryVisible: directoryVisible.wrappedValue
            )

            let listsBox = WorkspaceHostingBox(content: lists)
            let directoryBox = WorkspaceHostingBox(content: directory)
            let readerBox = WorkspaceHostingBox(content: reader)
            self.listsBox = listsBox
            self.directoryBox = directoryBox
            self.readerBox = readerBox
            listsController = NSHostingController(rootView: WorkspaceHostingRoot(box: listsBox))
            directoryController = NSHostingController(rootView: WorkspaceHostingRoot(box: directoryBox))
            readerController = NSHostingController(rootView: WorkspaceHostingRoot(box: readerBox))
            listsController.sizingOptions = []
            directoryController.sizingOptions = []
            readerController.sizingOptions = []
        }

        func updateBindings(
            listsVisible: Binding<Bool>,
            directoryVisible: Binding<Bool>
        ) {
            listsVisibility = listsVisible
            directoryVisibility = directoryVisible
        }

        func updateContent(
            lists: Lists,
            directory: Directory,
            reader: Reader,
            listsRevision: String,
            directoryRevision: String,
            readerRevision: String
        ) {
            let listsChanged = lastListsRevision != listsRevision
            let directoryChanged = lastDirectoryRevision != directoryRevision
            let readerChanged = lastReaderRevision != readerRevision
            guard listsChanged || directoryChanged || readerChanged else { return }

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

/// The single platform-owned navigation split. It deliberately excludes the
/// Inspector, which remains SwiftUI's standard window Inspector so AppKit and
/// SwiftUI never compete for the same trailing toolbar section.
@MainActor
final class AppKitWorkspaceNavigationController: NSSplitViewController {
    private enum WidthPersistence {
        static let restoreDelay = Duration.milliseconds(40)
        static let animatedRestoreDelay = Duration.milliseconds(240)
        static let persistenceDelay = Duration.milliseconds(350)
        static let tolerance: CGFloat = 1
    }

    private enum PaneLayout {
        /// Explicit pane restoration must never resize the window. The window
        /// owns its readable minimum; this split minimum only keeps the Reader
        /// mounted when both navigation panes are intentionally visible.
        static let emergencyReaderMinimum: CGFloat = 1
        static let auxiliaryHoldingPriority = NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1
        )
    }

    var onPaneVisibilityChange: ((WorkspaceNavigationPaneVisibility) -> Void)?

    private let listsItem: NSSplitViewItem
    private let directoryItem: NSSplitViewItem
    private let readerItem: NSSplitViewItem
    private let initialListsWidth: CGFloat
    private let initialDirectoryWidth: CGFloat
    private let widthDefaults: UserDefaults
    private var didRestoreListsWidth = false
    private var didRestoreDirectoryWidth = false
    private var requestedVisibility: WorkspaceNavigationPaneVisibility?
    private var lastReportedVisibility: WorkspaceNavigationPaneVisibility?
    private var visibilityTransitionGeneration = 0
    private var isApplyingRequestedVisibility = false
    private var pendingInitialWidthRestore: Task<Void, Never>?
    private var pendingWidthPersistence: Task<Void, Never>?

    init(
        listsController: NSViewController,
        directoryController: NSViewController,
        readerController: NSViewController,
        initialListsWidth: CGFloat,
        initialDirectoryWidth: CGFloat,
        widthDefaults: UserDefaults = MacWikiDefaults.current
    ) {
        listsItem = NSSplitViewItem(sidebarWithViewController: listsController)
        directoryItem = NSSplitViewItem(contentListWithViewController: directoryController)
        readerItem = NSSplitViewItem(viewController: readerController)
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
        listsItem.canCollapseFromWindowResize = false
        listsItem.allowsFullHeightLayout = true
        configureAuxiliaryCollapseBehavior(listsItem)

        configure(
            directoryItem,
            minimum: MainWindowColumnWidth.directoryRange.lowerBound,
            maximum: MainWindowColumnWidth.directoryRange.upperBound,
            holdingPriority: PaneLayout.auxiliaryHoldingPriority,
            canCollapse: true
        )
        directoryItem.canCollapseFromWindowResize = false
        configureAuxiliaryCollapseBehavior(directoryItem)

        configure(
            readerItem,
            minimum: PaneLayout.emergencyReaderMinimum,
            maximum: 10_000,
            holdingPriority: .defaultLow,
            canCollapse: false
        )

        addSplitViewItem(listsItem)
        addSplitViewItem(directoryItem)
        addSplitViewItem(readerItem)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scheduleInitialWidthRestore(after: WidthPersistence.restoreDelay)
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        reportUserDrivenVisibilityIfNeeded()
        scheduleWidthPersistence()
    }

    func setPaneVisibility(
        listsVisible: Bool,
        directoryVisible: Bool,
        animated: Bool
    ) {
        let target = WorkspaceNavigationPaneVisibility(
            listsVisible: listsVisible,
            directoryVisible: directoryVisible
        )
        requestedVisibility = target
        visibilityTransitionGeneration &+= 1
        let generation = visibilityTransitionGeneration

        let listsChanged = listsItem.isCollapsed == listsVisible
        let directoryChanged = directoryItem.isCollapsed == directoryVisible
        guard listsChanged || directoryChanged else {
            isApplyingRequestedVisibility = false
            lastReportedVisibility = target
            scheduleInitialWidthRestore(after: WidthPersistence.restoreDelay)
            return
        }

        isApplyingRequestedVisibility = true
        let apply = {
            if listsChanged {
                self.listsItem.isCollapsed = !listsVisible
            }
            if directoryChanged {
                self.directoryItem.isCollapsed = !directoryVisible
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
                listsItem.animator().isCollapsed = !listsVisible
            }
            if directoryChanged {
                directoryItem.animator().isCollapsed = !directoryVisible
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
    }

    private var currentVisibility: WorkspaceNavigationPaneVisibility {
        WorkspaceNavigationPaneVisibility(
            listsVisible: !listsItem.isCollapsed,
            directoryVisible: !directoryItem.isCollapsed
        )
    }

    private func finishVisibilityUpdate(generation: Int, animated: Bool) {
        guard visibilityTransitionGeneration == generation else { return }
        isApplyingRequestedVisibility = false
        lastReportedVisibility = currentVisibility
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
        let visibleAuxiliaryCount = [
            visibility.listsVisible,
            visibility.directoryVisible
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

        if shouldRestoreLists {
            listsItem.minimumThickness = initialListsWidth
            listsItem.maximumThickness = initialListsWidth
        }
        if shouldRestoreDirectory {
            directoryItem.minimumThickness = initialDirectoryWidth
            directoryItem.maximumThickness = initialDirectoryWidth
        }
        if shouldRestoreLists || shouldRestoreDirectory {
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
    }

    private func reportUserDrivenVisibilityIfNeeded() {
        guard !isApplyingRequestedVisibility else { return }
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
                || (!directoryItem.isCollapsed && !didRestoreDirectoryWidth) else {
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
            inspectorVisible: false
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
