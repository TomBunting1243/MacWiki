import AppKit
import SwiftData
import WebKit

extension WebView.Coordinator {
    func presentNativeLinkContextMenu(for request: WebViewLinkContextRequest) {
        guard let webView else { return }
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        if request.articleTitle != nil {
            menu.addItem(linkMenuItem(
                title: "Open",
                systemImage: "arrow.up.forward",
                action: .open,
                request: request
            ))
            menu.addItem(linkMenuItem(
                title: "Open in New Tab",
                systemImage: "plus.square.on.square",
                action: .openInNewTab,
                request: request
            ))
            menu.addItem(linkMenuItem(
                title: "Open in New Window",
                systemImage: "macwindow.badge.plus",
                action: .openInNewWindow,
                request: request
            ))
            menu.addItem(linkMenuItem(
                title: "Open in Background Tab",
                systemImage: "square.on.square",
                action: .openInNewBackgroundTab,
                request: request
            ))

            let readingLists = fetchReadingLists()
            if !readingLists.isEmpty {
                menu.addItem(.separator())
                let saveToListItem = NSMenuItem(title: "Save to List", action: nil, keyEquivalent: "")
                let saveToListMenu = NSMenu(title: "Save to List")
                saveToListMenu.autoenablesItems = false

                for list in readingLists {
                    let item = linkMenuItem(
                        title: list.name,
                        systemImage: list.icon,
                        action: .saveToList,
                        request: request,
                        readingListID: list.id
                    )
                    saveToListMenu.addItem(item)
                }
                saveToListItem.submenu = saveToListMenu
                menu.addItem(saveToListItem)
            }

            menu.addItem(.separator())
            menu.addItem(linkMenuItem(
                title: "Copy Title",
                systemImage: "doc.on.doc",
                action: .copyTitle,
                request: request
            ))
        } else {
            menu.addItem(linkMenuItem(
                title: "Open Link",
                systemImage: "safari",
                action: .open,
                request: request
            ))
            menu.addItem(.separator())
        }

        menu.addItem(linkMenuItem(
            title: "Copy Link",
            systemImage: "link",
            action: .copyLink,
            request: request
        ))

        menu.popUp(positioning: nil, at: WebViewContextMenuController.contextMenuPoint(request.point, in: webView), in: webView)
    }

