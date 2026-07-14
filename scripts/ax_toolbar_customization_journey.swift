#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

private enum JourneyError: LocalizedError {
    case usage
    case missing(String)
    case action(String, AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_toolbar_customization_journey.swift <pid> [verify-order]"
        case .missing(let description):
            description
        case .action(let label, let error):
            "\(label) rejected AXPress (\(error.rawValue))."
        }
    }
}

private func attributeValue(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func stringAttribute(_ name: CFString, from element: AXUIElement) -> String {
    guard let value = attributeValue(name, from: element) else { return "" }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return ""
}

private func directChildren(of element: AXUIElement) -> [AXUIElement] {
    attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
}

private func descendants(in root: AXUIElement, limit: Int = 1_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    var index = 0
    while index < pending.count, result.count < limit {
        let element = pending[index]
        index += 1
        result.append(element)
        pending.append(contentsOf: directChildren(of: element))
    }
    return result
}

private func labels(of element: AXUIElement) -> [String] {
    [
        stringAttribute(kAXTitleAttribute as CFString, from: element),
        stringAttribute(kAXDescriptionAttribute as CFString, from: element),
        stringAttribute(kAXValueAttribute as CFString, from: element)
    ].filter { !$0.isEmpty }
}

private func labeledElement(
    in root: AXUIElement,
    role: String? = nil,
    containing text: String
) -> AXUIElement? {
    descendants(in: root).first { element in
        if let role,
           stringAttribute(kAXRoleAttribute as CFString, from: element) != role {
            return false
        }
        return labels(of: element).contains {
            $0.localizedCaseInsensitiveContains(text)
        }
    }
}

private func press(_ element: AXUIElement, label: String) throws {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else { throw JourneyError.action(label, result) }
}

private func wait(
    timeout: TimeInterval = 5,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    } while Date() < deadline
    return false
}

private func settleCustomizationEdit() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
}

private func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attributeValue(kAXPositionAttribute as CFString, from: element),
          let sizeValue = attributeValue(kAXSizeAttribute as CFString, from: element),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        return nil
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

private func postMouseEvent(
    _ type: CGEventType,
    at point: CGPoint,
    source: CGEventSource
) throws {
    guard let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else {
        throw JourneyError.missing("Unable to create a mouse event.")
    }
    event.post(tap: .cghidEventTap)
}

private func drag(from start: CGPoint, to end: CGPoint) throws {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        throw JourneyError.missing("Unable to create a mouse event source.")
    }
    var latestPoint = start
    var isLeftMouseDown = false
    defer {
        if isLeftMouseDown {
            try? postMouseEvent(.leftMouseUp, at: latestPoint, source: source)
        }
    }

    try postMouseEvent(.mouseMoved, at: start, source: source)
    Thread.sleep(forTimeInterval: 0.1)
    try postMouseEvent(.leftMouseDown, at: start, source: source)
    isLeftMouseDown = true
    for step in 1...42 {
        let progress = CGFloat(step) / 42
        let point = CGPoint(
            x: start.x + ((end.x - start.x) * progress),
            y: start.y + ((end.y - start.y) * progress)
        )
        latestPoint = point
        try postMouseEvent(.leftMouseDragged, at: point, source: source)
        Thread.sleep(forTimeInterval: 0.012)
    }
    try postMouseEvent(.leftMouseUp, at: end, source: source)
    isLeftMouseDown = false
}

private func mainWindow(in application: AXUIElement) -> AXUIElement? {
    let windows = attributeValue(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement] ?? []
    return windows.first {
        stringAttribute(kAXTitleAttribute as CFString, from: $0) == "MacWiki"
    }
}

private func isFrontmost(_ application: AXUIElement) -> Bool {
    (attributeValue(kAXFrontmostAttribute as CFString, from: application) as? NSNumber)?
        .boolValue == true
}

