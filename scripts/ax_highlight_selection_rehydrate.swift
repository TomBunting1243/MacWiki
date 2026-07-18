#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum HighlightSelectionError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case missing(String)
    case invalid(String)
    case actionFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_highlight_selection_rehydrate.swift <create|rehydrate> <pid> <selected text>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missing(let message), .invalid(let message):
            message
        case .actionFailed(let label, let error):
            "\(label) rejected its accessibility action (\(error.rawValue))."
        }
    }
}

private enum JourneyMode: String, Codable {
    case create
    case rehydrate
}

private struct JourneyResult: Codable {
    let mode: JourneyMode
    let pid: Int32
    let selectedText: String
    let selectionBoundsX: Double
    let selectionBoundsY: Double
    let selectionBoundsWidth: Double
    let selectionBoundsHeight: Double
    let nativeMenuAction: String
    let notesRowVisible: Bool
    let renderedHighlightContextMenuVisible: Bool
}

private func attributeValue(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func stringAttribute(_ name: CFString, from element: AXUIElement) -> String {
    guard let value = attributeValue(name, from: element) else { return "" }
    if let string = value as? String { return string }
    if let attributed = value as? NSAttributedString { return attributed.string }
    if let number = value as? NSNumber { return number.stringValue }
    return ""
}

private func strings(of element: AXUIElement) -> [String] {
    [
        stringAttribute(kAXTitleAttribute as CFString, from: element),
        stringAttribute(kAXDescriptionAttribute as CFString, from: element),
        stringAttribute(kAXValueAttribute as CFString, from: element),
        stringAttribute(kAXHelpAttribute as CFString, from: element)
    ].filter { !$0.isEmpty }
}

private func role(of element: AXUIElement) -> String {
    stringAttribute(kAXRoleAttribute as CFString, from: element)
}

private func elements(in root: AXUIElement, limit: Int = 10_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    var nextIndex = 0

    while nextIndex < pending.count, result.count < limit {
        let element = pending[nextIndex]
        nextIndex += 1
        result.append(element)

        // The driver uses the web area's parameterized text APIs directly. Skipping
        // its large semantic subtree keeps native control and menu queries bounded.
        guard role(of: element) != "AXWebArea" else { continue }
        let children = attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
        pending.append(contentsOf: children)
    }
    return result
}

private func actionNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func wait(timeout: TimeInterval = 45, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.12)
    } while Date() < deadline
    return false
}

private func element(
    in application: AXUIElement,
    role expectedRole: String? = nil,
    named name: String,
    matchingContains: Bool = false,
    requiringAction action: String? = nil
) -> AXUIElement? {
    elements(in: application).first { candidate in
        if let expectedRole, role(of: candidate) != expectedRole { return false }
        let matches = strings(of: candidate).contains { value in
            matchingContains ? value.contains(name) : value == name
        }
        guard matches else { return false }
        if let action { return actionNames(of: candidate).contains(action) }
        return true
    }
}

private func perform(_ action: String, on element: AXUIElement, label: String) throws {
    let result = AXUIElementPerformAction(element, action as CFString)
    guard result == .success else { throw HighlightSelectionError.actionFailed(label, result) }
}

private func chooseMenuItem(_ element: AXUIElement, label: String) throws {
    if actionNames(of: element).contains("AXPick") {
        try perform("AXPick", on: element, label: label)
    } else {
        try perform(kAXPressAction as String, on: element, label: label)
    }
}

private func pressButton(in application: AXUIElement, named name: String) throws {
    var lastError = AXError.cannotComplete
    let succeeded = wait(timeout: 8) {
        guard let button = element(
            in: application,
            role: kAXButtonRole as String,
            named: name,
            requiringAction: kAXPressAction as String
        ) else { return false }
        lastError = AXUIElementPerformAction(button, kAXPressAction as CFString)
        return lastError == .success
    }
    guard succeeded else {
        if lastError == .cannotComplete {
            throw HighlightSelectionError.missing("Reader omitted an actionable \(name) inspector control.")
        }
        throw HighlightSelectionError.actionFailed(name, lastError)
    }
}

private func pressInspectorMode(in application: AXUIElement, named name: String) throws {
    let allowedRoles = Set([kAXRadioButtonRole as String, "AXTab", kAXButtonRole as String])
    var lastError = AXError.cannotComplete
    let succeeded = wait(timeout: 8) {
        guard let control = elements(in: application).first(where: { candidate in
            allowedRoles.contains(role(of: candidate))
                && strings(of: candidate).contains(name)
                && actionNames(of: candidate).contains(kAXPressAction as String)
        }) else { return false }
        lastError = AXUIElementPerformAction(control, kAXPressAction as CFString)
        return lastError == .success
    }
    guard succeeded else {
        if lastError == .cannotComplete {
            throw HighlightSelectionError.missing("Reader omitted an actionable \(name) inspector mode.")
        }
        throw HighlightSelectionError.actionFailed(name, lastError)
    }
}

