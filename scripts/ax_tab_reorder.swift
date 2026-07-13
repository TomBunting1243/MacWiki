#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum VerificationError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case missing(String)
    case actionFailed(String, AXError)
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_tab_reorder.swift <pid> <expected tab count>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missing(let description):
            description
        case .actionFailed(let description, let error):
            "\(description) failed with AX error \(error.rawValue)."
        case .eventCreationFailed:
            "Could not create a native input event."
        }
    }
}

private struct TabEvidence: Codable, Equatable {
    let title: String
    let value: String
    let frame: [Double]
}

private struct VerificationResult: Codable {
    let before: [TabEvidence]
    let after: [TabEvidence]
    let draggedTitle: String
    let destinationTitle: String
    let overflowMenuTitles: [String]
}

private func attributeValue(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func stringAttribute(_ name: CFString, from element: AXUIElement) -> String {
    attributeValue(name, from: element) as? String ?? ""
}

private func children(of element: AXUIElement) -> [AXUIElement] {
    attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
}

private func elements(in root: AXUIElement, limit: Int = 8_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    while let element = pending.popLast(), result.count < limit {
        result.append(element)
        pending.append(contentsOf: children(of: element).reversed())
    }
    return result
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

private func evidence(for element: AXUIElement) -> TabEvidence? {
    let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
    let value = stringAttribute(kAXValueAttribute as CFString, from: element)
    let title = {
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
        return title.isEmpty
            ? stringAttribute(kAXDescriptionAttribute as CFString, from: element)
            : title
    }()
    guard role == kAXButtonRole as String,
          value.hasPrefix("Active tab") || value.hasPrefix("Inactive tab"),
          !title.isEmpty,
          let frame = frame(of: element) else {
        return nil
    }
    return TabEvidence(
        title: title,
        value: value,
        frame: [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height].map(Double.init)
    )
}

private func tabs(in application: AXUIElement) -> [(AXUIElement, TabEvidence)] {
    elements(in: application).compactMap { element in
        evidence(for: element).map { (element, $0) }
    }
}

private func tabCandidateDiagnostics(in application: AXUIElement) -> [String] {
    elements(in: application).compactMap { element in
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
        let description = stringAttribute(kAXDescriptionAttribute as CFString, from: element)
        let value = stringAttribute(kAXValueAttribute as CFString, from: element)
        guard title.hasPrefix("QA ") || description.hasPrefix("QA ") || value.contains("tab") else {
            return nil
        }
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        return "role=\(role) title=\(title) description=\(description) value=\(value)"
    }
}

private func controlDiagnostics(in application: AXUIElement) -> [String] {
    elements(in: application).compactMap { element in
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        guard role == kAXButtonRole as String || role == kAXMenuButtonRole as String else { return nil }
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
        let description = stringAttribute(kAXDescriptionAttribute as CFString, from: element)
        let help = stringAttribute(kAXHelpAttribute as CFString, from: element)
        guard !title.hasPrefix("QA "), !description.hasPrefix("QA ") else { return nil }
        let value = stringAttribute(kAXValueAttribute as CFString, from: element)
        return "role=\(role) title=\(title) description=\(description) help=\(help) value=\(value)"
    }
}

private func wait(
    timeout: TimeInterval = 10,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}

private func perform(_ action: String, on element: AXUIElement, description: String) throws {
    let result = AXUIElementPerformAction(element, action as CFString)
    guard result == .success else {
        throw VerificationError.actionFailed(description, result)
    }
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
        throw VerificationError.eventCreationFailed
    }
    event.post(tap: .cghidEventTap)
}

private func drag(from start: CGPoint, to end: CGPoint) throws {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        throw VerificationError.eventCreationFailed
    }
    try postMouseEvent(.mouseMoved, at: start, source: source)
    Thread.sleep(forTimeInterval: 0.10)
    try postMouseEvent(.leftMouseDown, at: start, source: source)

    let steps = 42
    for step in 1...steps {
        let progress = CGFloat(step) / CGFloat(steps)
        let point = CGPoint(
            x: start.x + ((end.x - start.x) * progress),
            y: start.y + ((end.y - start.y) * progress)
        )
        try postMouseEvent(.leftMouseDragged, at: point, source: source)
        Thread.sleep(forTimeInterval: 0.012)
    }
    try postMouseEvent(.leftMouseUp, at: end, source: source)
}

