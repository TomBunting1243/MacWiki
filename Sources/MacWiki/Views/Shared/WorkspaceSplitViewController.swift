import AppKit

struct WorkspacePaneVisibility: Equatable, Sendable {
    let sidebarVisible: Bool
    let directoryVisible: Bool
    let inspectorVisible: Bool
}

/// The main window's single native split hierarchy. Semantic split-item
/// behaviors let AppKit own full-height sidebar/inspector layout and standard
/// collapse interactions while the reader controller remains mounted.
@MainActor
final class WorkspaceSplitViewController: NSSplitViewController {
    private enum WidthPersistence {
        static let restoreDelay = Duration.milliseconds(40)
        static let animatedRestoreDelay = Duration.milliseconds(240)
        static let persistenceDelay = Duration.milliseconds(350)
        static let tolerance: CGFloat = 1
    }

    private enum PaneLayout {
        /// The window-level content minimum preserves the normal 520-point
        /// reading surface. This emergency split minimum prevents AppKit from
        /// resizing an already-narrow window when the user restores a pane.
        static let emergencyReaderMinimum: CGFloat = 1
        static let auxiliaryHoldingPriority = NSLayoutConstraint.Priority(
            rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1
        )
    }

    var onPaneVisibilityChange: ((WorkspacePaneVisibility) -> Void)?

    private let sidebarItem: NSSplitViewItem
    private let directoryItem: NSSplitViewItem
    private let readerItem: NSSplitViewItem
    private let inspectorItem: NSSplitViewItem
    private let initialSidebarWidth: CGFloat
    private let initialDirectoryWidth: CGFloat
    private let initialInspectorWidth: CGFloat
    private let widthDefaults: UserDefaults
    private var didRestoreSidebarWidth = false
    private var didRestoreDirectoryWidth = false
    private var didRestoreInspectorWidth = false
    private var desiredVisibility: WorkspacePaneVisibility?
    private var appliedVisibility: WorkspacePaneVisibility?
    private var lastReportedVisibility: WorkspacePaneVisibility?
    private var visibilityTransitionGeneration = 0
    private var activeVisibilityAnimationGenerations: Set<Int> = []
    private var isApplyingRequestedVisibility = false
    private var pendingInitialWidthRestore: Task<Void, Never>?
    private var pendingWidthPersistence: Task<Void, Never>?
    private var readerToolbarController: ReaderToolbarController?

    init(
        sidebarController: NSViewController,
        directoryController: NSViewController,
        readerController: NSViewController,
        inspectorController: NSViewController,
        initialSidebarWidth: CGFloat,
        initialDirectoryWidth: CGFloat,
        initialInspectorWidth: CGFloat,
        widthDefaults: UserDefaults = MacWikiDefaults.current
    ) {
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        directoryItem = NSSplitViewItem(contentListWithViewController: directoryController)
        readerItem = NSSplitViewItem(viewController: readerController)
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorController)
        self.initialSidebarWidth = Self.clampedInitialWidth(
            initialSidebarWidth,
            range: MainWindowColumnWidth.sidebarRange,
            fallback: AppStorageKey.MainWindow.sidebarWidthDefault
        )
        self.initialDirectoryWidth = Self.clampedInitialWidth(
            initialDirectoryWidth,
            range: MainWindowColumnWidth.directoryRange,
            fallback: AppStorageKey.MainWindow.directoryWidthDefault
        )
        self.initialInspectorWidth = Self.clampedInitialWidth(
            initialInspectorWidth,
            range: MainWindowColumnWidth.inspectorRange,
            fallback: AppStorageKey.MainWindow.inspectorWidthDefault
        )
        self.widthDefaults = widthDefaults
        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        configureAuxiliaryItem(
            sidebarItem,
            minimum: MainWindowColumnWidth.sidebarRange.lowerBound,
            maximum: MainWindowColumnWidth.sidebarRange.upperBound
        )
        configureAuxiliaryItem(
            directoryItem,
            minimum: MainWindowColumnWidth.directoryRange.lowerBound,
            maximum: MainWindowColumnWidth.directoryRange.upperBound
        )
        configure(
            readerItem,
            minimum: PaneLayout.emergencyReaderMinimum,
            maximum: 10_000,
            holdingPriority: .defaultLow,
            canCollapse: false
        )
        configureAuxiliaryItem(
            inspectorItem,
            minimum: MainWindowColumnWidth.inspectorRange.lowerBound,
            maximum: MainWindowColumnWidth.inspectorRange.upperBound
        )