private func parameterizedValue(
    _ name: CFString,
    parameter: CFTypeRef,
    from element: AXUIElement
) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(element, name, parameter, &result) == .success else {
        return nil
    }
    return result
}

private func rangeValue(_ range: CFRange) -> AXValue {
    var mutableRange = range
    return AXValueCreate(.cfRange, &mutableRange)!
}

private func populatedWebArea(in application: AXUIElement, containing selectedText: String) throws -> AXUIElement {
    var resolved: AXUIElement?
    let found = wait(timeout: 55) {
        guard let webArea = elements(in: application).first(where: { role(of: $0) == "AXWebArea" }) else {
            return false
        }
        let range = rangeValue(CFRange(location: 0, length: 4_000))
        let content = parameterizedValue(
            kAXStringForRangeParameterizedAttribute as CFString,
            parameter: range,
            from: webArea
        ) as? String ?? ""
        guard content.contains(selectedText) else { return false }
        resolved = webArea
        return true
    }
    guard found, let resolved else {
        throw HighlightSelectionError.missing("Rendered reader content did not expose the target text through WebKit accessibility.")
    }
    return resolved
}

private func textRangeAndBounds(for selectedText: String, in webArea: AXUIElement) throws -> (NSRange, CGRect) {
    let contentRange = rangeValue(CFRange(location: 0, length: 4_000))
    guard let content = parameterizedValue(
        kAXStringForRangeParameterizedAttribute as CFString,
        parameter: contentRange,
        from: webArea
    ) as? String else {
        throw HighlightSelectionError.missing("WebKit did not return rendered reader text.")
    }

    let selectedRange = (content as NSString).range(of: selectedText)
    guard selectedRange.location != NSNotFound else {
        throw HighlightSelectionError.missing("Rendered reader text omitted \(selectedText).")
    }
    let boundsRange = rangeValue(CFRange(location: selectedRange.location, length: selectedRange.length))
    guard let rawBounds = parameterizedValue(
        kAXBoundsForRangeParameterizedAttribute as CFString,
        parameter: boundsRange,
        from: webArea
    ) else {
        throw HighlightSelectionError.missing("WebKit did not expose screen bounds for the target text.")
    }

    var bounds = CGRect.zero
    guard AXValueGetValue(rawBounds as! AXValue, .cgRect, &bounds),
          bounds.width >= 12,
          bounds.height >= 8 else {
        throw HighlightSelectionError.invalid("Target text returned invalid screen bounds: \(bounds).")
    }
    return (selectedRange, bounds)
}

private func postMouseEvent(
    type: CGEventType,
    point: CGPoint,
    button: CGMouseButton,
    source: CGEventSource
) {
    CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: button
    )?.post(tap: .cghidEventTap)
}

private func dragSelect(bounds: CGRect) throws {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        throw HighlightSelectionError.missing("Unable to create an exact pointer event source.")
    }
    let start = CGPoint(x: bounds.minX + 2, y: bounds.midY)
    let end = CGPoint(x: bounds.maxX - 2, y: bounds.midY)
    postMouseEvent(type: .mouseMoved, point: start, button: .left, source: source)
    usleep(80_000)
    postMouseEvent(type: .leftMouseDown, point: start, button: .left, source: source)
    for step in 1...32 {
        let progress = CGFloat(step) / 32
        let point = CGPoint(
            x: start.x + ((end.x - start.x) * progress),
            y: start.y + ((end.y - start.y) * progress)
        )
        postMouseEvent(type: .leftMouseDragged, point: point, button: .left, source: source)
        usleep(10_000)
    }
    postMouseEvent(type: .leftMouseUp, point: end, button: .left, source: source)
}

private func rightClick(point: CGPoint) throws {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        throw HighlightSelectionError.missing("Unable to create an exact pointer event source.")
    }
    postMouseEvent(type: .mouseMoved, point: point, button: .right, source: source)
    usleep(80_000)
    postMouseEvent(type: .rightMouseDown, point: point, button: .right, source: source)
    usleep(45_000)
    postMouseEvent(type: .rightMouseUp, point: point, button: .right, source: source)
}

private func postEscape() {
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
}

private func selectedMarkerText(in webArea: AXUIElement) -> String? {
    guard let markers = attributeValue(kAXSelectedTextMarkerRangeAttribute as CFString, from: webArea) else {
        return nil
    }
    return parameterizedValue(
        "AXStringForTextMarkerRange" as CFString,
        parameter: markers,
        from: webArea
    ) as? String
}