private func pressEscape() throws {
    guard let source = CGEventSource(stateID: .combinedSessionState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
        throw VerificationError.eventCreationFailed
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

private func overflowButton(in application: AXUIElement) -> AXUIElement? {
    elements(in: application).first { element in
        let help = stringAttribute(kAXHelpAttribute as CFString, from: element)
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
        return help == "All Tabs" || title == "All Tabs"
    }
}

private func visibleMenuTitles(in application: AXUIElement) -> [String] {
    elements(in: application).compactMap { element in
        guard stringAttribute(kAXRoleAttribute as CFString, from: element) == kAXMenuItemRole as String else {
            return nil
        }
        let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
        return title.isEmpty ? nil : title
    }
}

do {
    guard CommandLine.arguments.count == 3,
          let processID = pid_t(CommandLine.arguments[1]),
          let expectedCount = Int(CommandLine.arguments[2]),
          expectedCount >= 4 else {
        throw VerificationError.usage
    }
    guard AXIsProcessTrusted() else { throw VerificationError.accessibilityUnavailable }

    let application = AXUIElementCreateApplication(processID)
    guard wait(timeout: 20, condition: { tabs(in: application).count == expectedCount }) else {
        throw VerificationError.missing(
            "Expected \(expectedCount) semantic tabs; observed \(tabs(in: application).count). " +
                "Candidates: \(tabCandidateDiagnostics(in: application).prefix(24).joined(separator: " | "))"
        )
    }

    let initialTabs = tabs(in: application)
    let before = initialTabs.map(\.1)
    guard Set(before.map(\.title)).count == expectedCount,
          before.allSatisfy({ $0.value.hasPrefix("Active tab") || $0.value.hasPrefix("Inactive tab") }) else {
        throw VerificationError.missing("Tabs did not expose unique titles and active/inactive values.")
    }

    let sourceTitle = before[0].title
    let destinationTitle = before[2].title
    guard let source = tabs(in: application).first(where: { $0.1.title == sourceTitle }),
          let destination = tabs(in: application).first(where: { $0.1.title == destinationTitle }),
          let sourceFrame = frame(of: source.0),
          let destinationFrame = frame(of: destination.0),
          sourceFrame.width > 20,
          destinationFrame.width > 20 else {
        throw VerificationError.missing("Could not resolve visible source and destination tab frames.")
    }

    try drag(
        from: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY),
        to: CGPoint(x: destinationFrame.midX, y: destinationFrame.midY)
    )

    guard wait(timeout: 12, condition: {
        tabs(in: application).map(\.1.title) != before.map(\.title)
    }) else {
        throw VerificationError.missing(
            "Tab drag did not publish a reordered accessibility sequence. " +
                "Source frame: \(sourceFrame); destination frame: \(destinationFrame)."
        )
    }

    let after = tabs(in: application).map(\.1)
    guard after.count == expectedCount,
          Set(after.map(\.title)) == Set(before.map(\.title)),
          after.first?.title != sourceTitle else {
        throw VerificationError.missing("Tab reorder changed membership or left the dragged tab at its source.")
    }

    guard let overflow = overflowButton(in: application) else {
        throw VerificationError.missing(
            "The constrained tab lane did not expose All Tabs overflow. Controls: " +
                controlDiagnostics(in: application).prefix(40).joined(separator: " | ")
        )
    }
    try perform(kAXPressAction as String, on: overflow, description: "Open All Tabs overflow")
    let expectedOverflowTitles = Set(after.map(\.title))
    guard wait(condition: {
        Set(visibleMenuTitles(in: application).filter(expectedOverflowTitles.contains)) == expectedOverflowTitles
    }) else {
        throw VerificationError.missing("All Tabs overflow did not expose every open title.")
    }
    let visibleOverflowTitleSet = Set(visibleMenuTitles(in: application))
    let overflowMenuTitles = after.map(\.title).filter(visibleOverflowTitleSet.contains)
    try pressEscape()

    Thread.sleep(forTimeInterval: 1.0)
    let result = VerificationResult(
        before: before,
        after: after,
        draggedTitle: sourceTitle,
        destinationTitle: destinationTitle,
        overflowMenuTitles: overflowMenuTitles
    )
    FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    print()
} catch {
    fputs("ax_tab_reorder: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
