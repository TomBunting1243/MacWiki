import AppKit
import Foundation
import Testing

@testable import MacWiki

struct DiscoverEditorialDesignRegressionTests {
    @Test func discoveryImagesFitCompletelyAndOpenInsideMacWiki() throws {
        let feature = try source("Sources/MacWiki/Views/Home/Discover/DiscoverFeatureComponents.swift")
        let news = try source("Sources/MacWiki/Views/Home/Discover/DiscoverNewsComponents.swift")
        let media = try source("Sources/MacWiki/Views/Home/Discover/DiscoverMediaSupport.swift")
        let mediaViewer = try source("Sources/MacWiki/Views/Home/Discover/DiscoverMediaViewer.swift")

        for imageSurface in [feature, news, media, mediaViewer] {
            #expect(!imageSurface.contains("aspectRatio(contentMode: .fill)"))
            #expect(!imageSurface.contains("scaledToFill()"))
        }

        #expect(feature.contains(".aspectRatio(contentMode: .fit)"))
        #expect(news.contains(".aspectRatio(contentMode: .fit)"))
        #expect(media.contains(".aspectRatio(contentMode: .fit)"))
        #expect(media.contains(".scaledToFit()"))
        #expect(media.contains(".sheet(item: $selectedImage)"))
        #expect(media.contains(".sheet(isPresented: $isViewerPresented)"))
        #expect(mediaViewer.contains("struct DiscoverMediaViewer: View"))
        #expect(media.components(separatedBy: ".accessibilityHint(\"Open image in MacWiki\")").count - 1 == 2)
        #expect(mediaViewer.contains("Button(\"Open Commons in Browser\", systemImage: \"safari\")"))
    }

    @Test func discoveryKeyboardAndPointerFeedbackHaveVisibleOwners() throws {
        let sections = try source("Sources/MacWiki/Views/Home/Discover/DiscoverFeedSections.swift")
        let collectionStages = try source("Sources/MacWiki/Views/Home/Discover/DiscoverFeedCollectionStages.swift")
        let collections = try source("Sources/MacWiki/Views/Home/Discover/DiscoverCollectionComponents.swift")
        let news = try source("Sources/MacWiki/Views/Home/Discover/DiscoverNewsComponents.swift")
        let media = try source("Sources/MacWiki/Views/Home/Discover/DiscoverMediaSupport.swift")
        let sidebar = try source("Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverRows.swift")

        #expect(sections.contains(".onKeyPress(.return, phases: .down)"))
        #expect(sections.contains("activePageViewsPopover == nil"))
        #expect(sections.contains("keyPress.modifiers.contains(.command)"))
        #expect(!collectionStages.contains("collectionsKeyboardShortcutHost"))
        #expect(!collectionStages.contains(".opacity(0.001)"))
        #expect(!collectionStages.contains(".keyboardShortcut(.return"))

        for interactiveSurface in [collections, news, media] {
            #expect(interactiveSurface.contains(".onHover"))
            #expect(interactiveSurface.contains("discoverHoverEffect"))
        }
        #expect(sidebar.contains("sidebarDiscoverInteractiveHover"))
        #expect(sidebar.components(separatedBy: ".sidebarDiscoverInteractiveHover").count - 1 >= 4)
    }