private func assertNotesRow(in application: AXUIElement, selectedText: String) throws {
    try pressInspectorMode(in: application, named: "Notes")
    guard wait(timeout: 12, condition: {
        element(in: application, named: selectedText, matchingContains: true) != nil &&
            element(in: application, role: kAXButtonRole as String, named: "Add Note") != nil
    }) else {
        throw HighlightSelectionError.missing("The persisted highlight did not appear as an actionable Notes row.")
    }
}

private func runCreate(
    application: AXUIElement,
    pid: pid_t,
    selectedText: String,
    webArea: AXUIElement,
    bounds: CGRect
) throws -> JourneyResult {
    try dragSelect(bounds: bounds)
    guard wait(timeout: 5, condition: { selectedMarkerText(in: webArea) == selectedText }) else {
        throw HighlightSelectionError.invalid("Pointer drag did not select the exact rendered target text.")
    }

    try rightClick(point: CGPoint(x: bounds.midX, y: bounds.midY))
    guard wait(timeout: 5, condition: {
        element(in: application, role: kAXMenuItemRole as String, named: "Highlight") != nil &&
            element(in: application, role: kAXMenuItemRole as String, named: "Copy Selection") != nil
    }) else {
        throw HighlightSelectionError.missing("The rendered selection omitted MacWiki's native Highlight context menu.")
    }
    guard let yellow = element(
        in: application,
        role: kAXMenuItemRole as String,
        named: "Yellow",
        requiringAction: "AXPick"
    ) else {
        throw HighlightSelectionError.missing("The native selection menu omitted the Yellow highlight action.")
    }
    try chooseMenuItem(yellow, label: "Yellow")
    try assertNotesRow(in: application, selectedText: selectedText)

    return JourneyResult(
        mode: .create,
        pid: pid,
        selectedText: selectedText,
        selectionBoundsX: bounds.origin.x,
        selectionBoundsY: bounds.origin.y,
        selectionBoundsWidth: bounds.width,
        selectionBoundsHeight: bounds.height,
        nativeMenuAction: "Highlight → Yellow",
        notesRowVisible: true,
        renderedHighlightContextMenuVisible: false
    )
}

private func runRehydrate(
    application: AXUIElement,
    pid: pid_t,
    selectedText: String,
    bounds: CGRect
) throws -> JourneyResult {
    var contextMenuVisible = false
    for _ in 1...15 where !contextMenuVisible {
        try rightClick(point: CGPoint(x: bounds.midX, y: bounds.midY))
        contextMenuVisible = wait(timeout: 1.2) {
            element(in: application, role: kAXMenuItemRole as String, named: "Highlight Color") != nil &&
                element(in: application, role: kAXMenuItemRole as String, named: "Delete Highlight") != nil
        }
        if !contextMenuVisible {
            postEscape()
            Thread.sleep(forTimeInterval: 0.25)
        }
    }
    guard contextMenuVisible else {
        throw HighlightSelectionError.missing("Relaunched reader never exposed the persisted rendered highlight context menu.")
    }
    postEscape()
    try assertNotesRow(in: application, selectedText: selectedText)

    return JourneyResult(
        mode: .rehydrate,
        pid: pid,
        selectedText: selectedText,
        selectionBoundsX: bounds.origin.x,
        selectionBoundsY: bounds.origin.y,
        selectionBoundsWidth: bounds.width,
        selectionBoundsHeight: bounds.height,
        nativeMenuAction: "Rendered highlight → Highlight Color",
        notesRowVisible: true,
        renderedHighlightContextMenuVisible: true
    )
}

do {
    guard CommandLine.arguments.count == 4,
          let mode = JourneyMode(rawValue: CommandLine.arguments[1]),
          let pid = pid_t(CommandLine.arguments[2]) else {
        throw HighlightSelectionError.usage
    }
    guard AXIsProcessTrusted() else { throw HighlightSelectionError.accessibilityUnavailable }

    let selectedText = CommandLine.arguments[3]
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    let webArea = try populatedWebArea(in: application, containing: selectedText)
    let (_, bounds) = try textRangeAndBounds(for: selectedText, in: webArea)
    let result: JourneyResult
    switch mode {
    case .create:
        result = try runCreate(
            application: application,
            pid: pid,
            selectedText: selectedText,
            webArea: webArea,
            bounds: bounds
        )
    case .rehydrate:
        result = try runRehydrate(
            application: application,
            pid: pid,
            selectedText: selectedText,
            bounds: bounds
        )
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_highlight_selection_rehydrate: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
