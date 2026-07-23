import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    /// Coordinates the two independently hosted Discover sidebar popovers.
    /// AppKit must finish closing Time Machine before page-view chrome joins
    /// the window ordering group on macOS 27.
    static let sidebarPageViewsWillPresent = Notification.Name(
        "com.tombunting.MacWiki.sidebarPageViewsWillPresent"
    )

    /// Sent by the window-local Time Machine coordinator only after its
    /// popover has actually finished closing. The originating `NSWindow` is
    /// carried as the notification object.
    static let sidebarPageViewsHandoffReady = Notification.Name(
        "com.tombunting.MacWiki.sidebarPageViewsHandoffReady"
    )
}

enum SidebarPageViewsButtonStyle {
    case pulse
    case iconOnly
}

struct SidebarPageViewsPopoverConfiguration {
    let title: String
    let referenceDate: Date
    let initialPulse: WikipediaService.TrendPulse?
    let style: SidebarPageViewsButtonStyle
    let isPresented: Binding<Bool>
    let onRequestPresentation: () -> Void
    var onPulseLoaded: ((WikipediaService.TrendPulse) -> Void)? = nil
}

/// A native AppKit button and popover for Discover's sidebar statistics.
///
/// Discover's rows and Time Machine live in separate AppKit hosting
/// controllers. Presenting a SwiftUI `.popover` while the native Time Machine
/// popover was dismissing could trap in ViewBridge on macOS 27. Keeping the
/// complete presentation lifecycle in AppKit gives the window server one
/// ordering owner and preserves a normal transient-popover interaction.
struct SidebarPageViewsPopoverButton: NSViewRepresentable {
    let configuration: SidebarPageViewsPopoverConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> PageViewsButton {
        let button = PageViewsButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.press(_:))
        button.setButtonType(.momentaryPushIn)
        button.focusRingType = .exterior
        context.coordinator.configure(button, with: configuration)
        return button
    }

    func updateNSView(_ button: PageViewsButton, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configure(button, with: configuration)
        context.coordinator.reconcilePresentation(relativeTo: button)
    }

    static func dismantleNSView(_ button: PageViewsButton, coordinator: Coordinator) {
        coordinator.closePopover(updateBinding: false)
        button.target = nil
        button.action = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        var parent: SidebarPageViewsPopoverButton
        private var popover: NSPopover?
        private weak var presentationButton: PageViewsButton?
        private var isAwaitingHandoff = false
        private var activeIdentity: String?

        init(parent: SidebarPageViewsPopoverButton) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(completePresentationHandoff(_:)),
                name: .sidebarPageViewsHandoffReady,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc
        func press(_ sender: PageViewsButton) {
            if popover?.isShown == true || isAwaitingHandoff {
                closePopover(updateBinding: true)
                return
            }
            parent.configuration.onRequestPresentation()
            requestPresentationHandoff(relativeTo: sender)
        }

        func configure(
            _ button: PageViewsButton,
            with configuration: SidebarPageViewsPopoverConfiguration
        ) {
            button.target = self
            button.action = #selector(press(_:))
            presentationButton = button
            button.configure(
                pulse: configuration.initialPulse,
                style: configuration.style,
                title: configuration.title
            )
        }

        func reconcilePresentation(relativeTo button: PageViewsButton) {
            guard parent.configuration.isPresented.wrappedValue else {
                closePopover(updateBinding: false)
                return
            }

            let identity = presentationIdentity(for: parent.configuration)
            if let activeIdentity, activeIdentity != identity {
                closePopover(updateBinding: false)
            }
            guard popover == nil, !isAwaitingHandoff else { return }
            requestPresentationHandoff(relativeTo: button)
        }

        func closePopover(updateBinding: Bool) {
            isAwaitingHandoff = false
            let popover = popover
            self.popover = nil
            activeIdentity = nil
            popover?.delegate = nil
            popover?.close()
            if updateBinding, parent.configuration.isPresented.wrappedValue {
                parent.configuration.isPresented.wrappedValue = false
            }
        }

        private func requestPresentationHandoff(relativeTo button: PageViewsButton) {
            guard !isAwaitingHandoff,
                  let window = button.window else {
                return
            }
            presentationButton = button
            isAwaitingHandoff = true
            NotificationCenter.default.post(
                name: .sidebarPageViewsWillPresent,
                object: window
            )
        }

        @objc
        private func completePresentationHandoff(_ notification: Notification) {
            guard isAwaitingHandoff,
                  let sourceWindow = notification.object as? NSWindow,
                  let button = presentationButton,
                  button.window === sourceWindow else {
                return
            }
            isAwaitingHandoff = false
            guard parent.configuration.isPresented.wrappedValue,
                  button.window != nil,
                  popover == nil else {
                return
            }
            presentPopover(
                relativeTo: button,
                identity: presentationIdentity(for: parent.configuration)
            )
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closedPopover = notification.object as? NSPopover,
                  closedPopover === popover else {
                return
            }
            popover = nil
            activeIdentity = nil
            if parent.configuration.isPresented.wrappedValue {
                parent.configuration.isPresented.wrappedValue = false
            }
        }

        private func presentPopover(relativeTo button: NSButton, identity: String) {
            let configuration = parent.configuration
            let rootView = AnyView(
                SidebarPageViewsPopoverContent(
                    title: configuration.title,
                    referenceDate: configuration.referenceDate,
                    initialPulse: configuration.initialPulse,
                    onPulseLoaded: configuration.onPulseLoaded
                )
                .defaultAppStorage(MacWikiDefaults.current)
            )
            let hostingController = NSHostingController(rootView: rootView)
            hostingController.sizingOptions = [.preferredContentSize]
            let fittingSize = hostingController.sizeThatFits(
                in: NSSize(width: 420, height: 720)
            )
            hostingController.preferredContentSize = NSSize(
                width: max(300, min(fittingSize.width, 420)),
                height: max(120, min(fittingSize.height, 720))
            )

            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
            popover.contentViewController = hostingController
            self.popover = popover
            activeIdentity = identity
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .maxX
            )
        }

        private func presentationIdentity(
            for configuration: SidebarPageViewsPopoverConfiguration
        ) -> String {
            let title = titleMatchKey(configuration.title)
            let day = Calendar.current.startOfDay(for: configuration.referenceDate)
            return "\(title)|\(Int(day.timeIntervalSinceReferenceDate))"
        }
    }
}