private func activateTarget(
    pid: pid_t,
    application: AXUIElement,
    window: AXUIElement
) throws {
    guard let runningApplication = NSRunningApplication(processIdentifier: pid),
          !runningApplication.isTerminated else {
        throw JourneyError.missing("The target MacWiki process exited.")
    }
    _ = runningApplication.activate(options: [.activateAllWindows])
    _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    guard wait(timeout: 8, condition: { isFrontmost(application) }) else {
        throw JourneyError.missing("MacWiki did not become the frontmost application.")
    }
}

private func customizationContainer(
    in application: AXUIElement,
    mainWindow window: AXUIElement
) -> AXUIElement? {
    let sheets = attributeValue("AXSheets" as CFString, from: window) as? [AXUIElement] ?? []
    if let sheet = sheets.first ?? directChildren(of: window).first(where: {
        stringAttribute(kAXRoleAttribute as CFString, from: $0) == kAXSheetRole as String
    }) {
        return sheet
    }

    let windows = attributeValue(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement] ?? []
    return windows.first { candidate in
        !CFEqual(candidate, window)
            && labels(of: candidate).contains {
                $0.localizedCaseInsensitiveContains("toolbar")
                    || $0.localizedCaseInsensitiveContains("customize")
            }
    }
}

private func nativeToolbar(in window: AXUIElement) -> AXUIElement? {
    directChildren(of: window).first {
        stringAttribute(kAXRoleAttribute as CFString, from: $0) == kAXToolbarRole as String
    }
}

private func inspectorItem(in toolbar: AXUIElement) -> AXUIElement? {
    labeledElement(in: toolbar, role: kAXButtonRole as String, containing: "Inspector")
}

private func readerStyleItem(in toolbar: AXUIElement) -> AXUIElement? {
    labeledElement(in: toolbar, role: kAXButtonRole as String, containing: "Reader Style")
}

private func pageViewsItem(in toolbar: AXUIElement) -> AXUIElement? {
    labeledElement(in: toolbar, role: kAXButtonRole as String, containing: "Page Views")
}

private func openCustomization(
    in application: AXUIElement,
    mainWindow window: AXUIElement
) throws -> AXUIElement {
    if let existing = customizationContainer(in: application, mainWindow: window) {
        return existing
    }
    guard let menuBar = attributeValue(kAXMenuBarAttribute as CFString, from: application),
          CFGetTypeID(menuBar) == AXUIElementGetTypeID() else {
        throw JourneyError.missing("The MacWiki menu bar is unavailable.")
    }
    let menuBarElement = menuBar as! AXUIElement
    guard let viewMenu = labeledElement(
        in: menuBarElement,
        role: kAXMenuBarItemRole as String,
        containing: "View"
    ) else {
        throw JourneyError.missing("The View menu is unavailable.")
    }
    try press(viewMenu, label: "View")
    guard wait(condition: {
        labeledElement(
            in: menuBarElement,
            role: kAXMenuItemRole as String,
            containing: "Customize Toolbar"
        ) != nil
    }), let customize = labeledElement(
        in: menuBarElement,
        role: kAXMenuItemRole as String,
        containing: "Customize Toolbar"
    ) else {
        throw JourneyError.missing("View > Customize Toolbar is unavailable.")
    }
    try press(customize, label: "Customize Toolbar")
    guard wait(timeout: 8, condition: {
        customizationContainer(in: application, mainWindow: window) != nil
    }), let sheet = customizationContainer(in: application, mainWindow: window) else {
        throw JourneyError.missing("The native toolbar customization sheet did not appear.")
    }
    return sheet
}

private func closeCustomization(
    _ sheet: AXUIElement,
    application: AXUIElement,
    window: AXUIElement
) throws {
    guard let done = labeledElement(
        in: sheet,
        role: kAXButtonRole as String,
        containing: "Done"
    ) else {
        throw JourneyError.missing("The customization sheet omitted Done.")
    }
    try press(done, label: "Done")
    guard wait(condition: {
        customizationContainer(in: application, mainWindow: window) == nil
    }) else {
        throw JourneyError.missing("The customization sheet did not close.")
    }
}

