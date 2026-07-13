#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum JourneyError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case missing(String)
    case actionFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_reader_inspector_journey.swift <pid> <article title>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missing(let description):
            description
        case .actionFailed(let label, let error):
            "\(label) rejected AXPress (\(error.rawValue))."
        }
    }
}

private struct JourneyResult: Codable {
    let pid: Int32
    let articleTitle: String
    let toolbarControls: [String]
    let inspectorStates: [String: [String]]
    let findBar: [String]
    let inspectorToggleCycle: String
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

private func elements(in application: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [application]
    while !pending.isEmpty, result.count < limit {
        let element = pending.removeFirst()
        result.append(element)
        let children = attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
        pending.append(contentsOf: children)
    }
    return result
}

private func labels(in application: AXUIElement) -> [String] {
    var seen = Set<String>()
    return elements(in: application).flatMap { element in
        [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXValueAttribute as CFString, from: element)
        ]
    }.filter { !$0.isEmpty && seen.insert($0).inserted }
}

private func element(
    in application: AXUIElement,
    role: String,
    label: String
) -> AXUIElement? {
    elements(in: application).first { element in
        guard stringAttribute(kAXRoleAttribute as CFString, from: element) == role else { return false }
        return [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXPlaceholderValueAttribute as CFString, from: element)
        ].contains(label)
    }
}

private func button(in application: AXUIElement, label: String) -> AXUIElement? {
    element(in: application, role: kAXButtonRole as String, label: label)
}

private func press(_ element: AXUIElement, label: String) throws {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else { throw JourneyError.actionFailed(label, result) }
}

private func wait(
    timeout: TimeInterval = 20,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.12)
    } while Date() < deadline
    return false
}

do {
    guard CommandLine.arguments.count == 3,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw JourneyError.usage
    }
    guard AXIsProcessTrusted() else { throw JourneyError.accessibilityUnavailable }

    let articleTitle = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid)
    guard wait(timeout: 35, condition: {
        let currentLabels = labels(in: application)
        return currentLabels.contains(articleTitle) && currentLabels.contains("Inspector mode")
    }) else {
        throw JourneyError.missing("The article and inspector did not become accessible.")
    }

    let expectedToolbarControls = [
        "Back", "Forward", "Search Wikipedia", "Save Article", "Mark as Read",
        "Find in Page", "Reader Style", "Show Page Views",
        "Share", "More", "Hide Inspector"
    ]
    let availableToolbarControls = expectedToolbarControls.filter { button(in: application, label: $0) != nil }
    guard availableToolbarControls.count == expectedToolbarControls.count else {
        let missing = expectedToolbarControls.filter { !availableToolbarControls.contains($0) }
        throw JourneyError.missing("Reader toolbar omitted accessible controls: \(missing.joined(separator: ", "))")
    }

    var reportedToolbarControls = availableToolbarControls
    if button(in: application, label: "Open in Browser") == nil {
        guard let moreButton = button(in: application, label: "More") else {
            throw JourneyError.missing("Reader toolbar omitted More for overflow actions.")
        }
        try press(moreButton, label: "More")
        guard wait(condition: { button(in: application, label: "Open in Browser") != nil }) else {
            throw JourneyError.missing("Reader overflow omitted Open in Browser.")
        }
        reportedToolbarControls.append("Open in Browser (More)")
        let escape = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)
        escape?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
    } else {
        reportedToolbarControls.append("Open in Browser")
    }

    func inspectorButton(_ label: String) throws -> AXUIElement {
        guard let result = button(in: application, label: label) else {
            throw JourneyError.missing("Inspector mode omitted \(label).")
        }
        return result
    }

    var inspectorStates: [String: [String]] = [:]
    let initialLabels = labels(in: application)
    guard initialLabels.contains("Metadata"), initialLabels.contains("Contents") else {
        throw JourneyError.missing("Info mode omitted Metadata or Contents.")
    }
    inspectorStates["Info"] = ["Selected", "Metadata", "Contents"]

    try press(try inspectorButton("Notes"), label: "Notes")
    guard wait(condition: { labels(in: application).contains("No Highlights Yet") }) else {
        throw JourneyError.missing("Notes mode did not expose its empty-highlight state.")
    }
    guard stringAttribute(kAXValueAttribute as CFString, from: try inspectorButton("Notes")) == "Selected" else {
        throw JourneyError.missing("Notes mode did not expose its selected accessibility value.")
    }
    inspectorStates["Notes"] = ["Selected", "No Highlights Yet"]

    try press(try inspectorButton("References"), label: "References")
    guard wait(condition: {
        let current = labels(in: application)
        return current.contains("References") || current.contains("No References Found")
    }) else {
        throw JourneyError.missing("References mode did not expose content or its empty state.")
    }
    guard stringAttribute(kAXValueAttribute as CFString, from: try inspectorButton("References")) == "Selected" else {
        throw JourneyError.missing("References mode did not expose its selected accessibility value.")
    }
    inspectorStates["References"] = ["Selected", labels(in: application).contains("References") ? "References" : "No References Found"]

    try press(try inspectorButton("Info"), label: "Info")
    guard wait(condition: { labels(in: application).contains("Metadata") }) else {
        throw JourneyError.missing("Info mode did not restore Metadata.")
    }

    guard let findButton = button(in: application, label: "Find in Page") else {
        throw JourneyError.missing("Find in Page button disappeared.")
    }
    try press(findButton, label: "Find in Page")
    guard wait(condition: {
        element(in: application, role: kAXTextFieldRole as String, label: "Find in page") != nil &&
            button(in: application, label: "Done") != nil
    }) else {
        throw JourneyError.missing("Find bar did not expose its field and Done action.")
    }
    let findBar = ["Find in page", "Previous", "Next", "Done"]
    guard let doneButton = button(in: application, label: "Done") else {
        throw JourneyError.missing("Find bar omitted Done.")
    }
    try press(doneButton, label: "Done")
    guard wait(condition: { element(in: application, role: kAXTextFieldRole as String, label: "Find in page") == nil }) else {
        throw JourneyError.missing("Find bar did not dismiss.")
    }

    guard let toggleInspector = element(
        in: application,
        role: kAXMenuItemRole as String,
        label: "Toggle Inspector"
    ) else {
        throw JourneyError.missing("View menu omitted Toggle Inspector.")
    }
    try press(toggleInspector, label: "Toggle Inspector")
    guard wait(condition: { !labels(in: application).contains("Inspector mode") }) else {
        throw JourneyError.missing("Toggle Inspector did not hide the inspector.")
    }
    try press(toggleInspector, label: "Toggle Inspector")
    guard wait(condition: { labels(in: application).contains("Inspector mode") }) else {
        throw JourneyError.missing("Toggle Inspector did not restore the inspector.")
    }

    let result = JourneyResult(
        pid: pid,
        articleTitle: articleTitle,
        toolbarControls: reportedToolbarControls,
        inspectorStates: inspectorStates,
        findBar: findBar,
        inspectorToggleCycle: "hidden → restored"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_reader_inspector_journey: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
