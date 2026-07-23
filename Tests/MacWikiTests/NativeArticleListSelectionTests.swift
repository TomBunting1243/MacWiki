import Foundation
import Testing

@testable import MacWiki

struct NativeArticleListSelectionTests {
    @Test("native selection is scoped to selected reading-list content")
    func nativeSelectionIsScopedToSelectedReadingListContent() throws {
        let directory = try repositorySource(
            "Sources/MacWiki/Views/Sidebar/DirectoryView.swift"
        )
        let scrollSurface = try sourceSection(
            in: directory,
            from: "private var directoryScrollSurface",
            to: "private static let discoverFeedDateFormatter"
        )
        let compactSurface = compacted(scrollSurface)
        let compactDirectory = compacted(directory)

        #expect(occurrenceCount(of: "List(selection:", in: compactDirectory) == 1)
        #expect(occurrenceCount(of: "List(selection:", in: compactSurface) == 1)

        let selectedListBranch = try requiredRange(
            of: "elseifselectedList!=nil{",
            in: compactSurface
        )
        let nativeList = try requiredRange(
            of: "List(selection:Binding(",
            in: compactSurface,
            after: selectedListBranch.upperBound
        )
        let selectionGetter = try requiredRange(
            of: "get:{columnState.selectedSavedArticleIDs}",
            in: compactSurface,
            after: nativeList.upperBound
        )
        let selectionSetter = try requiredRange(
            of: "set:{columnState.selectedSavedArticleIDs=$0}",
            in: compactSurface,
            after: selectionGetter.upperBound
        )
        let defaultList = try requiredRange(
            of: "else{List{",
            in: compactSurface,
            after: selectionSetter.upperBound
        )

        #expect(selectedListBranch.lowerBound < nativeList.lowerBound)
        #expect(nativeList.lowerBound < selectionGetter.lowerBound)
        #expect(selectionGetter.lowerBound < selectionSetter.lowerBound)
        #expect(selectionSetter.lowerBound < defaultList.lowerBound)
    }

