import SwiftUI
import AppKit
import SwiftData

struct AppKitMainSplitView: NSViewControllerRepresentable {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?

    let tabBarLiquidGlass: Bool
    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    func makeNSViewController(context: Context) -> MainWindowSplitViewController {
        let controller = MainWindowSplitViewController()
        controller.update(configuration: configuration)
        return controller
    }

    func updateNSViewController(_ controller: MainWindowSplitViewController, context: Context) {
        controller.update(configuration: configuration)
    }

    private var configuration: MainWindowSplitViewController.Configuration {
        MainWindowSplitViewController.Configuration(
            appState: appState,
            modelContext: modelContext,
            listsRootView: AnyView(
                ListsColumnView(
                    selectedList: $selectedList,
                    selectedLabel: $selectedLabel,
                    selectedTag: $selectedTag,
                    rootSelection: $rootSelection,
                    onEditLabel: onEditLabel,
                    onAddNewLabel: onAddNewLabel
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
            ),
            directoryRootView: AnyView(
                DirectoryColumnView(
                    selectedList: $selectedList,
                    rootSelection: $rootSelection,
                    selectedLabel: selectedLabel,
                    selectedTag: selectedTag,
                    onNewLabelWithArticle: onNewLabelWithArticle,
                    onNewTagWithArticle: onNewTagWithArticle
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
            ),
            readerRootView: AnyView(
                ReaderColumnView(
                    tabBarLiquidGlass: tabBarLiquidGlass,
                    onNewLabelWithArticle: onNewLabelWithArticle
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
            ),
            inspectorRootView: AnyView(
                InspectorColumnView(
                    showNewLabelSheet: $showNewLabelSheet,
                    articleForNewLabel: $articleForNewLabel
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
            ),
            sidebarColumnVisible: appState.listsSidebarVisible,
            directoryColumnVisible: appState.directoryColumnVisible,
            inspectorVisible: appState.inspectorVisible && !appState.isFocusModeEnabled,
            animateTransitions: !reduceMotion,
            navigationToggleAllowed: !appState.isWikiHopNavigationLocked && !appState.isFocusModeEnabled,
            inspectorToggleAllowed: !appState.isFocusModeEnabled,
            onSidebarColumnVisibilityChange: { isVisible in
                guard appState.listsSidebarVisible != isVisible else { return }
                appState.listsSidebarVisible = isVisible
            },
            onDirectoryColumnVisibilityChange: { isVisible in
                guard appState.directoryColumnVisible != isVisible else { return }
                appState.directoryColumnVisible = isVisible
            },
            onInspectorVisibilityChange: { isVisible in
                guard appState.inspectorVisible != isVisible else { return }
                appState.inspectorVisible = isVisible
            }
        )
    }
}

@MainActor
final class MainWindowSplitViewController: NSSplitViewController, NSToolbarDelegate, NSToolbarItemValidation, NSSharingServicePickerToolbarItemDelegate {
    private enum ToolbarAnchor {
        static let inspectorBoundary = MainWindowToolbarItemID.more
    }

    private enum PersistedWidthKey {
        static let sidebar = "mainWindow.sidebarWidth"
        static let directory = "mainWindow.directoryWidth"
        static let inspector = "mainWindow.inspectorWidth"
    }

    struct Configuration {
        let appState: AppState
        let modelContext: ModelContext
        let listsRootView: AnyView
        let directoryRootView: AnyView
        let readerRootView: AnyView
        let inspectorRootView: AnyView
        let sidebarColumnVisible: Bool
        let directoryColumnVisible: Bool
        let inspectorVisible: Bool
        let animateTransitions: Bool
        let navigationToggleAllowed: Bool
        let inspectorToggleAllowed: Bool
        let onSidebarColumnVisibilityChange: (Bool) -> Void
        let onDirectoryColumnVisibilityChange: (Bool) -> Void
        let onInspectorVisibilityChange: (Bool) -> Void
    }

    private let listsHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let directoryHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let readerHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let inspectorHostingController = NSHostingController(rootView: AnyView(EmptyView()))

    private lazy var sidebarItem = NSSplitViewItem(sidebarWithViewController: listsHostingController)
    private lazy var directoryItem = NSSplitViewItem(contentListWithViewController: directoryHostingController)
    private lazy var readerItem = NSSplitViewItem(viewController: readerHostingController)
    private lazy var inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHostingController)

    private lazy var windowToolbar: NSToolbar = {
        let toolbar = NSToolbar(identifier: MainWindowToolbarItemID.toolbar)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        toolbar.centeredItemIdentifier = MainWindowToolbarItemID.principalTitle
        return toolbar
    }()

    private let titleToolbarLabel: NSTextField = {
        let label = NSTextField(labelWithString: "MacWiki")
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.backgroundColor = .clear
        label.textColor = .labelColor
        return label
    }()

    private let savePopover = NSPopover()
    private let readerStylePopover = NSPopover()
    private let pageViewsPopover = NSPopover()
    private var currentConfiguration: Configuration?
    private var lastPublishedSidebarColumnVisible: Bool?
    private var lastPublishedDirectoryColumnVisible: Bool?
    private var lastPublishedInspectorVisible: Bool?
    private var hasRestoredInitialDividerPositions = false

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        prepareSplitViewController()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        prepareSplitViewController()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.dividerStyle = .thin
        splitView.delegate = self
        savePopover.behavior = .transient
        readerStylePopover.behavior = .transient
        pageViewsPopover.behavior = .transient
        updateSplitViewChrome()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureWindowChrome()
        synchronizeToolbarTrackingSeparatorsIfNeeded()
        refreshToolbarContent()
        restoreDividerPositionsIfNeeded()
    }

    func update(configuration: Configuration) {
        currentConfiguration = configuration

        listsHostingController.rootView = configuration.listsRootView
        directoryHostingController.rootView = configuration.directoryRootView
        readerHostingController.rootView = configuration.readerRootView
        inspectorHostingController.rootView = configuration.inspectorRootView

        if sidebarItem.isCollapsed != !configuration.sidebarColumnVisible ||
            directoryItem.isCollapsed != !configuration.directoryColumnVisible ||
            inspectorItem.isCollapsed != !configuration.inspectorVisible {
            applyCollapsedState(
                sidebarColumnVisible: configuration.sidebarColumnVisible,
                directoryColumnVisible: configuration.directoryColumnVisible,
                inspectorVisible: configuration.inspectorVisible,
                animated: configuration.animateTransitions
            )
        }

        publishChromeVisibilityStateIfNeeded()
        configureWindowChrome()
        refreshToolbarContent()
        synchronizeToolbarTrackingSeparatorsIfNeeded()
        updateSplitViewChrome()
    }

    private func configureSplitItems() {
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 240
        sidebarItem.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
        sidebarItem.automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .automatic

        directoryItem.canCollapse = false
        directoryItem.canCollapseFromWindowResize = false
        directoryItem.minimumThickness = 260
        directoryItem.maximumThickness = 420
        directoryItem.automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension
        directoryItem.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
        directoryItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        directoryItem.holdingPriority = NSLayoutConstraint.Priority(255)
        directoryItem.titlebarSeparatorStyle = .automatic

        readerItem.canCollapse = false
        readerItem.holdingPriority = NSLayoutConstraint.Priority(200)
        if #available(macOS 26, *) {
            readerItem.automaticallyAdjustsSafeAreaInsets = true
        }

        inspectorItem.canCollapse = true
        inspectorItem.canCollapseFromWindowResize = false
        inspectorItem.minimumThickness = 260
        inspectorItem.maximumThickness = 340
        inspectorItem.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
        inspectorItem.automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension
        inspectorItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        inspectorItem.holdingPriority = NSLayoutConstraint.Priority(260)
        inspectorItem.titlebarSeparatorStyle = .automatic
    }

    private func prepareSplitViewController() {
        let splitView = MainWindowChromeSplitView(frame: .zero)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        self.splitView = splitView

        configureSplitItems()
        splitViewItems = [sidebarItem, directoryItem, readerItem, inspectorItem]
        updateSplitViewChrome()
    }

    private func applyCollapsedState(
        sidebarColumnVisible: Bool,
        directoryColumnVisible: Bool,
        inspectorVisible: Bool,
        animated: Bool
    ) {
        let applyChanges = {
            self.sidebarItem.isCollapsed = !sidebarColumnVisible
            self.directoryItem.isCollapsed = !directoryColumnVisible
            self.inspectorItem.isCollapsed = !inspectorVisible
        }

        guard animated else {
            applyChanges()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.sidebarItem.animator().isCollapsed = !sidebarColumnVisible
            self.directoryItem.animator().isCollapsed = !directoryColumnVisible
            self.inspectorItem.animator().isCollapsed = !inspectorVisible
        }

    }

    override func toggleSidebar(_ sender: Any?) {
        guard let configuration = currentConfiguration else { return }

        applyCollapsedState(
            sidebarColumnVisible: sidebarItem.isCollapsed,
            directoryColumnVisible: !directoryItem.isCollapsed,
            inspectorVisible: !inspectorItem.isCollapsed,
            animated: configuration.animateTransitions
        )
        publishChromeVisibilityStateIfNeeded()
        synchronizeToolbarTrackingSeparatorsIfNeeded()
    }

    override func toggleInspector(_ sender: Any?) {
        guard let configuration = currentConfiguration else { return }

        let shouldShowInspector = inspectorItem.isCollapsed
        applyCollapsedState(
            sidebarColumnVisible: !sidebarItem.isCollapsed,
            directoryColumnVisible: !directoryItem.isCollapsed,
            inspectorVisible: shouldShowInspector,
            animated: configuration.animateTransitions
        )
        publishChromeVisibilityStateIfNeeded()
        synchronizeToolbarTrackingSeparatorsIfNeeded()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleSidebar(_:)) {
            let isAllowed = currentConfiguration?.navigationToggleAllowed ?? true
            return isAllowed
        }

        if item.action == #selector(toggleInspector(_:)) {
            let isAllowed = currentConfiguration?.inspectorToggleAllowed ?? true
            return isAllowed
        }