        // Keep explicit user collapse available without letting a window resize
        // silently rewrite the command-driven visibility model.
        sidebarItem.canCollapseFromWindowResize = false
        directoryItem.canCollapseFromWindowResize = false
        inspectorItem.canCollapseFromWindowResize = false
        sidebarItem.allowsFullHeightLayout = true
        inspectorItem.allowsFullHeightLayout = true

        addSplitViewItem(sidebarItem)
        addSplitViewItem(directoryItem)
        addSplitViewItem(readerItem)
        addSplitViewItem(inspectorItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pendingInitialWidthRestore?.cancel()
        pendingWidthPersistence?.cancel()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scheduleInitialWidthRestore(after: WidthPersistence.restoreDelay)
        readerToolbarController?.installIfPossible()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        readerToolbarController?.installIfPossible()
    }

    func configureReaderToolbar(environment: ReaderToolbarEnvironment) {
        if let readerToolbarController {
            readerToolbarController.update(environment: environment)
        } else {
            readerToolbarController = ReaderToolbarController(
                splitController: self,
                environment: environment
            )
        }
        readerToolbarController?.installIfPossible()
    }

    func invalidateReaderToolbar() {
        readerToolbarController?.invalidate()
        readerToolbarController = nil
    }

    /// Reserved for reader-scoped native chrome. Keeping the accessory owned by
    /// the semantic reader item lets a later toolbar pass move controls without
    /// changing this four-pane hierarchy or replacing the reader host.
    func setReaderTopAccessoryViewControllers(
        _ controllers: [NSSplitViewItemAccessoryViewController]
    ) {
        let current = readerItem.topAlignedAccessoryViewControllers
        guard current.count != controllers.count
                || zip(current, controllers).contains(where: { pair in pair.0 !== pair.1 }) else {
            return
        }
        readerItem.topAlignedAccessoryViewControllers = controllers
    }

    func setPaneVisibility(
        sidebarVisible: Bool,
        directoryVisible: Bool,
        inspectorVisible: Bool,
        animated: Bool
    ) {
        let target = WorkspacePaneVisibility(
            sidebarVisible: sidebarVisible,
            directoryVisible: directoryVisible,
            inspectorVisible: inspectorVisible
        )
        if !isApplyingRequestedVisibility, appliedVisibility == target {
            return
        }
        let previousDesiredVisibility = desiredVisibility ?? currentVisibility
        if isApplyingRequestedVisibility, previousDesiredVisibility == target {
            return
        }

        desiredVisibility = target
        visibilityTransitionGeneration &+= 1
        let generation = visibilityTransitionGeneration

        let currentVisibility = currentVisibility
        let sidebarChanged = currentVisibility.sidebarVisible != sidebarVisible
            || previousDesiredVisibility.sidebarVisible != sidebarVisible
        let directoryChanged = currentVisibility.directoryVisible != directoryVisible
            || previousDesiredVisibility.directoryVisible != directoryVisible
        let inspectorChanged = currentVisibility.inspectorVisible != inspectorVisible
            || previousDesiredVisibility.inspectorVisible != inspectorVisible
        let visibilityChanged = sidebarChanged || directoryChanged || inspectorChanged

        guard visibilityChanged else {
            appliedVisibility = target
            isApplyingRequestedVisibility = !activeVisibilityAnimationGenerations.isEmpty
            lastReportedVisibility = target
            scheduleInitialWidthRestore(after: WidthPersistence.restoreDelay)
            return
        }

        isApplyingRequestedVisibility = true
        let applyTarget = {
            if sidebarChanged {
                self.sidebarItem.isCollapsed = !sidebarVisible
            }
            if directoryChanged {
                self.directoryItem.isCollapsed = !directoryVisible
            }
            if inspectorChanged {
                self.inspectorItem.isCollapsed = !inspectorVisible
            }
        }

        guard animated, view.window != nil else {
            applyTarget()
            if activeVisibilityAnimationGenerations.isEmpty {
                finishVisibilityTransition(generation: generation, animated: false)
            }
            return
        }

        activeVisibilityAnimationGenerations.insert(generation)
        let isRetargetingActiveTransition = !activeVisibilityAnimationGenerations
            .subtracting([generation])
            .isEmpty
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isRetargetingActiveTransition ? 0.10 : 0.18
            context.allowsImplicitAnimation = true
            if sidebarChanged {
                sidebarItem.animator().isCollapsed = !sidebarVisible
            }
            if directoryChanged {
                directoryItem.animator().isCollapsed = !directoryVisible
            }
            if inspectorChanged {
                inspectorItem.animator().isCollapsed = !inspectorVisible
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.completeVisibilityAnimation(generation: generation)
            }
        }
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        reportUserDrivenVisibilityIfNeeded()