extension SidebarPageViewsPopoverButton {
    final class PageViewsButton: NSButton {
        private var restingBackgroundColor = NSColor.clear
        private var hoverBackgroundColor = NSColor.clear
        private var pressedBackgroundColor = NSColor.clear
        private var trackingAreaReference: NSTrackingArea?
        private var layoutStyle: SidebarPageViewsButtonStyle = .pulse

        override var intrinsicContentSize: NSSize {
            let base = super.intrinsicContentSize
            switch layoutStyle {
            case .pulse:
                return NSSize(width: base.width + 14, height: max(21, base.height + 4))
            case .iconOnly:
                return NSSize(width: max(28, base.width), height: max(28, base.height))
            }
        }

        func configure(
            pulse: WikipediaService.TrendPulse?,
            style: SidebarPageViewsButtonStyle,
            title: String
        ) {
            layoutStyle = style
            isBordered = style == .iconOnly
            bezelStyle = style == .iconOnly ? .accessoryBarAction : .inline
            imagePosition = style == .iconOnly ? .imageOnly : .imageLeading
            imageScaling = .scaleProportionallyDown
            wantsLayer = style == .pulse
            layer?.masksToBounds = style == .pulse
            layer?.cornerRadius = style == .pulse ? 10.5 : 0
            layer?.borderWidth = style == .pulse ? 0.7 : 0

            let presentation = PulsePresentation(pulse: pulse)
            let symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: style == .iconOnly ? ChromeIconMetrics.symbolPointSize : 10,
                weight: .semibold
            )
            image = NSImage(
                systemSymbolName: style == .iconOnly
                    ? "chart.xyaxis.line"
                    : presentation.symbolName,
                accessibilityDescription: "View statistics"
            )?.withSymbolConfiguration(symbolConfiguration)
            contentTintColor = presentation.tint