        return super.validateUserInterfaceItem(item)
    }
    private func publishChromeVisibilityStateIfNeeded() {
        guard let configuration = currentConfiguration else { return }

        let sidebarColumnVisible = !sidebarItem.isCollapsed
        if lastPublishedSidebarColumnVisible != sidebarColumnVisible {
            lastPublishedSidebarColumnVisible = sidebarColumnVisible
            configuration.onSidebarColumnVisibilityChange(sidebarColumnVisible)
        }

        let directoryColumnVisible = !directoryItem.isCollapsed
        if lastPublishedDirectoryColumnVisible != directoryColumnVisible {
            lastPublishedDirectoryColumnVisible = directoryColumnVisible
            configuration.onDirectoryColumnVisibilityChange(directoryColumnVisible)
        }

        let inspectorVisible = !inspectorItem.isCollapsed
        if lastPublishedInspectorVisible != inspectorVisible {
            lastPublishedInspectorVisible = inspectorVisible
            configuration.onInspectorVisibilityChange(inspectorVisible)
        }
    }

    private var currentTab: ArticleTab? {
        guard let configuration = currentConfiguration,
              let activeID = configuration.appState.activeTabId else {
            return nil
        }

        return configuration.appState.openTabs.first(where: { $0.id == activeID })
    }

    private var currentArticle: Article? {
        currentConfiguration?.appState.currentArticle
    }

    private func configureWindowChrome() {
        guard let window = view.window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
    }

    private func refreshToolbarContent() {
        guard currentConfiguration != nil else { return }

        titleToolbarLabel.stringValue = MainWindowToolbarTitleResolver.title(
            currentTab: currentTab,
            currentArticle: currentArticle
        )

        updateDynamicToolbarItems()
        windowToolbar.validateVisibleItems()
    }

    private func updateDynamicToolbarItems() {
        if let markReadItem = windowToolbar.items.first(where: { $0.itemIdentifier == MainWindowToolbarItemID.markRead }) {
            let isRead = currentArticle?.isRead == true
            markReadItem.label = isRead ? "Mark as Unread" : "Mark as Read"
            markReadItem.toolTip = markReadItem.label
            markReadItem.image = NSImage(
                systemSymbolName: isRead ? "checkmark.circle.fill" : "circle",
                accessibilityDescription: markReadItem.label
            )
        }

        if let moreItem = windowToolbar.items.first(where: { $0.itemIdentifier == MainWindowToolbarItemID.more }) as? NSMenuToolbarItem {
            moreItem.menu = makeMoreMenu()
        }
    }

    private func toolbarItemView(for identifier: NSToolbarItem.Identifier) -> NSView? {
        guard let item = windowToolbar.items.first(where: { $0.itemIdentifier == identifier }) else {
            return nil
        }

        if let view = item.view {
            return view
        }

        return item.value(forKey: "view") as? NSView
    }

    private func presentPopover(
        _ popover: NSPopover,
        identifier: NSToolbarItem.Identifier,
        size: CGSize,
        @ViewBuilder content: () -> some View
    ) {
        guard let configuration = currentConfiguration,
              let anchorView = toolbarItemView(for: identifier) else {
            return
        }

        popover.contentSize = size
        popover.contentViewController = NSHostingController(
            rootView: AnyView(
                content()
                    .environment(configuration.appState)
                    .environment(\.modelContext, configuration.modelContext)
            )
        )
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
    }

    private func makeMenuToolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        menu: NSMenu
    ) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.menu = menu
        item.showsIndicator = true
        return item
    }

    private func makeMoreMenu() -> NSMenu {
        let menu = NSMenu(title: "More")

        let openItem = NSMenuItem(
            title: "Open in Browser",
            action: #selector(openCurrentArticleInBrowser(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: openItem.title)
        openItem.isEnabled = currentArticle != nil
        menu.addItem(openItem)

        let pageViewsItem = NSMenuItem(
            title: "Show Page Views",
            action: #selector(showPageViewsPopover(_:)),
            keyEquivalent: ""
        )
        pageViewsItem.target = self
        pageViewsItem.image = NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: pageViewsItem.title)
        pageViewsItem.isEnabled = currentArticle != nil
        menu.addItem(pageViewsItem)

        menu.addItem(.separator())

        let focusEnabled = currentConfiguration?.appState.isFocusModeEnabled == true
        let focusItem = NSMenuItem(
            title: focusEnabled ? "Exit Focus Mode" : "Enter Focus Mode",
            action: #selector(toggleFocusMode(_:)),
            keyEquivalent: ""
        )
        focusItem.target = self
        focusItem.image = NSImage(
            systemSymbolName: focusEnabled ? "viewfinder.circle.fill" : "viewfinder.circle",
            accessibilityDescription: focusItem.title
        )
        focusItem.isEnabled = currentArticle != nil && currentConfiguration?.appState.isWikiHopNavigationLocked != true
        menu.addItem(focusItem)

        return menu
    }

    private func synchronizeToolbarTrackingSeparatorsIfNeeded() {
        guard view.window?.toolbar === windowToolbar else { return }

        synchronizeTrackingSeparator(
            toolbar: windowToolbar,
            identifier: .sidebarTrackingSeparator,
            after: nil,
            dividerIndex: leadingTrackingSeparatorDividerIndex()
        )

        synchronizeTrackingSeparator(
            toolbar: windowToolbar,
            identifier: .inspectorTrackingSeparator,
            after: ToolbarAnchor.inspectorBoundary,
            dividerIndex: dividerIndex(before: inspectorItem)
        )
    }

    private func leadingTrackingSeparatorDividerIndex() -> Int? {
        if !sidebarItem.isCollapsed {
            return dividerIndex(after: sidebarItem)
        }

        if !directoryItem.isCollapsed {
            return dividerIndex(after: directoryItem)
        }

        return nil
    }

    private func dividerIndex(after item: NSSplitViewItem) -> Int? {
        let visibleItems = splitViewItems.filter { !$0.isCollapsed }
        guard let visibleIndex = visibleItems.firstIndex(where: { $0 === item }),
              visibleIndex < visibleItems.count - 1 else {
            return nil
        }

        return visibleIndex
    }

    private func dividerIndex(before item: NSSplitViewItem) -> Int? {
        let visibleItems = splitViewItems.filter { !$0.isCollapsed }
        guard let visibleIndex = visibleItems.firstIndex(where: { $0 === item }),
              visibleIndex > 0 else {
            return nil
        }

        return visibleIndex - 1
    }

    private func synchronizeTrackingSeparator(
        toolbar: NSToolbar,
        identifier: NSToolbarItem.Identifier,
        after anchor: NSToolbarItem.Identifier?,
        dividerIndex: Int?
    ) {
        let existingIndex = toolbar.items.firstIndex { $0.itemIdentifier == identifier }

        guard let dividerIndex else {
            if let existingIndex {
                toolbar.removeItem(at: existingIndex)
            }
            return
        }

        let desiredIndex: Int
        if let anchor,
           let anchorIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == anchor }) {
            desiredIndex = anchorIndex + 1
        } else {
            desiredIndex = 0
        }

        if let existingIndex, existingIndex != desiredIndex {
            toolbar.removeItem(at: existingIndex)
            let adjustedIndex = min(
                max(0, existingIndex < desiredIndex ? desiredIndex - 1 : desiredIndex),
                toolbar.items.count
            )
            toolbar.insertItem(withItemIdentifier: identifier, at: adjustedIndex)
        } else if existingIndex == nil {
            toolbar.insertItem(withItemIdentifier: identifier, at: min(desiredIndex, toolbar.items.count))
        }

        guard let trackingItem = toolbar.items.first(where: { $0.itemIdentifier == identifier }) as? NSTrackingSeparatorToolbarItem else {
            return
        }

        trackingItem.splitView = splitView
        trackingItem.dividerIndex = dividerIndex
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        persistCurrentVisibleColumnWidths()
        publishChromeVisibilityStateIfNeeded()
        updateSplitViewChrome()
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        let visibleItems = splitViewItems.filter { !$0.isCollapsed }
        guard dividerIndex >= 0, dividerIndex + 1 < visibleItems.count, dividerIndex + 1 < splitView.subviews.count else {
            return proposedPosition
        }

        let leftView = splitView.subviews[dividerIndex]
        let rightView = splitView.subviews[dividerIndex + 1]
        let leftItem = visibleItems[dividerIndex]
        let rightItem = visibleItems[dividerIndex + 1]

        let currentDividerOrigin = leftView.frame.maxX
        let currentLeftWidth = leftView.frame.width
        let currentRightWidth = rightView.frame.width
        let proposedDelta = proposedPosition - currentDividerOrigin

        let minimumDelta = max(
            resolvedMinimumThickness(for: leftItem) - currentLeftWidth,
            currentRightWidth - resolvedMaximumThickness(for: rightItem)
        )
        let maximumDelta = min(
            resolvedMaximumThickness(for: leftItem) - currentLeftWidth,
            currentRightWidth - resolvedMinimumThickness(for: rightItem)
        )

        let clampedDelta = min(max(proposedDelta, minimumDelta), maximumDelta)
        return currentDividerOrigin + clampedDelta
    }

    override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    private func updateSplitViewChrome() {
        guard let splitView = splitView as? MainWindowChromeSplitView else { return }
        splitView.visuallyHiddenDividerIndexes = resolvedVisuallyHiddenDividerIndexes()
        splitView.needsDisplay = true
        splitView.window?.invalidateCursorRects(for: splitView)
    }


    private func resolvedVisuallyHiddenDividerIndexes() -> Set<Int> {
        guard !sidebarItem.isCollapsed,
              !directoryItem.isCollapsed,
              let directoryLeadingDividerIndex = dividerIndex(before: directoryItem) else {
            return []
        }

        return [directoryLeadingDividerIndex]
    }

    private func restoreDividerPositionsIfNeeded(force: Bool = false) {
        guard force || !hasRestoredInitialDividerPositions else { return }
        guard splitView.bounds.width > 0 else { return }

        let visibleItems = splitViewItems.filter { !$0.isCollapsed }
        guard visibleItems.count >= 2 else { return }

        let dividerThickness = splitView.dividerThickness
        let defaults = UserDefaults.standard

        let sidebarWidth = clampedWidth(
            defaults.object(forKey: PersistedWidthKey.sidebar) as? Double,
            defaultWidth: 208,
            minimum: sidebarItem.minimumThickness,
            maximum: sidebarItem.maximumThickness
        )
        let directoryWidth = clampedWidth(
            defaults.object(forKey: PersistedWidthKey.directory) as? Double,
            defaultWidth: 300,
            minimum: directoryItem.minimumThickness,
            maximum: directoryItem.maximumThickness
        )
        let inspectorWidth = clampedWidth(
            defaults.object(forKey: PersistedWidthKey.inspector) as? Double,
            defaultWidth: 280,
            minimum: inspectorItem.minimumThickness,
            maximum: inspectorItem.maximumThickness
        )

        if !sidebarItem.isCollapsed, !directoryItem.isCollapsed {
            splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            let secondDivider = sidebarWidth + dividerThickness + directoryWidth
            if splitView.subviews.count >= 3 {
                splitView.setPosition(secondDivider, ofDividerAt: 1)
            }
        }

        if !inspectorItem.isCollapsed, splitView.subviews.count >= 4 {
            let trailingDivider = max(
                0,
                splitView.bounds.width - dividerThickness - inspectorWidth
            )
            splitView.setPosition(trailingDivider, ofDividerAt: splitView.subviews.count - 2)
        }

        hasRestoredInitialDividerPositions = true
    }

    private func persistCurrentVisibleColumnWidths() {
        let defaults = UserDefaults.standard

        if !sidebarItem.isCollapsed {
            defaults.set(sidebarItem.viewController.view.frame.width, forKey: PersistedWidthKey.sidebar)
        }

        if !directoryItem.isCollapsed {
            defaults.set(directoryItem.viewController.view.frame.width, forKey: PersistedWidthKey.directory)
        }

        if !inspectorItem.isCollapsed {
            defaults.set(inspectorItem.viewController.view.frame.width, forKey: PersistedWidthKey.inspector)
        }
    }

    private func clampedWidth(
        _ storedValue: Double?,
        defaultWidth: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        let resolvedStored = storedValue.map { CGFloat($0) } ?? defaultWidth
        return min(max(resolvedStored, minimum), maximum)
    }

    private func resolvedMinimumThickness(for item: NSSplitViewItem) -> CGFloat {
        item.minimumThickness == NSSplitViewItem.unspecifiedDimension ? 0 : item.minimumThickness
    }

    private func resolvedMaximumThickness(for item: NSSplitViewItem) -> CGFloat {
        item.maximumThickness == NSSplitViewItem.unspecifiedDimension ? .greatestFiniteMagnitude : item.maximumThickness
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            MainWindowToolbarItemID.back,
            MainWindowToolbarItemID.forward,
            MainWindowToolbarItemID.search,
            MainWindowToolbarItemID.find,
            MainWindowToolbarItemID.principalTitle,
            MainWindowToolbarItemID.newTab,
            MainWindowToolbarItemID.save,
            MainWindowToolbarItemID.markRead,
            MainWindowToolbarItemID.readerStyle,
            MainWindowToolbarItemID.share,
            MainWindowToolbarItemID.more,
            .inspectorTrackingSeparator,
            .toggleInspector,
            .flexibleSpace,
            .space
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            MainWindowToolbarItemID.back,
            MainWindowToolbarItemID.forward,
            MainWindowToolbarItemID.search,
            MainWindowToolbarItemID.find,
            .flexibleSpace,
            MainWindowToolbarItemID.principalTitle,
            .flexibleSpace,
            MainWindowToolbarItemID.newTab,
            MainWindowToolbarItemID.save,
            MainWindowToolbarItemID.markRead,
            MainWindowToolbarItemID.readerStyle,
            MainWindowToolbarItemID.share,
            MainWindowToolbarItemID.more,
            .inspectorTrackingSeparator,
            .toggleInspector
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .toggleInspector:
            return nil
        case .sidebarTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: leadingTrackingSeparatorDividerIndex() ?? 0
            )
        case .inspectorTrackingSeparator:
            return NSTrackingSeparatorToolbarItem(
                identifier: itemIdentifier,
                splitView: splitView,
                dividerIndex: dividerIndex(before: inspectorItem) ?? max(0, splitView.subviews.count - 2)
            )
        case MainWindowToolbarItemID.back:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "Back",
                symbolName: "chevron.left",
                action: #selector(goBack(_:))
            )
        case MainWindowToolbarItemID.forward:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "Forward",
                symbolName: "chevron.right",
                action: #selector(goForward(_:))
            )
        case MainWindowToolbarItemID.search:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "Search Wikipedia",
                symbolName: "magnifyingglass",
                action: #selector(startSearch(_:))
            )
        case MainWindowToolbarItemID.find:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "Find in Page",
                symbolName: "magnifyingglass.circle",
                action: #selector(toggleFindOnPage(_:))
            )
        case MainWindowToolbarItemID.principalTitle:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Title"
            let width = max(180, min(titleToolbarLabel.fittingSize.width + 32, 420))
            titleToolbarLabel.frame = CGRect(origin: .zero, size: CGSize(width: width, height: 28))
            item.view = titleToolbarLabel
            return item
        case MainWindowToolbarItemID.newTab:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "New Tab",
                symbolName: "plus",
                action: #selector(createNewTab(_:))
            )
        case MainWindowToolbarItemID.save:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "Save Article",
                symbolName: "bookmark",
                action: #selector(showSavePopover(_:))
            )
        case MainWindowToolbarItemID.markRead:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "Mark as Read",
                symbolName: "circle",
                action: #selector(toggleReadState(_:))
            )
        case MainWindowToolbarItemID.readerStyle:
            return makeToolbarButtonItem(
                identifier: itemIdentifier,
                label: "Reader Style",
                symbolName: "textformat.size",
                action: #selector(showReaderStylePopover(_:))
            )
        case MainWindowToolbarItemID.share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Share"
            item.paletteLabel = "Share"
            item.toolTip = "Share"
            item.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
            item.delegate = self
            return item
        case MainWindowToolbarItemID.more:
            return makeMenuToolbarItem(
                identifier: itemIdentifier,
                label: "More",
                symbolName: "ellipsis.circle",
                menu: makeMoreMenu()
            )
        default:
            return nil
        }
    }

    private func makeToolbarButtonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.target = self
        item.action = action
        if identifier == MainWindowToolbarItemID.back || identifier == MainWindowToolbarItemID.forward {
            item.isNavigational = true
        }
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let configuration = currentConfiguration else { return false }

        switch item.itemIdentifier {
        case .toggleSidebar:
            return currentConfiguration?.navigationToggleAllowed ?? true
        case MainWindowToolbarItemID.back:
            return currentTab?.canGoBack == true
        case MainWindowToolbarItemID.forward:
            return currentTab?.canGoForward == true
        case MainWindowToolbarItemID.search:
            return !configuration.appState.isWikiHopNavigationLocked && !configuration.appState.isFocusModeEnabled
        case MainWindowToolbarItemID.find:
            return currentArticle != nil && !configuration.appState.isFocusModeEnabled
        case MainWindowToolbarItemID.newTab:
            return !configuration.appState.isWikiHopNavigationLocked
        case MainWindowToolbarItemID.markRead:
            return currentArticle != nil
        case MainWindowToolbarItemID.save,
             MainWindowToolbarItemID.readerStyle,
             MainWindowToolbarItemID.share,
             MainWindowToolbarItemID.more:
            return currentArticle != nil
        default:
            return true
        }
    }

    @objc private func goBack(_ sender: Any?) {
        currentConfiguration?.appState.goBack()
    }

    @objc private func goForward(_ sender: Any?) {
        currentConfiguration?.appState.goForward()
    }

    @objc private func startSearch(_ sender: Any?) {
        currentConfiguration?.appState.startSearch(context: .navigation)
    }

    @objc private func toggleFindOnPage(_ sender: Any?) {
        guard let configuration = currentConfiguration,
              currentArticle != nil,
              let tabID = configuration.appState.activeTabId,
              !configuration.appState.isFocusModeEnabled else {
            return
        }

        if configuration.appState.showFindOnPage {
            configuration.appState.showFindOnPage = false
            configuration.appState.findOnPageQuery = ""
            configuration.appState.findOnPageMatchFound = nil
            configuration.appState.pendingFindOnPageRequest = AppState.FindOnPageRequest(
                requestID: UUID(),
                tabID: tabID,
                query: "",
                backwards: false
            )
        } else {
            configuration.appState.showFindOnPage = true
            configuration.appState.findOnPageMatchFound = nil
        }
    }

    @objc private func createNewTab(_ sender: Any?) {
        guard let configuration = currentConfiguration,
              !configuration.appState.isWikiHopNavigationLocked else { return }
        configuration.appState.createNewTab()
    }

    @objc private func showSavePopover(_ sender: Any?) {
        guard let article = currentArticle else { return }

        presentPopover(
            savePopover,
            identifier: MainWindowToolbarItemID.save,
            size: CGSize(width: 180, height: 260)
        ) {
            SaveToListPopover(
                articleTitle: article.title,
                articleDescription: article.description,
                articleExtract: article.extract,
                thumbnailURL: article.thumbnailURL,
                articleWordCount: article.wordCount
            )
        }
    }

    @objc private func showReaderStylePopover(_ sender: Any?) {
        presentPopover(
            readerStylePopover,
            identifier: MainWindowToolbarItemID.readerStyle,
            size: CGSize(width: 320, height: 360)
        ) {
            ReaderStylePopover()
        }
    }

    @objc private func openCurrentArticleInBrowser(_ sender: Any?) {
        guard let article = currentArticle else { return }
        NSWorkspace.shared.open(article.url)
    }

    @objc private func showPageViewsPopover(_ sender: Any?) {
        guard let article = currentArticle else { return }

        presentPopover(
            pageViewsPopover,
            identifier: MainWindowToolbarItemID.more,
            size: CGSize(width: 300, height: 220)
        ) {
            SidebarPageViewsPopoverContent(
                title: article.title,
                referenceDate: Date()
            )
        }
    }

    @objc private func toggleFocusMode(_ sender: Any?) {
        guard let configuration = currentConfiguration,
              configuration.appState.currentArticle != nil,
              !configuration.appState.isWikiHopNavigationLocked else {
            return
        }

        configuration.appState.toggleFocusMode()
    }

    @objc private func toggleReadState(_ sender: Any?) {
        guard let configuration = currentConfiguration,
              let article = currentArticle else { return }
        let nextState = !article.isRead
        _ = ReadStateSync.applyReadState(
            nextState,
            for: article,
            in: configuration.modelContext,
            appState: configuration.appState
        )
    }

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        guard let article = currentArticle else { return [] }
        return [article.url]
    }
}

