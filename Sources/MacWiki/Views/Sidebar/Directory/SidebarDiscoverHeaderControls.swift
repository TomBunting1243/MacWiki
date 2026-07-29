import AppKit
import SwiftUI

@MainActor
protocol SidebarPageViewsHeaderHandoffPresentation: AnyObject {
    var sidebarPageViewsPresentationOwner: AnyObject? { get }
    var sidebarPageViewsPresentedPopover: AnyObject? { get }
    var isSidebarPageViewsPresentedPopoverShown: Bool { get }

    func closePopoverForSidebarPageViewsHandoff()
}

/// Owns the notification ordering contract between the Time Machine popover
/// and the page-view presenter. Its owner identity is AppKit's window in the
/// app, while tests can exercise the same flow with ordinary object owners.
@MainActor
final class SidebarPageViewsHeaderHandoffCoordinator: NSObject {
    private weak var presentation: (any SidebarPageViewsHeaderHandoffPresentation)?
    private let notificationCenter: NotificationCenter
    private weak var pendingOwner: AnyObject?
    private var isObserving = true

    var hasPendingHandoff: Bool {
        pendingOwner != nil
    }

    init(
        presentation: any SidebarPageViewsHeaderHandoffPresentation,
        notificationCenter: NotificationCenter = .default
    ) {
        self.presentation = presentation
        self.notificationCenter = notificationCenter
        super.init()
        notificationCenter.addObserver(
            self,
            selector: #selector(closeForPageViewsPresentation(_:)),
            name: .sidebarPageViewsWillPresent,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        pendingOwner = nil
        notificationCenter.removeObserver(self)
    }

    @discardableResult
    func popoverDidClose(_ closedPopover: AnyObject) -> Bool {
        guard let presentation,
              SidebarPageViewsHandoffState.ownersMatch(
                closedPopover,
                presentation.sidebarPageViewsPresentedPopover
              ) else {
            return false
        }
        return completePendingHandoff()
    }

    /// Finishes a handoff when teardown deliberately removes the popover's
    /// delegate and closes it synchronously.
    @discardableResult
    func presentationClosedSynchronously() -> Bool {
        completePendingHandoff()
    }

    @objc
    private func closeForPageViewsPresentation(_ notification: Notification) {
        guard isObserving,
              let sourceOwner = notification.object as AnyObject?,
              let presentation,
              SidebarPageViewsHandoffState.ownersMatch(
                sourceOwner,
                presentation.sidebarPageViewsPresentationOwner
              ) else {
            return
        }

        guard presentation.isSidebarPageViewsPresentedPopoverShown else {
            announcePageViewsHandoffReady(for: sourceOwner)
            return
        }

        pendingOwner = sourceOwner
        presentation.closePopoverForSidebarPageViewsHandoff()
    }

    @discardableResult
    private func completePendingHandoff() -> Bool {
        guard let pendingOwner else { return false }
        self.pendingOwner = nil
        announcePageViewsHandoffReady(for: pendingOwner)
        return true
    }

    private func announcePageViewsHandoffReady(for sourceOwner: AnyObject) {
        notificationCenter.post(
            name: .sidebarPageViewsHandoffReady,
            object: sourceOwner
        )
    }
}

/// A platform-owned momentary segmented control for Discovery's split-item
/// accessory. AppKit owns the Time Machine popover because SwiftUI popovers do
/// not reliably present from `NSSplitViewItemAccessoryViewController` hosts.
struct SidebarDiscoverHeaderControls<PopoverContent: View>: NSViewRepresentable {
    let showsTimeMachine: Bool
    let isRefreshEnabled: Bool
    let timeMachineAccessibilityValue: String
    let onRefresh: () -> Void
    @ViewBuilder let popoverContent: () -> PopoverContent

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentStyle = .automatic
        control.trackingMode = .momentary
        control.controlSize = .regular
        control.target = context.coordinator
        control.action = #selector(Coordinator.activate(_:))
        control.setAccessibilityLabel("Discover Controls")
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.configure(
            control,
            showsTimeMachine: showsTimeMachine,
            isRefreshEnabled: isRefreshEnabled,
            timeMachineAccessibilityValue: timeMachineAccessibilityValue,
            onRefresh: onRefresh,
            popoverContent: AnyView(popoverContent())
        )
    }