    @Test func discoverSidebarUsesCountedHeadersAndAStableDateLauncher() throws {
        let accessory = try source("Sources/MacWiki/Views/Columns/DirectoryColumnAccessoryView.swift")
        let directory = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let rows = try source("Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverRows.swift")
        let state = try source("Sources/MacWiki/Views/Sidebar/Directory/DirectoryColumnState.swift")
        let nativeControls = try source(
            "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverHeaderControls.swift"
        )

        let discoverControls = try slice(
            accessory,
            from: "private var discoverControls",
            to: "private var viewOptionsMenu"
        )

        #expect(accessory.contains("Text(\"\\(discoverArticleCount) articles\")"))
        #expect(accessory.contains("SidebarDiscoverHeaderControls("))
        #expect(discoverControls.contains("timeMachineAccessibilityValue:"))
        #expect(!discoverControls.contains("ViewThatFits"))
        #expect(nativeControls.contains("NSSegmentedControl"))
        #expect(nativeControls.contains("NSPopover"))
        #expect(nativeControls.contains("control.sizeToFit()"))
        #expect(!nativeControls.contains("control.setWidth("))
        #expect(accessory.contains("columnState.send(.refreshDiscover)"))
        #expect(state.contains("case refreshDiscover"))
        #expect(directory.contains("case .refreshDiscover:"))
        #expect(accessory.contains("SidebarDiscoverArticleInventory.articles(in: feed)"))
        #expect(
            directory.components(
                separatedBy: "SidebarDiscoverArticleInventory.renderedArticleRows(in: feed)"
            ).count - 1 == 2
        )
        #expect(directory.contains("let trendPulse = discoverTrendPulseStore.pulse(for: article.title)"))
        #expect(!directory.contains("showTrendPulse"))
        #expect(directory.contains("discoverPulseRefreshGeneration &+= 1"))
        #expect(directory.contains("refreshGeneration: discoverPulseRefreshGeneration"))
        #expect(directory.contains("pageViewsPresentation: SidebarPageViewsPopoverConfiguration("))
        let articleRows = try source(
            "Sources/MacWiki/Views/Sidebar/Directory/DirectoryArticleRowViews.swift"
        )
        #expect(articleRows.contains("SidebarPageViewsPopoverButton(configuration: pageViewsPresentation)"))
        #expect(!articleRows.contains(".labelStyle(.iconOnly)"))
        #expect(articleRows.components(separatedBy: "FlowLayout(spacing: 8)").count - 1 >= 2)
        #expect(articleRows.components(separatedBy: ".fixedSize(horizontal: true, vertical: false)").count - 1 >= 4)
        #expect(rows.contains("struct SidebarDiscoverSectionHeader: View"))
        #expect(rows.contains("struct SidebarDiscoverStatsButton: View"))
        #expect(rows.contains("SidebarPageViewsPopoverButton("))
        #expect(!rows.contains(".popover(isPresented:"))
        #expect(rows.contains(".textCase(.uppercase)"))
        #expect(rows.contains(".font(.caption2.monospacedDigit())"))
    }

    @Test func discoverSidebarPopoversShareOneAppKitPresentationOwner() throws {
        let pageViewsButton = try source(
            "Sources/MacWiki/Views/Sidebar/Directory/SidebarPageViewsPopoverButton.swift"
        )
        let timeMachineControls = try source(
            "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverHeaderControls.swift"
        )
        let rows = try source(
            "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverRows.swift"
        )
        let directory = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let discoverRows = try slice(
            directory,
            from: "private func discoverArticleRow(",
            to: "private func discoverArticle(from result:"
        )

        #expect(pageViewsButton.contains("struct SidebarPageViewsPopoverButton: NSViewRepresentable"))
        #expect(pageViewsButton.contains("final class Coordinator: NSObject, NSPopoverDelegate"))
        #expect(pageViewsButton.contains("let popover = NSPopover()"))
        #expect(pageViewsButton.contains("NSHostingController(rootView: rootView)"))
        #expect(!pageViewsButton.contains("Task.sleep"))
        #expect(pageViewsButton.contains("if popover?.isShown == true || isAwaitingHandoff"))
        #expect(pageViewsButton.contains("closePopover(updateBinding: true)"))
        #expect(pageViewsButton.contains("name: .sidebarPageViewsWillPresent"))
        #expect(pageViewsButton.contains("object: window"))
        #expect(pageViewsButton.contains("name: .sidebarPageViewsHandoffReady"))
        #expect(pageViewsButton.contains("button.window === sourceWindow"))
        #expect(pageViewsButton.contains("setAccessibilityLabel(\"\\(title), \\(presentation.accessibilityLabel)\")"))
        #expect(pageViewsButton.contains("bezelStyle = style == .iconOnly ? .accessoryBarAction : .inline"))
        #expect(pageViewsButton.contains("width: max(28, base.width)"))
        #expect(timeMachineControls.contains("name: .sidebarPageViewsWillPresent"))
        #expect(timeMachineControls.contains("closeForPageViewsPresentation"))
        #expect(timeMachineControls.contains("hostControl?.window === sourceWindow"))
        #expect(timeMachineControls.contains("popoverDidClose"))
        #expect(timeMachineControls.contains("name: .sidebarPageViewsHandoffReady"))
        #expect(timeMachineControls.contains("let pendingHandoffWindow = pendingPageViewsHandoffWindow"))
        #expect(timeMachineControls.contains("popover.behavior = .semitransient"))
        #expect(timeMachineControls.contains("popover?.animates = false"))
        #expect(timeMachineControls.contains("announcePageViewsHandoffReady(for: pendingHandoffWindow)"))
        #expect(rows.contains("SidebarPageViewsPopoverButton("))
        #expect(!rows.contains(".popover(isPresented:"))
        #expect(!discoverRows.contains(".popover(isPresented:"))
    }

    @Test @MainActor
    func discoverSidebarStatisticsPillsKeepReadableNativeMetrics() {
        let button = SidebarPageViewsPopoverButton.PageViewsButton()

        button.configure(
            pulse: nil,
            style: .pulse,
            title: "Readable statistics"
        )

        #expect(button.intrinsicContentSize.height >= 26)
        #expect(button.layer?.cornerRadius == 13)
        #expect(button.imageHugsTitle)
        #expect(button.alignment == .center)
        #expect(
            button.contentCompressionResistancePriority(for: .horizontal)
                == .required
        )
        #expect(button.contentHuggingPriority(for: .horizontal) == .required)
    }

    @Test func leavingDirectoryClearsPageViewsPresentationState() throws {
        let directory = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let rootSelectionLifecycle = try slice(
            directory,
            from: ".onChange(of: rootSelection) { _, newValue in",
            to: ".onDisappear {"
        )
        let disappearanceLifecycle = try slice(
            directory,
            from: ".onDisappear {",
            to: "private func reconcileSelectionAnchor("
        )

        for lifecycle in [rootSelectionLifecycle, disappearanceLifecycle] {
            #expect(lifecycle.contains("activePageViewsPopover = nil"))
            #expect(lifecycle.contains("pendingPageViewsRowKey = nil"))
        }
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func slice(_ source: String, from start: String, to end: String) throws -> String {
        let startRange = try #require(source.range(of: start))
        let endRange = try #require(source.range(of: end, range: startRange.upperBound..<source.endIndex))
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
