#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum VerificationError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case missing(String)
    case actionFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_article_row_secondary_window.swift <pid> <expected query> [app log path]"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missing(let description):
            description
        case .actionFailed(let description, let error):
            "\(description) failed with AX error \(error.rawValue)."
        }
    }
}

private struct RowEvidence: Codable {
    let title: String
    let value: String
    let actions: [String]
}

private struct RuntimeDiagnosticCheckpoint: Codable {
    let stage: String
    let attributeGraphCycleCount: Int
}

private struct VerificationResult: Codable {
    let pid: Int32
    let query: String
    let rows: [RowEvidence]
    let readStateCycle: String
    let contextMenuAction: String
    let secondaryWindow: [String]
    let finalWindowCount: Int
    let runtimeDiagnosticCheckpoints: [RuntimeDiagnosticCheckpoint]
}

private let toggleReadStatusAction = "Toggle Read Status"

private func attributeGraphCycleCount(in logURL: URL?) -> Int {
    guard let logURL,
          let contents = try? String(contentsOf: logURL, encoding: .utf8) else {
        return 0
    }
    return contents.components(separatedBy: "AttributeGraph: cycle detected").count - 1
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

private func children(of element: AXUIElement) -> [AXUIElement] {
    attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
}

private func elements(in root: AXUIElement, limit: Int = 8_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    while !pending.isEmpty, result.count < limit {
        let element = pending.removeFirst()
        result.append(element)
        pending.append(contentsOf: children(of: element))
    }
    return result
}

private func labels(in root: AXUIElement) -> Set<String> {
    Set(elements(in: root).flatMap { element in
        [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXValueAttribute as CFString, from: element)
        ]
    }.filter { !$0.isEmpty })
}

private func actionNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func attributeNames(of element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(element, &names) == .success else { return [] }
    return names as? [String] ?? []
}

private func customActions(of element: AXUIElement) -> [AXUIElement] {
    attributeValue("AXCustomActions" as CFString, from: element) as? [AXUIElement] ?? []
}

private func customAction(titled title: String, on element: AXUIElement) -> AXUIElement? {
    customActions(of: element).first { action in
        stringAttribute(kAXTitleAttribute as CFString, from: action) == title ||
            stringAttribute(kAXDescriptionAttribute as CFString, from: action) == title
    }
}

private func namedActionIdentifier(_ title: String, on element: AXUIElement) -> String? {
    actionNames(of: element).first { actionName in
        actionName == title || actionName.hasPrefix("Name:\(title)\n")
    }
}

private func perform(_ action: String, on element: AXUIElement, description: String) throws {
    let result = AXUIElementPerformAction(element, action as CFString)
    guard result == .success else { throw VerificationError.actionFailed(description, result) }
}

private func wait(timeout: TimeInterval = 25, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.12)
    } while Date() < deadline
    return false
}

private func windows(in application: AXUIElement) -> [AXUIElement] {
    attributeValue(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement] ?? []
}

private func articleRows(in application: AXUIElement) -> [(AXUIElement, RowEvidence)] {
    var seen = Set<String>()
    return elements(in: application).compactMap { element in
        guard stringAttribute(kAXRoleAttribute as CFString, from: element) == kAXButtonRole as String else {
            return nil
        }
        let value = stringAttribute(kAXValueAttribute as CFString, from: element)
        let title: String
        if value.hasSuffix(", Unread") {
            title = String(value.dropLast(", Unread".count))
        } else if value.hasSuffix(", Read") {
            title = String(value.dropLast(", Read".count))
        } else {
            title = value
        }
        let actions = actionNames(of: element)
        guard !title.isEmpty,
              actions.contains(kAXPressAction as String),
              actions.contains(kAXShowMenuAction as String),
              seen.insert(title).inserted else {
            return nil
        }
        return (element, RowEvidence(title: title, value: value, actions: actions))
    }
}

private func row(titled title: String, in application: AXUIElement) -> (AXUIElement, RowEvidence)? {
    articleRows(in: application).first { $0.1.title == title }
}

private func hasReadStateAction(
    for row: AXUIElement,
    named title: String
) -> Bool {
    if namedActionIdentifier(title, on: row) != nil || customAction(titled: title, on: row) != nil {
        return true
    }
    return elements(in: row).contains { element in
        stringAttribute(kAXRoleAttribute as CFString, from: element) == kAXButtonRole as String &&
            stringAttribute(kAXHelpAttribute as CFString, from: element) == title
    }
}

