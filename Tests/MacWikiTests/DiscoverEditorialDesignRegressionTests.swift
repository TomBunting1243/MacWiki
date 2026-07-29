import AppKit
import SwiftUI
import Testing

@testable import MacWiki

@MainActor
private final class SidebarPageViewsNotificationRecorder: NSObject {
    private(set) var objects: [AnyObject] = []

    @objc
    func record(_ notification: Notification) {
        guard let object = notification.object as AnyObject? else { return }
        objects.append(object)
    }
}

@MainActor
private final class SidebarPageViewsHeaderPresentationSpy:
    SidebarPageViewsHeaderHandoffPresentation {
    let owner: AnyObject
    let presentedPopover: AnyObject
    var isPopoverShown: Bool
    private(set) var closeCount = 0

    init(
        owner: AnyObject,
        presentedPopover: AnyObject,
        isPopoverShown: Bool
    ) {
        self.owner = owner
        self.presentedPopover = presentedPopover
        self.isPopoverShown = isPopoverShown
    }

    var sidebarPageViewsPresentationOwner: AnyObject? {
        owner
    }

    var sidebarPageViewsPresentedPopover: AnyObject? {
        presentedPopover
    }

    var isSidebarPageViewsPresentedPopoverShown: Bool {
        isPopoverShown
    }

    func closePopoverForSidebarPageViewsHandoff() {
        closeCount += 1
    }
}

struct DiscoverEditorialDesignRegressionTests {
    @Test @MainActor
    func discoverSidebarHeaderControlsExposeDateAndRefreshSemantics() {
        var refreshCount = 0
        let coordinator = SidebarDiscoverHeaderControls<EmptyView>.Coordinator()
        let control = NSSegmentedControl()
        defer {
            coordinator.invalidate()
        }

        coordinator.configure(
            control,
            showsTimeMachine: true,
            isRefreshEnabled: true,
            timeMachineAccessibilityValue: "Wednesday, July 29, 2026",
            onRefresh: { refreshCount += 1 },
            popoverContent: AnyView(EmptyView())
        )

        #expect(control.segmentCount == 2)
        #expect(control.accessibilityValue() as? String == "Wednesday, July 29, 2026")
        #expect(control.toolTip(forSegment: 0) == "Browse Wikipedia editions from another day")
        #expect(control.toolTip(forSegment: 1) == "Refresh Discover")
        #expect(control.isEnabled(forSegment: 0))
        #expect(control.isEnabled(forSegment: 1))
        #expect(control.frame.width > 0)

        control.selectedSegment = 1
        coordinator.activate(control)

        #expect(refreshCount == 1)
        #expect(control.selectedSegment == -1)

        coordinator.configure(
            control,
            showsTimeMachine: false,
            isRefreshEnabled: false,
            timeMachineAccessibilityValue: "Updating Wednesday, July 29, 2026",
            onRefresh: { refreshCount += 1 },
            popoverContent: AnyView(EmptyView())
        )

        #expect(control.segmentCount == 1)
        #expect(control.toolTip(forSegment: 0) == "Refreshing Discover…")
        #expect(!control.isEnabled(forSegment: 0))

        let columnState = DirectoryColumnState()
        columnState.send(.refreshDiscover)
        #expect(columnState.commandRequest?.command == .refreshDiscover)
    }

    @Test @MainActor
    func pageViewsButtonRequestsOneNotificationHandoffAtATime() {
        let notificationCenter = NotificationCenter()
        let recorder = SidebarPageViewsNotificationRecorder()
        notificationCenter.addObserver(
            recorder,
            selector: #selector(SidebarPageViewsNotificationRecorder.record(_:)),
            name: .sidebarPageViewsWillPresent,
            object: nil
        )

        let button = SidebarPageViewsPopoverButton(
            configuration: SidebarPageViewsPopoverConfiguration(
                title: "Ada Lovelace",
                referenceDate: Date(timeIntervalSinceReferenceDate: 0),
                initialPulse: nil,
                style: .pulse,
                isPresented: .constant(false),
                onRequestPresentation: {}
            )
        )
        let coordinator = SidebarPageViewsPopoverButton.Coordinator(
            parent: button,
            notificationCenter: notificationCenter
        )
        let owner = NSObject()
        let otherOwner = NSObject()
        defer {
            notificationCenter.removeObserver(recorder)
            notificationCenter.removeObserver(coordinator)
        }

        #expect(coordinator.requestPresentationHandoff(owner: owner))
        #expect(recorder.objects.count == 1)
        #expect(recorder.objects.first === owner)

        #expect(!coordinator.requestPresentationHandoff(owner: otherOwner))
        #expect(recorder.objects.count == 1)

        coordinator.closePopover(updateBinding: false)
        #expect(coordinator.requestPresentationHandoff(owner: otherOwner))
        #expect(recorder.objects.count == 2)
        #expect(recorder.objects.last === otherOwner)
    }

