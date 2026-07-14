import AppKit

extension ReaderToolbarController {
    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case .macWikiSidebarDirectoryBoundary:
            trackingSeparator(identifier: identifier, dividerIndex: 0)
        case .macWikiDirectoryReaderBoundary:
            trackingSeparator(identifier: identifier, dividerIndex: 1)
        case .macWikiReaderInspectorBoundary:
            trackingSeparator(identifier: identifier, dividerIndex: 2)
        case .toggleSidebar:
            standardToggleItem(
                identifier: identifier,
                label: "Lists",
                action: #selector(toggleSidebar(_:))
            )
        case .macWikiListContents:
            buttonItem(
                identifier: identifier,
                label: "List Contents",
                symbol: "sidebar.squares.leading",
                action: #selector(toggleListContents(_:))
            )
        case .macWikiSearch:
            searchToolbarItem(identifier: identifier)
        case .macWikiHistory:
            groupedItem(
                identifier: identifier,
                label: "History",
                symbols: ["chevron.left", "chevron.right"],
                segmentLabels: ["Back", "Forward"],
                action: #selector(performHistoryAction(_:))
            )
        case .macWikiArticleState:
            groupedItem(
                identifier: identifier,
                label: "Article Status",
                symbols: ["bookmark", "circle"],
                segmentLabels: ["Save Article", "Mark as Read"],
                action: #selector(performArticleStateAction(_:))
            )
        case .macWikiFind:
            buttonItem(
                identifier: identifier,
                label: "Find in Page",
                symbol: "text.magnifyingglass",
                action: #selector(toggleFindOnPage(_:))
            )
        case .macWikiStyle:
            buttonItem(
                identifier: identifier,
                label: "Reader Style",
                symbol: "textformat.size",
                action: #selector(showReaderStyle(_:))
            )
        case .macWikiPageViews:
            buttonItem(
                identifier: identifier,
                label: "Page Views",
                symbol: "chart.xyaxis.line",
                action: #selector(showPageViews(_:))
            )
        case .macWikiOpenInBrowser:
            buttonItem(
                identifier: identifier,
                label: "Open in Browser",
                symbol: "safari",
                action: #selector(openInBrowser(_:))
            )
        case .macWikiShare:
            sharingItem(identifier: identifier)
        case .toggleInspector:
            standardToggleItem(
                identifier: identifier,
                label: "Inspector",
                action: #selector(toggleInspector(_:))
            )
        default:
            nil
        }
    }

    func items(
        for pickerToolbarItem: NSSharingServicePickerToolbarItem
    ) -> [Any] {
        guard !environment.appState.isWikiHopNavigationLocked,
              let article = environment.appState.currentArticle else { return [] }
        return [article.url as NSURL]
    }

    @objc func toggleSidebar(_ sender: Any?) {
        guard !environment.appState.isWikiHopNavigationLocked else { return }
        environment.appState.toggleListsSidebarVisibility()
    }

    @objc func toggleListContents(_ sender: Any?) {
        guard !environment.appState.isWikiHopNavigationLocked else { return }
        environment.appState.toggleDirectoryColumnVisibility()
    }

    @objc func performHistoryAction(_ sender: Any?) {
        guard !environment.appState.isWikiHopNavigationLocked else { return }
        switch selectedSegment(from: sender).flatMap(HistorySegment.init(rawValue:)) {
        case .back:
            environment.appState.goBack()
        case .forward:
            environment.appState.goForward()
        case nil:
            break
        }
    }

    @objc func performArticleStateAction(_ sender: Any?) {
        guard !environment.appState.isWikiHopNavigationLocked,
              let article = environment.appState.currentArticle else { return }
        switch selectedSegment(from: sender).flatMap(ArticleStateSegment.init(rawValue:)) {
        case .save:
            guard let item = activeItem(.macWikiArticleState) else { return }
            popoverPresenter.showSave(for: article, relativeTo: item)
        case .read:
            _ = ReadStateSync.applyReadState(
                !article.isRead,
                for: article,
                in: environment.modelContext,
                appState: environment.appState
            )
        case nil:
            break
        }
    }

    @objc func toggleFindOnPage(_ sender: Any?) {
        let appState = environment.appState
        guard !appState.isWikiHopNavigationLocked,
              let tabID = appState.activeTabId,
              appState.currentArticle != nil else {
            return
        }

        if appState.showFindOnPage {
            appState.dismissFindOnPage(
                activeTabID: tabID,
                clearsWebSelection: true
            )
        } else {
            appState.presentFindOnPage()
        }
    }

    @objc func showReaderStyle(_ sender: Any?) {
        guard !environment.appState.isWikiHopNavigationLocked,
              environment.appState.currentArticle != nil,
              let item = activeItem(.macWikiStyle) else {
            return
        }
        popoverPresenter.showReaderStyle(relativeTo: item)
    }

    @objc func showPageViews(_ sender: Any?) {
        guard !environment.appState.isWikiHopNavigationLocked,
              let article = environment.appState.currentArticle,
              let item = activeItem(.macWikiPageViews) else {
            return
        }
        popoverPresenter.showPageViews(for: article, relativeTo: item)
    }

    @objc func openInBrowser(_ sender: Any?) {
        guard !environment.appState.isWikiHopNavigationLocked,
              let article = environment.appState.currentArticle else { return }
        environment.openURL(article.url)
    }

    @objc func toggleInspector(_ sender: Any?) {
        environment.appState.toggleInspectorVisibility()
    }

    func updateButton(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        symbol: String,
        enabled: Bool
    ) {
        guard let item = activeItem(identifier) else { return }
        item.label = label
        item.toolTip = label
        item.image = symbolImage(named: symbol, accessibilityLabel: label)
        item.isEnabled = enabled
    }

    func updateStandardToggle(
        _ identifier: NSToolbarItem.Identifier,
        label: String,
        enabled: Bool
    ) {
        guard let item = activeItem(identifier) else { return }
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.isEnabled = enabled
    }

    func updateSearchItem(text: String, enabled: Bool) {
        guard let item = activeItem(.macWikiSearch) as? NSSearchToolbarItem else { return }
        let searchField = item.searchField
        if searchField.stringValue != text {
            searchField.stringValue = text
        }
        item.isEnabled = enabled
        searchField.isEnabled = enabled
    }

    func focusSearchField() {
        guard let searchField = (activeItem(.macWikiSearch) as? NSSearchToolbarItem)?.searchField,
              let attachedWindow else {
            return
        }
        attachedWindow.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func updateGroup(
        _ identifier: NSToolbarItem.Identifier,
        segments: [(label: String, symbol: String, enabled: Bool)]
    ) {
        guard let item = activeItem(identifier) as? NSToolbarItemGroup else { return }
        for (index, segment) in segments.enumerated()
            where item.subitems.indices.contains(index) {
            let subitem = item.subitems[index]
            subitem.label = segment.label
            subitem.toolTip = segment.label
            subitem.image = symbolImage(
                named: segment.symbol,
                accessibilityLabel: segment.label
            )
            subitem.isEnabled = segment.enabled
        }
        item.isEnabled = segments.contains { $0.enabled }
    }

    func activeItem(
        _ identifier: NSToolbarItem.Identifier
    ) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier == identifier }
    }

    private func trackingSeparator(
        identifier: NSToolbarItem.Identifier,
        dividerIndex: Int
    ) -> NSToolbarItem {
        let item = NSTrackingSeparatorToolbarItem(
            identifier: identifier,
            splitView: splitController.splitView,
            dividerIndex: dividerIndex
        )
        item.visibilityPriority = ReaderToolbarLayout.visibilityPriority(for: identifier)
        return item
    }

    private func buttonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbol: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = symbolImage(named: symbol, accessibilityLabel: label)
        item.target = self
        item.action = action
        item.visibilityPriority = ReaderToolbarLayout.visibilityPriority(for: identifier)
        return item
    }

    private func standardToggleItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.visibilityPriority = ReaderToolbarLayout.visibilityPriority(for: identifier)
        return item
    }

    private func searchToolbarItem(
        identifier: NSToolbarItem.Identifier
    ) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: identifier)
        item.label = "Search Wikipedia"
        item.paletteLabel = "Search Wikipedia"
        item.toolTip = "Search Wikipedia"
        item.visibilityPriority = ReaderToolbarLayout.visibilityPriority(for: identifier)

        let searchField = item.searchField
        searchField.placeholderString = "Search Wikipedia"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldChanged(_:))
        searchField.identifier = NSUserInterfaceItemIdentifier("sidebar-search-field")
        searchField.setAccessibilityLabel("Search Wikipedia")
        return item
    }

    private func groupedItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbols: [String],
        segmentLabels: [String],
        action: Selector
    ) -> NSToolbarItemGroup {
        let images = zip(symbols, segmentLabels).map {
            symbolImage(named: $0.0, accessibilityLabel: $0.1)
        }
        let item = NSToolbarItemGroup(
            itemIdentifier: identifier,
            images: images,
            selectionMode: .momentary,
            labels: segmentLabels,
            target: self,
            action: action
        )
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.visibilityPriority = ReaderToolbarLayout.visibilityPriority(for: identifier)
        return item
    }

    private func sharingItem(
        identifier: NSToolbarItem.Identifier
    ) -> NSSharingServicePickerToolbarItem {
        let item = NSSharingServicePickerToolbarItem(itemIdentifier: identifier)
        item.label = "Share"
        item.paletteLabel = "Share"
        item.toolTip = "Share"
        item.image = symbolImage(
            named: "square.and.arrow.up",
            accessibilityLabel: "Share"
        )
        item.delegate = self
        item.visibilityPriority = ReaderToolbarLayout.visibilityPriority(for: identifier)
        return item
    }

    private func selectedSegment(from sender: Any?) -> Int? {
        if let group = sender as? NSToolbarItemGroup {
            return group.selectedIndex
        }
        if let segmentedControl = sender as? NSSegmentedControl {
            return segmentedControl.selectedSegment
        }
        return nil
    }

    private func symbolImage(
        named symbol: String,
        accessibilityLabel: String
    ) -> NSImage {
        NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: accessibilityLabel
        ) ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        publishSearchText(sender.stringValue)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object is NSSearchField else { return }
        revealSearchSurfaceIfNeeded()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let searchField = notification.object as? NSSearchField else { return }
        publishSearchText(searchField.stringValue)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control is NSSearchField,
              let model = environment.sidebarSearchModel else {
            return false
        }

        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelectionDown()
            return true
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelectionUp()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelectedSearchResult(using: model)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if model.searchCoordinator.hasInput {
                model.searchCoordinator.clearSearch()
            } else {
                environment.appState.showSearch = false
                attachedWindow?.makeFirstResponder(nil)
            }
            return true
        default:
            return false
        }
    }

    private func publishSearchText(_ text: String) {
        guard !environment.appState.isWikiHopNavigationLocked,
              let searchCoordinator = environment.sidebarSearchModel?.searchCoordinator else {
            return
        }
        revealSearchSurfaceIfNeeded()
        if searchCoordinator.searchText != text {
            searchCoordinator.searchText = text
        }
    }

    private func revealSearchSurfaceIfNeeded() {
        let appState = environment.appState
        guard !appState.isWikiHopNavigationLocked,
              !appState.showSearch else {
            return
        }
        appState.startSearch(context: .navigation)
    }

    private func openSelectedSearchResult(using model: SidebarSearchSurfaceModel) {
        guard let row = model.selectedRow else { return }
        var inNewTab = environment.appState.searchContext == .newTab
        if SystemBridge.isCommandPressed {
            inNewTab.toggle()
        }
        if SystemBridge.isOptionPressed {
            environment.appState.presentOptionClickSavePrompt(for: row.article)
            return
        }
        environment.appState.openArticle(row.article, inNewTab: inNewTab)
    }
}