private func performReadStateAction(named title: String, on row: AXUIElement) throws {
    if let actionIdentifier = namedActionIdentifier(title, on: row) {
        try perform(actionIdentifier, on: row, description: title)
        return
    }
    if let action = customAction(titled: title, on: row) {
        try perform(kAXPressAction as String, on: action, description: title)
        return
    }
    if let button = elements(in: row).first(where: { element in
        stringAttribute(kAXRoleAttribute as CFString, from: element) == kAXButtonRole as String &&
            stringAttribute(kAXHelpAttribute as CFString, from: element) == title
    }) {
        try perform(kAXPressAction as String, on: button, description: title)
        return
    }
    throw VerificationError.missing("The target row omitted its \(title) accessibility action.")
}

private func menuItem(titled title: String, in application: AXUIElement) -> AXUIElement? {
    elements(in: application).first { element in
        stringAttribute(kAXRoleAttribute as CFString, from: element) == kAXMenuItemRole as String &&
            stringAttribute(kAXTitleAttribute as CFString, from: element) == title
    }
}

private func showContextMenu(for row: AXUIElement, in application: AXUIElement) throws {
    _ = AXUIElementSetAttributeValue(
        application,
        kAXFrontmostAttribute as CFString,
        kCFBooleanTrue
    )
    let deadline = Date().addingTimeInterval(5)
    var lastError: AXError = .cannotComplete
    repeat {
        lastError = AXUIElementPerformAction(row, kAXShowMenuAction as CFString)
        if wait(timeout: 0.8, condition: { menuItem(titled: "Open in New Window", in: application) != nil }) {
            return
        }
        Thread.sleep(forTimeInterval: 0.12)
    } while Date() < deadline
    if lastError != .success {
        throw VerificationError.actionFailed("Show article context menu", lastError)
    }
    throw VerificationError.missing("The article context menu did not become accessible.")
}

private func close(_ window: AXUIElement) throws {
    guard let closeButtonValue = attributeValue(kAXCloseButtonAttribute as CFString, from: window),
          CFGetTypeID(closeButtonValue) == AXUIElementGetTypeID() else {
        throw VerificationError.missing("The secondary article window omitted its native close button.")
    }
    let closeButton = unsafeBitCast(closeButtonValue, to: AXUIElement.self)
    try perform(kAXPressAction as String, on: closeButton, description: "Close secondary article window")
}