    @Test
    func pageViewsHandoffCompletesOnlyForTheOriginalCurrentOwner() {
        let owner = NSObject()
        let otherOwner = NSObject()
        var state = SidebarPageViewsHandoffState()

        let began = state.begin(owner: owner)
        let wrongSource = state.complete(
            sourceOwner: otherOwner,
            currentControlOwner: owner
        )
        let movedControl = state.complete(
            sourceOwner: owner,
            currentControlOwner: otherOwner
        )

        #expect(began)
        #expect(!wrongSource)
        #expect(!movedControl)
        #expect(state.isAwaiting)
        let matchingOwner = state.complete(
            sourceOwner: owner,
            currentControlOwner: owner
        )
        #expect(matchingOwner)
        #expect(!state.isAwaiting)
    }

    @Test @MainActor
    func timeMachineHandoffClosesOnlyForItsOwnerAndWaitsForPopoverDidClose() {
        let notificationCenter = NotificationCenter()
        let owner = NSObject()
        let otherOwner = NSObject()
        let popover = NSObject()
        let otherPopover = NSObject()
        let presentation = SidebarPageViewsHeaderPresentationSpy(
            owner: owner,
            presentedPopover: popover,
            isPopoverShown: true
        )
        let coordinator = SidebarPageViewsHeaderHandoffCoordinator(
            presentation: presentation,
            notificationCenter: notificationCenter
        )
        let recorder = SidebarPageViewsNotificationRecorder()
        notificationCenter.addObserver(
            recorder,
            selector: #selector(SidebarPageViewsNotificationRecorder.record(_:)),
            name: .sidebarPageViewsHandoffReady,
            object: nil
        )
        defer {
            coordinator.stop()
            notificationCenter.removeObserver(recorder)
        }

        notificationCenter.post(
            name: .sidebarPageViewsWillPresent,
            object: otherOwner
        )
        #expect(presentation.closeCount == 0)
        #expect(recorder.objects.isEmpty)

        notificationCenter.post(
            name: .sidebarPageViewsWillPresent,
            object: owner
        )
        #expect(presentation.closeCount == 1)
        #expect(coordinator.hasPendingHandoff)
        #expect(recorder.objects.isEmpty)

        #expect(!coordinator.popoverDidClose(otherPopover))
        #expect(coordinator.hasPendingHandoff)
        #expect(coordinator.popoverDidClose(popover))
        #expect(!coordinator.hasPendingHandoff)
        #expect(recorder.objects.count == 1)
        #expect(recorder.objects.first === owner)

        presentation.isPopoverShown = false
        notificationCenter.post(
            name: .sidebarPageViewsWillPresent,
            object: owner
        )
        #expect(presentation.closeCount == 1)
        #expect(recorder.objects.count == 2)
        #expect(recorder.objects.last === owner)
    }

    @Test
    func leavingDirectoryDismissesAllPageViewsPresentationState() {
        var state = SidebarPageViewsPresentationState(
            pendingRowKey: "discover:ada-lovelace",
            activePopover: SidebarPageViewsPopoverPayload(
                rowKey: "discover:ada-lovelace",
                title: "Ada Lovelace",
                initialPulse: nil,
                referenceDate: Date(timeIntervalSinceReferenceDate: 0)
            )
        )

        state.dismissAll()

        #expect(state.pendingRowKey == nil)
        #expect(state.activePopover == nil)
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

    @Test
    func discoverMediaTitlesRemainReadableInsideTheViewer() {
        #expect(
            DiscoverMediaPresentation.displayTitle(for: "File:Ada_Lovelace.PNG")
                == "Ada Lovelace"
        )
        #expect(
            DiscoverMediaPresentation.displayTitle(for: "  ")
                == "Media image"
        )
    }

    @Test
    func hoverProfilesReserveLiftAndShadowForElevatedSurfaces() {
        #expect(DiscoverHoverEffect.Profile.hero.scale > 1)
        #expect(DiscoverHoverEffect.Profile.hero.activeYOffset < 0)
        #expect(DiscoverHoverEffect.Profile.hero.activeShadowOpacity > 0)
        #expect(DiscoverHoverEffect.Profile.card.scale > 1)
        #expect(DiscoverHoverEffect.Profile.card.activeYOffset < 0)
        #expect(DiscoverHoverEffect.Profile.card.activeShadowOpacity > 0)

        #expect(DiscoverHoverEffect.Profile.row.scale == 1)
        #expect(DiscoverHoverEffect.Profile.row.activeYOffset == 0)
        #expect(DiscoverHoverEffect.Profile.row.activeShadowOpacity == 0)
        #expect(DiscoverHoverEffect.Profile.chip.scale == 1)
        #expect(DiscoverHoverEffect.Profile.chip.activeYOffset == 0)
        #expect(DiscoverHoverEffect.Profile.chip.activeShadowOpacity == 0)
    }
}
