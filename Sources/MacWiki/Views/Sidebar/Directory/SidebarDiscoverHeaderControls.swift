import AppKit
import SwiftUI

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
        coordinator.closePopover()
        nsView.target = nil
        nsView.action = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
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
        private weak var pendingPageViewsHandoffWindow: NSWindow?

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(closeForPageViewsPresentation),
                name: .sidebarPageViewsWillPresent,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
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
            popover.behavior = .transient
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
            let pendingHandoffWindow = pendingPageViewsHandoffWindow
            pendingPageViewsHandoffWindow = nil
            let popover = popover
            self.popover = nil
            hostingController = nil
            popover?.delegate = nil
            if pendingHandoffWindow != nil {
                // Teardown can race the delegate callback. Remove the remote
                // popover window synchronously before releasing a waiting
                // page-view presenter so the handoff cannot be stranded.
                popover?.animates = false
            }
            popover?.close()
            if let pendingHandoffWindow {
                announcePageViewsHandoffReady(for: pendingHandoffWindow)
            }
        }

        @objc
        private func closeForPageViewsPresentation(_ notification: Notification) {
            guard let sourceWindow = notification.object as? NSWindow,
                  hostControl?.window === sourceWindow else {
                return
            }

            guard popover?.isShown == true else {
                announcePageViewsHandoffReady(for: sourceWindow)
                return
            }

            pendingPageViewsHandoffWindow = sourceWindow
            popover?.close()
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closedPopover = notification.object as? NSPopover,
                  closedPopover === popover else {
                return
            }
            popover = nil
            hostingController = nil
            if let sourceWindow = pendingPageViewsHandoffWindow {
                pendingPageViewsHandoffWindow = nil
                announcePageViewsHandoffReady(for: sourceWindow)
            }
        }

        private func announcePageViewsHandoffReady(for sourceWindow: NSWindow) {
            NotificationCenter.default.post(
                name: .sidebarPageViewsHandoffReady,
                object: sourceWindow
            )
        }
    }
}