            switch style {
            case .pulse:
                attributedTitle = presentation.attributedTitle
                toolTip = "Views from recent daily pageviews"
                setAccessibilityLabel("\(title), \(presentation.accessibilityLabel)")
                setAccessibilityHelp("Show recent pageview chart")
                restingBackgroundColor = presentation.tint.withAlphaComponent(0.10)
                hoverBackgroundColor = presentation.tint.withAlphaComponent(0.17)
                pressedBackgroundColor = presentation.tint.withAlphaComponent(0.23)
                layer?.borderColor = presentation.tint.withAlphaComponent(0.18).cgColor
            case .iconOnly:
                attributedTitle = NSAttributedString(string: "")
                toolTip = "View page statistics"
                setAccessibilityLabel("View statistics for \(title)")
                setAccessibilityHelp("View page statistics")
                restingBackgroundColor = .clear
                hoverBackgroundColor = .clear
                pressedBackgroundColor = .clear
            }
            if style == .pulse {
                layer?.backgroundColor = restingBackgroundColor.cgColor
            }
            invalidateIntrinsicContentSize()
        }

        override func updateTrackingAreas() {
            if let trackingAreaReference {
                removeTrackingArea(trackingAreaReference)
                self.trackingAreaReference = nil
            }
            guard layoutStyle == .pulse else {
                super.updateTrackingAreas()
                return
            }
            let trackingArea = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(trackingArea)
            trackingAreaReference = trackingArea
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) {
            if layoutStyle == .pulse {
                layer?.backgroundColor = hoverBackgroundColor.cgColor
            }
            super.mouseEntered(with: event)
        }

        override func mouseExited(with event: NSEvent) {
            if layoutStyle == .pulse {
                layer?.backgroundColor = restingBackgroundColor.cgColor
            }
            super.mouseExited(with: event)
        }

        override func highlight(_ flag: Bool) {
            super.highlight(flag)
            if layoutStyle == .pulse {
                layer?.backgroundColor = (
                    flag ? pressedBackgroundColor : restingBackgroundColor
                ).cgColor
            }
        }
    }

    private struct PulsePresentation {
        let symbolName: String
        let deltaText: String
        let viewsText: String?
        let tint: NSColor

        init(pulse: WikipediaService.TrendPulse?) {
            guard let pulse else {
                symbolName = "chart.xyaxis.line"
                deltaText = "Views"
                viewsText = nil
                tint = .secondaryLabelColor
                return
            }

            let deltaFraction: Double? = if let previous = pulse.previousViews, previous > 0 {
                Double(pulse.latestViews - previous) / Double(previous)
            } else {
                nil
            }
            symbolName = (deltaFraction ?? 0) < 0
                ? "chart.line.downtrend.xyaxis"
                : "chart.line.uptrend.xyaxis"
            deltaText = ArticlePresentationFormatter.pageViewDeltaText(
                latestViews: pulse.latestViews,
                previousViews: pulse.previousViews,
                fallback: "Views"
            )
            viewsText = "\(abbreviatedViewCount(pulse.latestViews)) views"
            if let deltaFraction, deltaFraction > 0 {
                tint = .systemGreen.withAlphaComponent(0.9)
            } else if let deltaFraction, deltaFraction < 0 {
                tint = .systemRed.withAlphaComponent(0.85)
            } else {
                tint = .secondaryLabelColor
            }
        }

        var attributedTitle: NSAttributedString {
            let result = NSMutableAttributedString(
                string: deltaText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: tint
                ]
            )
            if let viewsText {
                result.append(NSAttributedString(
                    string: "  \(viewsText)",
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                ))
            }
            return result
        }

        var accessibilityLabel: String {
            [deltaText, viewsText].compactMap { $0 }.joined(separator: ", ")
        }
    }
}