        pendingWidthPersistence?.cancel()
        pendingWidthPersistence = Task { @MainActor [weak self] in
            try? await Task.sleep(for: WidthPersistence.persistenceDelay)
            guard let self, !Task.isCancelled else { return }
            persistVisibleAuxiliaryWidths()
        }
    }

    func restoreInitialVisibleWidthsIfFeasible() {
        let splitWidth = splitView.bounds.width
        let visibility = currentVisibility
        let visibleAuxiliaryWidth = (visibility.sidebarVisible ? initialSidebarWidth : 0)
            + (visibility.directoryVisible ? initialDirectoryWidth : 0)
            + (visibility.inspectorVisible ? initialInspectorWidth : 0)
        let visibleAuxiliaryCount = [
            visibility.sidebarVisible,
            visibility.directoryVisible,
            visibility.inspectorVisible
        ].filter { $0 }.count
        let requiredWidth = MainWindowLayout.minimumReaderWidth
            + visibleAuxiliaryWidth
            + (CGFloat(visibleAuxiliaryCount) * splitView.dividerThickness)
        guard splitWidth.isFinite,
              splitWidth >= requiredWidth else {
            establishAdaptiveWidthBaselineIfValid(visibility: visibility)
            return
        }

        if visibility.sidebarVisible, !didRestoreSidebarWidth {
            splitView.setPosition(initialSidebarWidth, ofDividerAt: 0)
            splitView.layoutSubtreeIfNeeded()
            didRestoreSidebarWidth = Self.matches(
                sidebarItem.viewController.view.bounds.width,
                initialSidebarWidth
            )
        }

        if visibility.directoryVisible, !didRestoreDirectoryWidth {
            let directoryLeadingEdge = directoryItem.viewController.view.convert(
                .zero,
                to: splitView
            ).x
            splitView.setPosition(
                directoryLeadingEdge + initialDirectoryWidth,
                ofDividerAt: 1
            )
            splitView.layoutSubtreeIfNeeded()
            didRestoreDirectoryWidth = Self.matches(
                directoryItem.viewController.view.bounds.width,
                initialDirectoryWidth
            )
        }

        if visibility.inspectorVisible, !didRestoreInspectorWidth {
            splitView.setPosition(splitWidth - initialInspectorWidth, ofDividerAt: 2)
            splitView.layoutSubtreeIfNeeded()
            didRestoreInspectorWidth = Self.matches(
                inspectorItem.viewController.view.bounds.width,
                initialInspectorWidth
            )
        }
    }

    private var currentVisibility: WorkspacePaneVisibility {
        WorkspacePaneVisibility(
            sidebarVisible: !sidebarItem.isCollapsed,
            directoryVisible: !directoryItem.isCollapsed,
            inspectorVisible: !inspectorItem.isCollapsed
        )
    }

    private static func clampedInitialWidth(
        _ width: CGFloat,
        range: ClosedRange<CGFloat>,
        fallback: Double
    ) -> CGFloat {
        CGFloat(
            MainWindowColumnWidth.clampedStorageValue(width, range: range)
                ?? fallback
        )
    }

    private static func matches(_ width: CGFloat, _ expected: CGFloat) -> Bool {
        abs(width - expected) < WidthPersistence.tolerance
    }

    /// When stored external-display widths cannot coexist with the readable
    /// reader minimum, AppKit lays out a valid adaptive set of pane widths.
    /// Treat those post-layout widths as the new persistence baseline so
    /// divider edits on the narrower display are not silently discarded.
    private func establishAdaptiveWidthBaselineIfValid(
        visibility: WorkspacePaneVisibility
    ) {
        let minimumAdaptiveWidth = MainWindowLayout.minimumContentWidth(
            listsSidebarVisible: visibility.sidebarVisible,
            directoryVisible: visibility.directoryVisible,
            inspectorVisible: visibility.inspectorVisible
        )
        guard splitView.bounds.width >= minimumAdaptiveWidth else { return }

        if visibility.sidebarVisible,
           Self.isPersistable(
               sidebarItem.viewController.view.bounds.width,
               in: MainWindowColumnWidth.sidebarRange
           ) {
            didRestoreSidebarWidth = true
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

    private static func isPersistable(
        _ width: CGFloat,
        in range: ClosedRange<CGFloat>
    ) -> Bool {
        width.isFinite
            && width >= range.lowerBound - WidthPersistence.tolerance
            && width <= range.upperBound + WidthPersistence.tolerance
    }

    private func configureAuxiliaryItem(
        _ item: NSSplitViewItem,
        minimum: CGFloat,
        maximum: CGFloat
    ) {
        configure(
            item,
            minimum: minimum,
            maximum: maximum,
            holdingPriority: PaneLayout.auxiliaryHoldingPriority,
            canCollapse: true
        )
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

    private func finishVisibilityTransition(generation: Int, animated: Bool) {
        guard visibilityTransitionGeneration == generation else { return }
        if let desiredVisibility, currentVisibility != desiredVisibility {
            sidebarItem.isCollapsed = !desiredVisibility.sidebarVisible
            directoryItem.isCollapsed = !desiredVisibility.directoryVisible
            inspectorItem.isCollapsed = !desiredVisibility.inspectorVisible
            splitView.layoutSubtreeIfNeeded()
        }
        isApplyingRequestedVisibility = false
        appliedVisibility = currentVisibility
        lastReportedVisibility = appliedVisibility
        scheduleInitialWidthRestore(
            after: animated
                ? WidthPersistence.animatedRestoreDelay
                : WidthPersistence.restoreDelay,
            replacingPending: true
        )
    }

    private func completeVisibilityAnimation(generation: Int) {
        activeVisibilityAnimationGenerations.remove(generation)
        guard activeVisibilityAnimationGenerations.isEmpty else { return }
        finishVisibilityTransition(
            generation: visibilityTransitionGeneration,
            animated: true
        )
    }

    private func reportUserDrivenVisibilityIfNeeded() {
        guard !isApplyingRequestedVisibility else { return }
        let visibility = currentVisibility
        guard visibility != desiredVisibility else {
            appliedVisibility = visibility
            lastReportedVisibility = visibility
            return
        }
        desiredVisibility = visibility
        appliedVisibility = visibility
        guard visibility != lastReportedVisibility else { return }
        lastReportedVisibility = visibility
        onPaneVisibilityChange?(visibility)
    }

    private func scheduleInitialWidthRestore(
        after delay: Duration,
        replacingPending: Bool = false
    ) {
        guard (!sidebarItem.isCollapsed && !didRestoreSidebarWidth)
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

    private func persistVisibleAuxiliaryWidths() {
        persistWidth(
            of: sidebarItem,
            didRestoreInitialWidth: didRestoreSidebarWidth,
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
}
