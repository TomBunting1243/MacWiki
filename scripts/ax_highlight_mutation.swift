#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum MutationError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case missing(String)
    case actionFailed(String, AXError)
    case valueFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_highlight_mutation.swift <pid> <highlight text> <note text>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missing(let description):
            description
        case .actionFailed(let label, let error):
            "\(label) rejected its accessibility action (\(error.rawValue))."
        case .valueFailed(let label, let error):
            "\(label) rejected its accessibility value (\(error.rawValue))."
        }
    }
}

private struct MutationResult: Codable {
    let pid: Int32
    let articleMode: String
    let highlightText: String
    let noteText: String
    let selectedColor: String
    let deleteAction: String
    let highlightRemoved: Bool
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

private func role(of element: AXUIElement) -> String {
    stringAttribute(kAXRoleAttribute as CFString, from: element)
}

private func strings(of element: AXUIElement) -> [String] {
    [
        stringAttribute(kAXTitleAttribute as CFString, from: element),
        stringAttribute(kAXDescriptionAttribute as CFString, from: element),
        stringAttribute(kAXValueAttribute as CFString, from: element),
        stringAttribute(kAXHelpAttribute as CFString, from: element)
    ].filter { !$0.isEmpty }
}

private func elements(in application: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [application]
    var nextIndex = 0

    while nextIndex < pending.count, result.count < limit {
        let element = pending[nextIndex]
        nextIndex += 1
        result.append(element)

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

private func button(in application: AXUIElement, named name: String) -> AXUIElement? {
    element(in: application, role: kAXButtonRole as String, named: name)
}

private func wait(
    timeout: TimeInterval = 45,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.12)
    } while Date() < deadline
    return false
}

private func waitForElement(
    in application: AXUIElement,
    role: String? = nil,
    named name: String,
    matchingContains: Bool = false,
    requiringAction action: String? = nil,
    failure: String
) throws -> AXUIElement {
    var result: AXUIElement?
    guard wait(condition: {
        result = element(
            in: application,
            role: role,
            named: name,
            matchingContains: matchingContains,
            requiringAction: action
        )
        return result != nil
    }), let result else {
        throw MutationError.missing(failure)
    }
    return result
}

private func perform(_ action: String, on element: AXUIElement, label: String) throws {
    let result = AXUIElementPerformAction(element, action as CFString)
    guard result == .success else { throw MutationError.actionFailed(label, result) }
}

private func press(_ element: AXUIElement, label: String) throws {
    try perform(kAXPressAction as String, on: element, label: label)
}

private func pressButton(
    in application: AXUIElement,
    named name: String,
    failure: String
) throws {
    var lastError: AXError = .cannotComplete
    let succeeded = wait(timeout: 8) {
        guard let candidate = button(in: application, named: name),
              actionNames(of: candidate).contains(kAXPressAction as String) else {
            return false
        }
        lastError = AXUIElementPerformAction(candidate, kAXPressAction as CFString)
        return lastError == .success
    }
    guard succeeded else {
        if lastError == .cannotComplete {
            throw MutationError.missing(failure)
        }
        throw MutationError.actionFailed(name, lastError)
    }
}

private func performNamedAction(
    in application: AXUIElement,
    named name: String,
    matchingContains: Bool = false,
    action: String,
    failure: String
) throws {
    var lastError: AXError = .cannotComplete
    let succeeded = wait(timeout: 8) {
        guard let candidate = element(
            in: application,
            named: name,
            matchingContains: matchingContains,
            requiringAction: action
        ) else {
            return false
        }
        lastError = AXUIElementPerformAction(candidate, action as CFString)
        return lastError == .success
    }
    guard succeeded else {
        if lastError == .cannotComplete {
            throw MutationError.missing(failure)
        }
        throw MutationError.actionFailed(name, lastError)
    }
}

private func trace(_ stage: String) {
    fputs("\(ISO8601DateFormatter().string(from: Date())) \(stage)\n", stderr)
}

private func traceEditableCandidates(in application: AXUIElement) {
    for candidate in elements(in: application) {
        let candidateRole = role(of: candidate)
        let candidateStrings = strings(of: candidate)
        let isRelevantRole = candidateRole.contains("Text") || candidateRole.contains("Edit")
        let isRelevantLabel = candidateStrings.contains { value in
            value.localizedCaseInsensitiveContains("note")
        }
        guard isRelevantRole || isRelevantLabel else { continue }
        let identifier = stringAttribute(kAXIdentifierAttribute as CFString, from: candidate)
        trace("candidate role=\(candidateRole) identifier=\(identifier) strings=\(candidateStrings) actions=\(actionNames(of: candidate))")
    }
}

private func chooseMenuItem(_ element: AXUIElement, label: String) throws {
    if actionNames(of: element).contains("AXPick") {
        try perform("AXPick", on: element, label: label)
    } else {
        try press(element, label: label)
    }
}

do {
    guard CommandLine.arguments.count == 4,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw MutationError.usage
    }
    guard AXIsProcessTrusted() else { throw MutationError.accessibilityUnavailable }