    func linkMenuItem(
        title: String,
        systemImage: String,
        action: WebViewContextMenuController.LinkMenuAction,
        request: WebViewLinkContextRequest,
        readingListID: UUID? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performLinkContextAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = WebViewContextMenuController.LinkMenuPayload(
            action: action,
            url: request.url,
            articleTitle: request.articleTitle,
            readingListID: readingListID
        )
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
            item.image = image
        }
        return item
    }

    @objc
    func performLinkContextAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? WebViewContextMenuController.LinkMenuPayload else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch payload.action {
            case .open:
                self.openLinkFromContextMenu(payload.url, inNewTab: false)
            case .openInNewTab:
                self.openLinkFromContextMenu(payload.url, inNewTab: true)
            case .openInNewBackgroundTab:
                self.openLinkFromContextMenu(payload.url, inNewTab: true, activateNewTab: false)
            case .openInNewWindow:
                self.openLinkFromContextMenuInNewWindow(payload.url)
            case .copyTitle:
                if let title = payload.articleTitle {
                    _ = SystemBridge.copyText(title)
                }
            case .copyLink:
                _ = SystemBridge.copyText(payload.url.absoluteString)
            case .saveToList:
                guard let title = payload.articleTitle,
                      let readingListID = payload.readingListID else { return }
                self.saveLinkedArticle(title: title, to: readingListID)
            }
        }
    }

    func openLinkFromContextMenuInNewWindow(_ url: URL) {
        dismissLinkHoverPreview(immediate: true)
        if let target = wikipediaLinkTarget(from: url) {
            let article = Article(id: target.id, title: target.displayTitle)
            onOpenArticleInNewWindow?(article)
            return
        }

        if url.scheme != nil {
            _ = SystemBridge.openURLExternally(url)
        }
    }

    func openLinkFromContextMenu(_ url: URL, inNewTab: Bool, activateNewTab: Bool = true) {
        dismissLinkHoverPreview(immediate: true)
        if let target = wikipediaLinkTarget(from: url) {
            let normalizedCurrentTitle = normalizedArticleKey(articleTitle)
            let normalizedTargetTitle = normalizedArticleKey(target.displayTitle)
            let fragment = url.fragment?.trimmingCharacters(in: .whitespacesAndNewlines)
            if !inNewTab,
               normalizedCurrentTitle == normalizedTargetTitle,
               let fragment,
               !fragment.isEmpty {
                scrollToAnchor(fragment)
                return
            }

            if inNewTab {
                let article = Article(id: target.id, title: target.displayTitle)
                appState?.openArticleInNewTab(article, activate: activateNewTab)
            } else {
                onLinkTapped?(target.displayTitle)
            }
            return
        }

        if url.scheme != nil {
            _ = SystemBridge.openURLExternally(url)
        }
    }

    func presentNativeSelectionContextMenu(for request: WebViewSelectionContextRequest) {
        guard let webView else { return }

        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        let highlightMenuRoot = NSMenuItem(title: "Highlight", action: nil, keyEquivalent: "")
        let highlightMenu = NSMenu(title: "Highlight")
        highlightMenu.autoenablesItems = false
        for color in HighlightColor.allCases {
            highlightMenu.addItem(selectionColorMenuItem(
                color: color,
                action: .highlight(color),
                request: request
            ))
        }
        highlightMenuRoot.submenu = highlightMenu
        menu.addItem(highlightMenuRoot)

        let noteMenuRoot = NSMenuItem(title: "Highlight with Note", action: nil, keyEquivalent: "")
        let noteMenu = NSMenu(title: "Highlight with Note")
        noteMenu.autoenablesItems = false
        for color in HighlightColor.allCases {
            noteMenu.addItem(selectionColorMenuItem(
                color: color,
                action: .highlightWithNote(color),
                request: request
            ))
        }
        noteMenuRoot.submenu = noteMenu
        menu.addItem(noteMenuRoot)

        menu.addItem(.separator())
        menu.addItem(selectionMenuItem(
            title: "Copy Selection",
            systemImage: "doc.on.doc",
            action: .copySelection,
            request: request
        ))

        menu.popUp(positioning: nil, at: WebViewContextMenuController.contextMenuPoint(request.point, in: webView), in: webView)
    }

    func selectionColorMenuItem(
        color: HighlightColor,
        action: WebViewContextMenuController.SelectionMenuAction,
        request: WebViewSelectionContextRequest
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: color.rawValue,
            action: #selector(performSelectionContextAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = WebViewContextMenuController.SelectionMenuPayload(action: action, request: request)
        item.image = WebViewContextMenuController.highlightColorSwatchImage(for: color)
        return item
    }

    func selectionMenuItem(
        title: String,
        systemImage: String,
        action: WebViewContextMenuController.SelectionMenuAction,
        request: WebViewSelectionContextRequest
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(performSelectionContextAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = WebViewContextMenuController.SelectionMenuPayload(action: action, request: request)
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
            item.image = image
        }
        return item
    }

    @objc
    func performSelectionContextAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? WebViewContextMenuController.SelectionMenuPayload else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch payload.action {
            case .highlight(let color):
                self.createHighlight(
                    from: payload.request.selection,
                    color: color,
                    note: nil
                )
            case .highlightWithNote(let color):
                if let highlightID = self.createHighlight(
                    from: payload.request.selection,
                    color: color,
                    note: nil
                ) {
                    self.openHighlightNoteEditor(highlightID: highlightID)
                }
            case .copySelection:
                _ = SystemBridge.copyText(payload.request.selection.text)
                self.appState?.currentTextSelection = nil
            }
        }
    }

    @discardableResult
    func createHighlight(from selection: TextSelectionData, color: HighlightColor, note: String?) -> UUID? {
        guard let modelContext else { return nil }
        guard let highlight = HighlightPersistence.create(
            from: selection,
            articleTitle: articleTitle,
            color: color,
            note: note,
            in: modelContext
        ) else { return nil }

        appState?.pendingImmediateHighlight = AppState.ImmediateHighlightRequest(
            id: highlight.id,
            cssColor: color.cssColor
        )
        appState?.currentTextSelection = nil
        return highlight.id
    }

    func openHighlightNoteEditor(highlightID: UUID) {
        appState?.selectedHighlightId = highlightID.uuidString
        appState?.highlightTagFilterId = nil
        appState?.inspectorMode = .notes
        appState?.inspectorVisible = true
        appState?.pendingHighlightNoteEditorRequest = AppState.HighlightNoteEditorRequest(
            requestID: UUID(),
            highlightID: highlightID
        )
    }

    func fetchReadingLists() -> [ReadingList] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<ReadingList>(
            sortBy: [SortDescriptor(\ReadingList.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func saveLinkedArticle(title: String, to readingListID: UUID) {
        guard let modelContext else { return }
        let targetListID = readingListID
        let descriptor = FetchDescriptor<ReadingList>(
            predicate: #Predicate { list in
                list.id == targetListID
            }
        )
        guard let list = try? modelContext.fetch(descriptor).first else { return }

        let normalized = ReadStateSync.normalizedTitle(title)
        if list.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalized }) {
            return
        }

        let saved = SavedArticle(title: title, list: list)
        saved.isRead = ReadStateSync.resolveReadState(for: title, in: modelContext)
        list.articles.append(saved)
        list.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
        SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
        appState?.requestSave()
    }

    func presentNativeHighlightContextMenu(for request: WebViewHighlightContextRequest) {
        guard let webView else { return }
        guard let highlight = highlights.first(where: { $0.id == request.id }) else { return }

        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        let colorMenuRoot = NSMenuItem(title: "Highlight Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu(title: "Highlight Color")
        colorMenu.autoenablesItems = false

        for color in HighlightColor.allCases {
            colorMenu.addItem(
                highlightColorMenuItem(
                    color: color,
                    isSelected: highlight.color == color,
                    highlightID: request.id
                )
            )
        }

        colorMenuRoot.submenu = colorMenu
        menu.addItem(colorMenuRoot)
        menu.addItem(.separator())
        menu.addItem(highlightMenuItem(
            title: highlight.note == nil ? "Add Note" : "Edit Note",
            systemImage: "note.text",
            action: .editNote,
            highlightID: request.id
        ))
        menu.addItem(highlightMenuItem(
            title: "Delete Highlight",
            systemImage: "trash",
            action: .delete,
            highlightID: request.id
        ))

        menu.popUp(positioning: nil, at: WebViewContextMenuController.contextMenuPoint(request.point, in: webView), in: webView)
    }

    func highlightColorMenuItem(
        color: HighlightColor,
        isSelected: Bool,
        highlightID: UUID
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: color.rawValue,
            action: #selector(performHighlightContextAction(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = WebViewContextMenuController.HighlightMenuPayload(action: .setColor(color), highlightID: highlightID)
        item.image = WebViewContextMenuController.highlightColorSwatchImage(for: color)
        item.state = isSelected ? .on : .off
        return item
    }

    func highlightMenuItem(
        title: String,
        systemImage: String,
        action: WebViewContextMenuController.HighlightMenuAction,
        highlightID: UUID
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performHighlightContextAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = WebViewContextMenuController.HighlightMenuPayload(action: action, highlightID: highlightID)
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
            item.image = image
        }
        return item
    }

    @objc
    func performHighlightContextAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? WebViewContextMenuController.HighlightMenuPayload else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch payload.action {
            case .setColor(let color):
                self.updateHighlightColor(highlightID: payload.highlightID, color: color)
            case .editNote:
                self.openHighlightInInspector(highlightID: payload.highlightID)
            case .delete:
                self.deleteHighlight(highlightID: payload.highlightID)
            }
        }
    }

    func openHighlightInInspector(highlightID: UUID) {
        appState?.selectedHighlightId = highlightID.uuidString
        appState?.inspectorMode = .notes
        appState?.inspectorVisible = true
    }

    @discardableResult
    func updateHighlightColor(highlightID: UUID, color: HighlightColor) -> Bool {
        guard let modelContext else { return false }
        guard let highlight = highlights.first(where: { $0.id == highlightID }) else { return false }
        guard highlight.color != color else { return true }

        guard HighlightPersistence.updateColor(
            of: highlight,
            to: color,
            in: modelContext
        ) else { return false }
        appState?.pendingHighlightColorChange = AppState.HighlightColorChangeRequest(
            id: highlightID,
            cssColor: color.cssColor
        )
        return true
    }

    func deleteHighlight(highlightID: UUID) {
        guard let modelContext else { return }
        guard let highlight = highlights.first(where: { $0.id == highlightID }) else { return }
        modelContext.delete(highlight)
        modelContext.saveReportingFailure(operation: #function)
    }
}