private func run() throws {
    guard (2...3).contains(CommandLine.arguments.count),
          let pid = Int32(CommandLine.arguments[1]) else {
        throw JourneyError.usage
    }
    guard AXIsProcessTrusted() else {
        throw JourneyError.missing("Accessibility access is unavailable.")
    }

    let application = AXUIElementCreateApplication(pid)
    guard wait(timeout: 15, condition: {
        guard let runningApplication = NSRunningApplication(processIdentifier: pid),
              !runningApplication.isTerminated,
              let window = mainWindow(in: application) else {
            return false
        }
        return nativeToolbar(in: window) != nil
    }), let window = mainWindow(in: application),
          let toolbar = nativeToolbar(in: window) else {
        throw JourneyError.missing("The MacWiki main window and native toolbar did not become ready.")
    }
    try activateTarget(pid: pid, application: application, window: window)

    let originalCursorPosition = CGEvent(source: nil)?.location
    defer {
        if let originalCursorPosition,
           let source = CGEventSource(stateID: .combinedSessionState) {
            try? postMouseEvent(.mouseMoved, at: originalCursorPosition, source: source)
        }
    }

    if CommandLine.arguments.last == "verify-order" {
        guard let readerStyle = readerStyleItem(in: toolbar),
              let pageViews = pageViewsItem(in: toolbar),
              let inspector = inspectorItem(in: toolbar),
              let readerStyleFrame = frame(of: readerStyle),
              let pageViewsFrame = frame(of: pageViews),
              let inspectorFrame = frame(of: inspector),
              readerStyleFrame.midX < pageViewsFrame.midX,
              pageViewsFrame.midX < inspectorFrame.midX else {
            throw JourneyError.missing("The customized Reader Style-before-Page Views order did not persist inside the reader zone.")
        }
        print("Toolbar customization persisted: Reader Style remains before Page Views and left of fixed Inspector after relaunch.")
        return
    }

    let sheet = try openCustomization(in: application, mainWindow: window)
    guard let readerStyle = readerStyleItem(in: toolbar),
          let readerStyleFrame = frame(of: readerStyle),
          let sheetFrame = frame(of: sheet) else {
        throw JourneyError.missing("The Reader Style item or customization sheet has no usable frame.")
    }
    try activateTarget(pid: pid, application: application, window: window)
    guard customizationContainer(in: application, mainWindow: window).map({ CFEqual($0, sheet) }) == true else {
        throw JourneyError.missing("The target customization sheet lost focus before the drag.")
    }
    try drag(
        from: CGPoint(x: readerStyleFrame.midX, y: readerStyleFrame.midY),
        to: CGPoint(x: sheetFrame.midX, y: sheetFrame.midY)
    )
    guard wait(condition: {
        guard let refreshedToolbar = nativeToolbar(in: window) else { return false }
        return readerStyleItem(in: refreshedToolbar) == nil
            && inspectorItem(in: refreshedToolbar) != nil
    }) else {
        throw JourneyError.missing("Dragging Reader Style out failed, or the fixed Inspector moved.")
    }
    settleCustomizationEdit()
    try closeCustomization(sheet, application: application, window: window)

    let replacementSheet = try openCustomization(in: application, mainWindow: window)
    guard let paletteReaderStyle = labeledElement(
        in: replacementSheet,
        role: kAXImageRole as String,
        containing: "Reader Style"
    ), let paletteFrame = frame(of: paletteReaderStyle),
          let currentToolbar = nativeToolbar(in: window),
          let pageViews = pageViewsItem(in: currentToolbar),
          let pageViewsFrame = frame(of: pageViews) else {
        throw JourneyError.missing("The Reader Style palette item or Page Views insertion target is unavailable.")
    }
    try activateTarget(pid: pid, application: application, window: window)
    guard customizationContainer(in: application, mainWindow: window).map({ CFEqual($0, replacementSheet) }) == true else {
        throw JourneyError.missing("The target customization sheet lost focus before the drag.")
    }
    try drag(
        from: CGPoint(x: paletteFrame.midX, y: paletteFrame.midY),
        to: CGPoint(x: pageViewsFrame.minX - 8, y: pageViewsFrame.midY)
    )
    guard wait(condition: {
        guard let refreshedToolbar = nativeToolbar(in: window),
              let insertedReaderStyle = readerStyleItem(in: refreshedToolbar),
              let refreshedPageViews = pageViewsItem(in: refreshedToolbar),
              let fixedInspector = inspectorItem(in: refreshedToolbar),
              let insertedFrame = frame(of: insertedReaderStyle),
              let refreshedPageViewsFrame = frame(of: refreshedPageViews),
              let inspectorFrame = frame(of: fixedInspector) else {
            return false
        }
        return insertedFrame.midX < refreshedPageViewsFrame.midX
            && refreshedPageViewsFrame.midX < inspectorFrame.midX
    }) else {
        throw JourneyError.missing("Dragging Reader Style back did not insert it before Page Views inside the reader zone.")
    }

    guard let refreshedToolbar = nativeToolbar(in: window),
          let insertedReaderStyle = readerStyleItem(in: refreshedToolbar),
          let fixedInspector = inspectorItem(in: refreshedToolbar),
          let insertedFrame = frame(of: insertedReaderStyle),
          let inspectorFrame = frame(of: fixedInspector) else {
        throw JourneyError.missing("Reader Style or fixed Inspector became unavailable before the boundary probe.")
    }
    try activateTarget(pid: pid, application: application, window: window)
    guard customizationContainer(in: application, mainWindow: window).map({ CFEqual($0, replacementSheet) }) == true else {
        throw JourneyError.missing("The target customization sheet lost focus before the boundary probe.")
    }
    try drag(
        from: CGPoint(x: insertedFrame.midX, y: insertedFrame.midY),
        to: CGPoint(x: inspectorFrame.maxX + 12, y: inspectorFrame.midY)
    )
    guard wait(condition: {
        guard let currentToolbar = nativeToolbar(in: window),
              let currentReaderStyle = readerStyleItem(in: currentToolbar),
              let currentInspector = inspectorItem(in: currentToolbar),
              let currentReaderStyleFrame = frame(of: currentReaderStyle),
              let currentInspectorFrame = frame(of: currentInspector) else {
            return false
        }
        return currentReaderStyleFrame.midX < currentInspectorFrame.midX
    }) else {
        throw JourneyError.missing("Reader Style crossed the fixed reader-inspector boundary.")
    }
    settleCustomizationEdit()
    try closeCustomization(replacementSheet, application: application, window: window)
    guard wait(timeout: 5, condition: {
        guard let committedToolbar = nativeToolbar(in: window),
              let committedReaderStyle = readerStyleItem(in: committedToolbar),
              let committedPageViews = pageViewsItem(in: committedToolbar),
              let committedInspector = inspectorItem(in: committedToolbar),
              let committedReaderStyleFrame = frame(of: committedReaderStyle),
              let committedPageViewsFrame = frame(of: committedPageViews),
              let committedInspectorFrame = frame(of: committedInspector) else {
            return false
        }
        return committedReaderStyleFrame.midX < committedPageViewsFrame.midX
            && committedPageViewsFrame.midX < committedInspectorFrame.midX
    }) else {
        throw JourneyError.missing("Done reverted the reader-scoped order or moved a control past Inspector.")
    }
    print("Toolbar customization passed: removed Reader Style, restored it before Page Views, rejected a cross-boundary move, kept Inspector fixed, and committed Done.")
}

do {
    try run()
} catch {
    fputs("ax_toolbar_customization_journey: \(error.localizedDescription)\n", stderr)
    exit(1)
}