    let highlightText = CommandLine.arguments[2]
    let noteText = CommandLine.arguments[3]
    let application = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

    trace("opening Notes inspector mode")
    try pressButton(in: application, named: "Notes", failure: "Inspector mode omitted an actionable Notes control.")
    _ = try waitForElement(
        in: application,
        named: highlightText,
        matchingContains: true,
        failure: "Seeded highlight did not appear in Notes."
    )
    trace("seeded highlight is visible")

    try pressButton(in: application, named: "Add Note", failure: "Seeded highlight omitted an actionable Add Note control.")
    var resolvedEditor: AXUIElement?
    guard wait(condition: {
        resolvedEditor = elements(in: application).first { candidate in
            let candidateRole = role(of: candidate)
            let isEditableText = candidateRole == kAXTextAreaRole as String ||
                candidateRole == kAXTextFieldRole as String
            return isEditableText && strings(of: candidate).contains("Highlight note")
        }
        return resolvedEditor != nil
    }), let editor = resolvedEditor else {
        traceEditableCandidates(in: application)
        throw MutationError.missing("Highlight note editor did not expose named editable text.")
    }
    let valueResult = AXUIElementSetAttributeValue(editor, kAXValueAttribute as CFString, noteText as CFString)
    guard valueResult == .success else { throw MutationError.valueFailed("Highlight note editor", valueResult) }
    try pressButton(in: application, named: "Save", failure: "Highlight note editor omitted an actionable Save control.")
    _ = try waitForElement(
        in: application,
        named: noteText,
        matchingContains: true,
        failure: "Saved highlight note did not appear."
    )
    trace("highlight note saved")

    try performNamedAction(
        in: application,
        named: highlightText,
        matchingContains: true,
        action: kAXShowMenuAction as String,
        failure: "Seeded highlight omitted its native context menu."
    )
    let blue = try waitForElement(
        in: application,
        role: kAXMenuItemRole as String,
        named: "Blue",
        failure: "Highlight context menu omitted the Blue color action."
    )
    try chooseMenuItem(blue, label: "Blue")
    trace("highlight color changed to Blue")

    try performNamedAction(
        in: application,
        named: highlightText,
        matchingContains: true,
        action: kAXShowMenuAction as String,
        failure: "Changed highlight omitted its native context menu."
    )
    let delete = try waitForElement(
        in: application,
        role: kAXMenuItemRole as String,
        named: "Delete Highlight",
        failure: "Highlight context menu omitted Delete Highlight."
    )
    try chooseMenuItem(delete, label: "Delete Highlight")
    guard wait(condition: {
        element(in: application, named: highlightText, matchingContains: true) == nil
    }) else {
        throw MutationError.missing("Deleted highlight remained in the Notes accessibility tree.")
    }
    trace("highlight deleted")

    let result = MutationResult(
        pid: pid,
        articleMode: "Notes",
        highlightText: highlightText,
        noteText: noteText,
        selectedColor: "Blue",
        deleteAction: "Delete Highlight",
        highlightRemoved: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_highlight_mutation: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