do {
    guard (3...4).contains(CommandLine.arguments.count),
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw VerificationError.usage
    }
    guard AXIsProcessTrusted() else { throw VerificationError.accessibilityUnavailable }

    let query = CommandLine.arguments[2]
    let appLogURL = CommandLine.arguments.count == 4
        ? URL(fileURLWithPath: CommandLine.arguments[3])
        : nil
    var runtimeDiagnosticCheckpoints: [RuntimeDiagnosticCheckpoint] = []
    func recordRuntimeDiagnostics(_ stage: String) {
        runtimeDiagnosticCheckpoints.append(
            RuntimeDiagnosticCheckpoint(
                stage: stage,
                attributeGraphCycleCount: attributeGraphCycleCount(in: appLogURL)
            )
        )
    }

    let application = AXUIElementCreateApplication(pid)
    guard wait(timeout: 40, condition: { articleRows(in: application).count >= 10 }) else {
        throw VerificationError.missing("Search did not expose ten semantic article result rows.")
    }

    let initialRows = Array(articleRows(in: application).prefix(10))
    guard initialRows.allSatisfy({ row in
        row.1.value == "\(row.1.title), Unread" &&
            row.1.actions.contains(kAXPressAction as String) &&
            row.1.actions.contains(kAXShowMenuAction as String) &&
            namedActionIdentifier(toggleReadStatusAction, on: row.0) != nil
    }) else {
        throw VerificationError.missing("An article row omitted its title, press action, or context-menu action.")
    }
    recordRuntimeDiagnostics("initial rows")

    let targetTitle = initialRows.first(where: { $0.1.title == query })?.1.title ?? initialRows[0].1.title
    guard let unreadTarget = row(titled: targetTitle, in: application),
          hasReadStateAction(for: unreadTarget.0, named: toggleReadStatusAction) else {
        let diagnosticRow = row(titled: targetTitle, in: application)?.0
        throw VerificationError.missing(
            "The target row omitted its Toggle Read Status accessibility action. " +
                "Actions: \(diagnosticRow.map(actionNames) ?? []). " +
                "Attributes: \(diagnosticRow.map(attributeNames) ?? [])."
        )
    }
    try performReadStateAction(named: toggleReadStatusAction, on: unreadTarget.0)
    guard wait(condition: {
        guard let updated = row(titled: targetTitle, in: application) else { return false }
        return updated.1.value == "\(targetTitle), Read" &&
            hasReadStateAction(for: updated.0, named: toggleReadStatusAction)
    }) else {
        throw VerificationError.missing("The target row did not announce Read after toggling its read status.")
    }
    recordRuntimeDiagnostics("marked read")

    guard let contextTarget = row(titled: targetTitle, in: application) else {
        throw VerificationError.missing("The target row disappeared before its context-menu check.")
    }
    try showContextMenu(for: contextTarget.0, in: application)
    guard menuItem(titled: "Mark as Unread", in: application) != nil else {
        throw VerificationError.missing("The article context menu did not expose the inverse Mark as Unread action.")
    }
    recordRuntimeDiagnostics("context menu")
    guard let openInNewWindow = menuItem(titled: "Open in New Window", in: application) else {
        throw VerificationError.missing("The article context menu omitted Open in New Window.")
    }
    try perform(kAXPressAction as String, on: openInNewWindow, description: "Open article in new window")

    guard wait(timeout: 35, condition: { windows(in: application).count == 2 }) else {
        throw VerificationError.missing("Open in New Window did not produce exactly two application windows.")
    }
    var resolvedArticleWindow: AXUIElement?
    guard wait(timeout: 35, condition: {
        resolvedArticleWindow = windows(in: application).first(where: { window in
            let windowLabels = labels(in: window)
            return windowLabels.contains(targetTitle) &&
                windowLabels.contains("Metadata") &&
                windowLabels.contains("Contents")
        })
        return resolvedArticleWindow != nil
    }), let articleWindow = resolvedArticleWindow else {
        throw VerificationError.missing("The secondary window omitted the selected article, Metadata, or Contents.")
    }

    let expectedSecondaryLabels = [
        targetTitle, "Metadata", "Contents", "Info", "Notes", "References"
    ]
    _ = wait(timeout: 3, condition: {
        let currentLabels = labels(in: articleWindow)
        return expectedSecondaryLabels.allSatisfy(currentLabels.contains)
    })
    let articleWindowLabels = labels(in: articleWindow)
    let missingSecondaryLabels = expectedSecondaryLabels.filter { !articleWindowLabels.contains($0) }
    guard missingSecondaryLabels.isEmpty else {
        throw VerificationError.missing(
            "The secondary article window omitted: \(missingSecondaryLabels.joined(separator: ", "))."
        )
    }
    recordRuntimeDiagnostics("secondary window")

    try close(articleWindow)
    guard wait(condition: { windows(in: application).count == 1 }) else {
        throw VerificationError.missing("Closing the secondary window did not preserve exactly one main window.")
    }
    recordRuntimeDiagnostics("secondary window closed")

    guard let readTarget = row(titled: targetTitle, in: application),
          hasReadStateAction(for: readTarget.0, named: toggleReadStatusAction) else {
        throw VerificationError.missing("The restored main-window row omitted its Toggle Read Status accessibility action.")
    }
    try performReadStateAction(named: toggleReadStatusAction, on: readTarget.0)
    guard wait(condition: {
        guard let restored = row(titled: targetTitle, in: application) else { return false }
        return restored.1.value == "\(targetTitle), Unread" &&
            hasReadStateAction(for: restored.0, named: toggleReadStatusAction)
    }) else {
        throw VerificationError.missing("The target row did not announce Unread after restoring its read status.")
    }
    recordRuntimeDiagnostics("restored unread")

    let result = VerificationResult(
        pid: pid,
        query: query,
        rows: initialRows.map(\.1),
        readStateCycle: "unread -> read -> unread",
        contextMenuAction: "Open in New Window",
        secondaryWindow: expectedSecondaryLabels,
        finalWindowCount: windows(in: application).count,
        runtimeDiagnosticCheckpoints: runtimeDiagnosticCheckpoints
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_article_row_secondary_window: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