private final class MainWindowChromeSplitView: NSSplitView {
    var visuallyHiddenDividerIndexes: Set<Int> = []
    private let hiddenDividerHotZoneWidth: CGFloat = 18

    override func drawDivider(in rect: NSRect) {
        if let dividerIndex = dividerIndex(for: rect),
           visuallyHiddenDividerIndexes.contains(dividerIndex) {
            return
        }

        super.drawDivider(in: rect)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if hiddenDividerIndex(at: point) != nil {
            return self
        }

        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        let cursor = isVertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown
        for dividerIndex in visuallyHiddenDividerIndexes {
            guard let rect = interactiveRect(forDividerAt: dividerIndex) else { continue }
            addCursorRect(rect, cursor: cursor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let initialPoint = convert(event.locationInWindow, from: nil)
        guard let dividerIndex = hiddenDividerIndex(at: initialPoint),
              let initialDividerOrigin = dividerOrigin(forDividerAt: dividerIndex) else {
            super.mouseDown(with: event)
            return
        }

        let initialAxis = isVertical ? initialPoint.x : initialPoint.y

        while let nextEvent = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = convert(nextEvent.locationInWindow, from: nil)
            let currentAxis = isVertical ? point.x : point.y
            let proposedOrigin = initialDividerOrigin + (currentAxis - initialAxis)

            if nextEvent.type == .leftMouseDragged {
                setPosition(proposedOrigin, ofDividerAt: dividerIndex)
            } else {
                return
            }
        }
    }

    private func dividerIndex(for drawnRect: NSRect) -> Int? {
        let visibleSubviews = subviews
            .filter { !$0.isHidden && $0.frame.width > 0.5 && $0.frame.height > 0.5 }
            .sorted { isVertical ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }

        guard visibleSubviews.count >= 2 else { return nil }

        for index in 0..<(visibleSubviews.count - 1) {
            let leadingSubview = visibleSubviews[index]
            let dividerOrigin = isVertical ? leadingSubview.frame.maxX : leadingSubview.frame.maxY
            let drawnOrigin = isVertical ? drawnRect.minX : drawnRect.minY

            if abs(dividerOrigin - drawnOrigin) < 1 {
                return index
            }
        }

        return nil
    }

    private func hiddenDividerIndex(at point: NSPoint) -> Int? {
        visuallyHiddenDividerIndexes.first { dividerIndex in
            guard let rect = interactiveRect(forDividerAt: dividerIndex) else { return false }
            return rect.contains(point)
        }
    }

    private func interactiveRect(forDividerAt dividerIndex: Int) -> NSRect? {
        guard let dividerOrigin = dividerOrigin(forDividerAt: dividerIndex) else {
            return nil
        }

        if isVertical {
            return NSRect(
                x: dividerOrigin - (hiddenDividerHotZoneWidth / 2),
                y: bounds.minY,
                width: hiddenDividerHotZoneWidth,
                height: bounds.height
            )
        }

        return NSRect(
            x: bounds.minX,
            y: dividerOrigin - (hiddenDividerHotZoneWidth / 2),
            width: bounds.width,
            height: hiddenDividerHotZoneWidth
        )
    }

    private func dividerOrigin(forDividerAt dividerIndex: Int) -> CGFloat? {
        let visibleSubviews = subviews
            .filter { !$0.isHidden && $0.frame.width > 0.5 && $0.frame.height > 0.5 }
            .sorted { isVertical ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY }

        guard dividerIndex >= 0, dividerIndex < visibleSubviews.count - 1 else {
            return nil
        }

        let leadingSubview = visibleSubviews[dividerIndex]
        return isVertical ? leadingSubview.frame.maxX : leadingSubview.frame.maxY
    }
}
