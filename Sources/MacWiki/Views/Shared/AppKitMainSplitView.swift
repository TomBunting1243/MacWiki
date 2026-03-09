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

    let listsSidebarWidth: CGFloat
    let inspectorIdealWidth: CGFloat
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
            listsRootView: AnyView(
                ListsColumnView(
                    selectedList: $selectedList,
                    selectedLabel: $selectedLabel,
                    selectedTag: $selectedTag,
                    rootSelection: $rootSelection,
                    preferredWidth: listsSidebarWidth,
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
                InspectorPanel(
                    showNewLabelSheet: $showNewLabelSheet,
                    articleForNewLabel: $articleForNewLabel,
                    currentArticleTitle: appState.currentArticle?.title
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
            ),
            navigationColumnsVisible: appState.sidebarVisible,
            inspectorVisible: appState.inspectorVisible && !appState.isFocusModeEnabled,
            listsSidebarWidth: listsSidebarWidth,
            inspectorIdealWidth: inspectorIdealWidth,
            animateTransitions: !reduceMotion,
            onListsSidebarWidthChange: { newWidth in
                let clamped = min(max(newWidth, 176), 260)
                guard clamped.isFinite, clamped > 0 else { return }
                if abs(listsSidebarWidth - clamped) > 0.5 {
                    UserDefaults.standard.set(Double(clamped), forKey: "listsSidebarWidth")
                }
            },
            onInspectorWidthChange: { newWidth in
                let clamped = min(max(newWidth, 220), 380)
                guard clamped.isFinite, clamped > 0 else { return }
                if abs(inspectorIdealWidth - clamped) > 0.5 {
                    UserDefaults.standard.set(Double(clamped), forKey: "inspectorWidth")
                }
            }
        )
    }
}

@MainActor
final class MainWindowSplitViewController: NSSplitViewController {
    private enum ToolbarAnchor {
        static let sidebar = NSToolbarItem.Identifier("sidebar")
        static let inspectorBoundary = NSToolbarItem.Identifier("inspector-boundary")
    }

    struct Configuration {
        let listsRootView: AnyView
        let directoryRootView: AnyView
        let readerRootView: AnyView
        let inspectorRootView: AnyView
        let navigationColumnsVisible: Bool
        let inspectorVisible: Bool
        let listsSidebarWidth: CGFloat
        let inspectorIdealWidth: CGFloat
        let animateTransitions: Bool
        let onListsSidebarWidthChange: (CGFloat) -> Void
        let onInspectorWidthChange: (CGFloat) -> Void
    }

    private let listsHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let directoryHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let readerHostingController = NSHostingController(rootView: AnyView(EmptyView()))
    private let inspectorHostingController = NSHostingController(rootView: AnyView(EmptyView()))