    @Test("selected reading-list rows use native presentation and stable UUID tags")
    func selectedListRowsUseNativePresentationAndStableUUIDTags() throws {
        let directory = try repositorySource(
            "Sources/MacWiki/Views/Sidebar/DirectoryView.swift"
        )
        let selectedListSection = compacted(try sourceSection(
            in: directory,
            from: "private func selectedListSection",
            to: "// MARK: - Directory Commands"
        ))
        let readingListModels = compacted(try repositorySource(
            "Sources/MacWiki/Models/ReadingList.swift"
        ))

        #expect(selectedListSection.contains("SavedArticleRow("))
        #expect(selectedListSection.contains(
            "isSelected:selectedSavedArticleIDs.contains(savedArticle.id)"
        ))
        #expect(selectedListSection.contains("selectionPresentation:.native"))
        #expect(selectedListSection.contains(").tag(savedArticle.id)"))

        #expect(readingListModels.contains("finalclassSavedArticle{varid:UUID"))
        #expect(readingListModels.contains("self.id=UUID()"))
    }

    @Test("normal activation keeps the tapped article selected before opening")
    func normalActivationKeepsTappedArticleSelectedBeforeOpening() throws {
        let directory = try repositorySource(
            "Sources/MacWiki/Views/Sidebar/DirectoryView.swift"
        )
        let activation = compacted(try sourceSection(
            in: directory,
            from: "private func handleSavedArticlePrimaryAction",
            to: "private func openArticleFromPrimaryClick"
        ))

        let selectedAssignment = try requiredRange(
            of: "selectedSavedArticleIDs=[savedArticle.id]",
            in: activation
        )
        let anchorAssignment = try requiredRange(
            of: "selectionAnchorSavedArticleID=savedArticle.id",
            in: activation,
            after: selectedAssignment.upperBound
        )
        let openCall = try requiredRange(
            of: "openArticleFromPrimaryClick(article,inNewTab:SystemBridge.isCommandPressed)",
            in: activation,
            after: anchorAssignment.upperBound
        )

        #expect(selectedAssignment.lowerBound < anchorAssignment.lowerBound)
        #expect(anchorAssignment.lowerBound < openCall.lowerBound)
        #expect(!activation.contains("clearSavedArticleSelection()"))
    }

    @Test("native row presentation suppresses only custom selected chrome")
    func nativePresentationSuppressesCustomSelectedChromeWithoutChangingControls() throws {
        let rowSource = try repositorySource(
            "Sources/MacWiki/Views/Sidebar/Directory/DirectoryArticleRowViews.swift"
        )
        let articleListItem = compacted(try sourceSection(
            in: rowSource,
            from: "enum ArticleListSelectionPresentation",
            to: "struct ArticleRow: View"
        ))
        let rowFill = compacted(try sourceSection(
            in: rowSource,
            from: "private var rowFill",
            to: "private var rowStroke"
        ))
        let rowStroke = compacted(try sourceSection(
            in: rowSource,
            from: "private var rowStroke",
            to: "init("
        ))

        #expect(articleListItem.contains("casecustom"))
        #expect(articleListItem.contains("casenative"))
        #expect(articleListItem.contains(
            "selectionPresentation:ArticleListSelectionPresentation=.custom"
        ))
        #expect(rowFill.contains("ifselectionPresentation==.custom,isSelected{"))
        #expect(rowStroke.contains("ifselectionPresentation==.custom,isSelected{"))

        #expect(articleListItem.contains("iflettoggle=onToggleRead{"))
        #expect(articleListItem.contains("Button(action:toggle)"))
        #expect(articleListItem.contains(".buttonStyle(.plain)"))
        #expect(articleListItem.contains(".contentShape(Rectangle())"))
        #expect(articleListItem.contains(".onTapGesture{"))
        #expect(articleListItem.contains("selectionPresentation.handlesPrimaryTap("))
        #expect(articleListItem.contains("onToggleRead:onToggleRead"))
    }

    @Test("search and default saved rows retain custom selection presentation")
    func searchAndDefaultRowsRetainCustomSelectionPresentation() throws {
        let articleRows = compacted(try repositorySource(
            "Sources/MacWiki/Views/Sidebar/Directory/DirectoryArticleRowViews.swift"
        ))
        let savedRow = compacted(try repositorySource(
            "Sources/MacWiki/Views/Sidebar/Directory/SavedArticleRow.swift"
        ))
        let searchRow = compacted(try repositorySource(
            "Sources/MacWiki/Views/Sidebar/Search/SidebarSearchResultRowView.swift"
        ))

        #expect(articleRows.contains(
            "selectionPresentation:ArticleListSelectionPresentation=.custom"
        ))
        #expect(savedRow.contains(
            "varselectionPresentation:ArticleListSelectionPresentation=.custom"
        ))
        #expect(savedRow.contains("selectionPresentation:selectionPresentation"))

        #expect(searchRow.contains("isSelected:isSelected"))
        #expect(!searchRow.contains("selectionPresentation:.native"))
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    private func sourceSection(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        guard let start = source.range(of: startMarker) else {
            throw SourceContractError.missingMarker(startMarker)
        }
        guard let end = source.range(
            of: endMarker,
            range: start.upperBound..<source.endIndex
        ) else {
            throw SourceContractError.missingMarker(endMarker)
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func requiredRange(
        of needle: String,
        in source: String,
        after lowerBound: String.Index? = nil
    ) throws -> Range<String.Index> {
        let searchStart = lowerBound ?? source.startIndex
        guard let range = source.range(
            of: needle,
            range: searchStart..<source.endIndex
        ) else {
            throw SourceContractError.missingMarker(needle)
        }
        return range
    }

    private func compacted(_ source: String) -> String {
        source.replacingOccurrences(
            of: #"\s+"#,
            with: "",
            options: .regularExpression
        )
    }

    private func occurrenceCount(of needle: String, in source: String) -> Int {
        source.components(separatedBy: needle).count - 1
    }
}

private enum SourceContractError: Error {
    case missingMarker(String)
}