    static func dismantleNSView(_ nsView: NSSegmentedControl, coordinator: Coordinator) {
        coordinator.invalidate()
        nsView.target = nil
        nsView.action = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate,
        SidebarPageViewsHeaderHandoffPresentation {
        private enum Action {
            case timeMachine
            case refresh
        }

        private var actions: [Action] = []
        private var onRefresh: (() -> Void)?
        private var popoverContent = AnyView(EmptyView())
        private var popover: NSPopover?
        private var hostingController: NSHostingController<AnyView>?
        private weak var hostControl: NSSegmentedControl?
        private var pageViewsHandoffCoordinator: SidebarPageViewsHeaderHandoffCoordinator!

        override init() {
            super.init()
            pageViewsHandoffCoordinator = SidebarPageViewsHeaderHandoffCoordinator(
                presentation: self
            )
        }

        func configure(
            _ control: NSSegmentedControl,
            showsTimeMachine: Bool,
            isRefreshEnabled: Bool,
            timeMachineAccessibilityValue: String,
            onRefresh: @escaping () -> Void,
            popoverContent: AnyView
        ) {
            hostControl = control
            self.onRefresh = onRefresh
            self.popoverContent = popoverContent
            hostingController?.rootView = popoverContent

            actions = showsTimeMachine ? [.timeMachine, .refresh] : [.refresh]
            control.segmentCount = actions.count
            control.setAccessibilityValue(timeMachineAccessibilityValue)

            for (index, action) in actions.enumerated() {
                switch action {
                case .timeMachine:
                    configureSegment(
                        index,
                        in: control,
                        label: "Time Machine",
                        systemImage: "calendar",
                        toolTip: "Browse Wikipedia editions from another day",
                        isEnabled: true
                    )
                case .refresh:
                    configureSegment(
                        index,
                        in: control,
                        label: "Refresh Discover",
                        systemImage: "arrow.clockwise",
                        toolTip: isRefreshEnabled ? "Refresh Discover" : "Refreshing Discover…",
                        isEnabled: isRefreshEnabled
                    )
                }
            }

            if !showsTimeMachine {
                closePopover()
            }
            control.selectedSegment = -1
            control.sizeToFit()
            control.invalidateIntrinsicContentSize()
        }

        private func configureSegment(
            _ index: Int,
            in control: NSSegmentedControl,
            label: String,
            systemImage: String,
            toolTip: String,
            isEnabled: Bool
        ) {
            let configuration = NSImage.SymbolConfiguration(
                pointSize: ChromeIconMetrics.symbolPointSize,
                weight: .regular
            )
            let image = NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: label
            )?.withSymbolConfiguration(configuration)

            control.setLabel("", forSegment: index)
            control.setImage(image, forSegment: index)
            control.setToolTip(toolTip, forSegment: index)
            control.setEnabled(isEnabled, forSegment: index)
        }

        @objc
        func activate(_ sender: NSSegmentedControl) {
            let selectedSegment = sender.selectedSegment
            guard actions.indices.contains(selectedSegment) else { return }

            switch actions[selectedSegment] {
            case .timeMachine:
                togglePopover(relativeTo: sender)
            case .refresh:
                onRefresh?()
            }
            sender.selectedSegment = -1
        }

        private func togglePopover(relativeTo control: NSSegmentedControl) {
            if popover?.isShown == true {
                closePopover()
                return
            }

            closePopover()
            let hostingController = NSHostingController(rootView: popoverContent)
            hostingController.sizingOptions = []
            let fittingSize = hostingController.sizeThatFits(
                in: NSSize(width: 320, height: 600)
            )

            let popover = NSPopover()
            // Keep same-window controls interactive so a statistics click
            // reaches its native button and can request the coordinated
            // Time Machine-to-statistics handoff on the first click.
            popover.behavior = .semitransient
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = hostingController
            popover.contentSize = NSSize(
                width: max(320, fittingSize.width),
                height: max(280, fittingSize.height)
            )

            self.hostingController = hostingController
            self.popover = popover
            popover.show(
                relativeTo: control.bounds,
                of: control,
                preferredEdge: .minY
            )
        }

        func closePopover() {
            let hasPendingHandoff = pageViewsHandoffCoordinator.hasPendingHandoff
            let popover = popover
            self.popover = nil
            hostingController = nil
            popover?.delegate = nil
            if hasPendingHandoff {
                // Teardown can race the delegate callback. Remove the remote
                // popover window synchronously before releasing a waiting
                // page-view presenter so the handoff cannot be stranded.
                popover?.animates = false
            }
            popover?.close()
            if hasPendingHandoff {
                pageViewsHandoffCoordinator.presentationClosedSynchronously()
            }
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closedPopover = notification.object as? NSPopover,
                  closedPopover === popover else {
                return
            }
            pageViewsHandoffCoordinator.popoverDidClose(closedPopover)
            popover = nil
            hostingController = nil
        }

        func invalidate() {
            closePopover()
            pageViewsHandoffCoordinator.stop()
        }

        var sidebarPageViewsPresentationOwner: AnyObject? {
            hostControl?.window
        }

        var sidebarPageViewsPresentedPopover: AnyObject? {
            popover
        }

        var isSidebarPageViewsPresentedPopoverShown: Bool {
            popover?.isShown == true
        }

        func closePopoverForSidebarPageViewsHandoff() {
            popover?.close()
        }
    }
}