    private lazy var sidebarItem = NSSplitViewItem(sidebarWithViewController: listsHostingController)
    private lazy var directoryItem = NSSplitViewItem(contentListWithViewController: directoryHostingController)
    private lazy var readerItem = NSSplitViewItem(viewController: readerHostingController)
    private lazy var inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorHostingController)

    private lazy var sidebarWidthConstraint = listsHostingController.view.widthAnchor.constraint(equalToConstant: 204)
    private lazy var directoryWidthConstraint = directoryHostingController.view.widthAnchor.constraint(equalToConstant: 272)
    private lazy var inspectorWidthConstraint = inspectorHostingController.view.widthAnchor.constraint(equalToConstant: 240)

    private var currentConfiguration: Configuration?

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.autosaveName = "MainWindowSplitViewController"
        splitView.dividerStyle = .thin

        configureSplitItems()
        splitViewItems = [sidebarItem, directoryItem, readerItem, inspectorItem]

        sidebarWidthConstraint.priority = .defaultHigh
        directoryWidthConstraint.priority = .defaultHigh
        inspectorWidthConstraint.priority = .defaultHigh

        sidebarWidthConstraint.isActive = true
        directoryWidthConstraint.isActive = true
        inspectorWidthConstraint.isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureWindowChrome()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        publishColumnWidths()
        configureWindowChrome()
    }

    func update(configuration: Configuration) {
        currentConfiguration = configuration

        listsHostingController.rootView = configuration.listsRootView
        directoryHostingController.rootView = configuration.directoryRootView
        readerHostingController.rootView = configuration.readerRootView
        inspectorHostingController.rootView = configuration.inspectorRootView

        sidebarWidthConstraint.constant = configuration.listsSidebarWidth
        inspectorWidthConstraint.constant = configuration.inspectorIdealWidth

        applyCollapsedState(
            navigationColumnsVisible: configuration.navigationColumnsVisible,
            inspectorVisible: configuration.inspectorVisible,
            animated: configuration.animateTransitions
        )

        configureWindowChrome()
    }

    private func configureSplitItems() {
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = true
        sidebarItem.minimumThickness = 176
        sidebarItem.maximumThickness = 260
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.titlebarSeparatorStyle = .none

        directoryItem.canCollapse = true
        directoryItem.canCollapseFromWindowResize = true
        directoryItem.minimumThickness = 212
        directoryItem.maximumThickness = 360

        readerItem.canCollapse = false
        if #available(macOS 26, *) {
            readerItem.automaticallyAdjustsSafeAreaInsets = true
        }

        inspectorItem.canCollapse = true
        inspectorItem.canCollapseFromWindowResize = false
        inspectorItem.minimumThickness = 220
        inspectorItem.maximumThickness = 380
        inspectorItem.allowsFullHeightLayout = true
        inspectorItem.titlebarSeparatorStyle = .none
    }

    private func applyCollapsedState(
        navigationColumnsVisible: Bool,
        inspectorVisible: Bool,
        animated: Bool
    ) {
        let applyChanges = {
            self.sidebarItem.isCollapsed = !navigationColumnsVisible
            self.directoryItem.isCollapsed = !navigationColumnsVisible
            self.inspectorItem.isCollapsed = !inspectorVisible
        }

        guard animated else {
            applyChanges()
            configureWindowChrome()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            self.sidebarItem.animator().isCollapsed = !navigationColumnsVisible
            self.directoryItem.animator().isCollapsed = !navigationColumnsVisible
            self.inspectorItem.animator().isCollapsed = !inspectorVisible
        } completionHandler: {
            Task { @MainActor in
                self.configureWindowChrome()
            }
        }
    }

    private func publishColumnWidths() {
        guard let configuration = currentConfiguration else { return }

        if !sidebarItem.isCollapsed {
            let width = listsHostingController.view.frame.width
            if width.isFinite, width > 0 {
                configuration.onListsSidebarWidthChange(width)
            }
        }

        if !inspectorItem.isCollapsed {
            let width = inspectorHostingController.view.frame.width
            if width.isFinite, width > 0 {
                configuration.onInspectorWidthChange(width)
            }
        }
    }

    private func configureWindowChrome() {
        guard let window = view.window, let toolbar = window.toolbar else { return }

        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true

        synchronizeTrackingSeparator(
            toolbar: toolbar,
            identifier: .sidebarTrackingSeparator,
            after: ToolbarAnchor.sidebar,
            dividerIndex: dividerIndex(after: sidebarItem)
        )

        synchronizeTrackingSeparator(
            toolbar: toolbar,
            identifier: .inspectorTrackingSeparator,
            after: ToolbarAnchor.inspectorBoundary,
            dividerIndex: dividerIndex(before: inspectorItem)
        )
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
        after anchor: NSToolbarItem.Identifier,
        dividerIndex: Int?
    ) {
        let existingIndex = toolbar.items.firstIndex { $0.itemIdentifier == identifier }

        guard let dividerIndex,
              let anchorIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == anchor }) else {
            if let existingIndex {
                toolbar.removeItem(at: existingIndex)
            }
            return
        }

        let desiredIndex = anchorIndex + 1

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
}
