#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

enum ReaderOfflineError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case failureSurfaceMissing
    case retryActionFailed(AXError)
    case failureSurfaceDidNotReturn

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_reader_offline_retry.swift <pid> [failure headline]"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .failureSurfaceMissing:
            "The reader did not expose its offline failure and retry surface."
        case .retryActionFailed(let error):
            "The native Retry button rejected AXPress (\(error.rawValue))."
        case .failureSurfaceDidNotReturn:
            "The offline failure surface did not return after retry."
        }
    }
}

struct ReaderOfflineResult: Codable {
    let pid: Int32
    let initialText: [String]
    let retryAction: String
    let finalText: [String]
}

func attributeValue(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

func stringAttribute(_ name: CFString, from element: AXUIElement) -> String {
    guard let value = attributeValue(name, from: element) else { return "" }
    if let string = value as? String { return string }
    if let attributed = value as? NSAttributedString { return attributed.string }
    return ""
}

func elementAttribute(_ name: CFString, from element: AXUIElement) -> AXUIElement? {
    guard let value = attributeValue(name, from: element),
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return (value as! AXUIElement)
}

func flattenedElements(from root: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    while let element = pending.popLast(), result.count < limit {
        result.append(element)
        let children = attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
        pending.append(contentsOf: children.reversed())
    }
    return result
}

func flattenedApplicationElements(from application: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    let windows = attributeValue(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement] ?? []
    let focusedWindow = elementAttribute(kAXFocusedWindowAttribute as CFString, from: application)
    let roots = windows.isEmpty ? focusedWindow.map { [$0] } ?? [] : windows
    guard !roots.isEmpty else { return flattenedElements(from: application, limit: limit) }

    var result: [AXUIElement] = []
    for window in roots where result.count < limit {
        result.append(contentsOf: flattenedElements(from: window, limit: limit - result.count))
    }
    return result
}

func visibleText(in application: AXUIElement) -> [String] {
    flattenedApplicationElements(from: application).flatMap { element in
        [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXValueAttribute as CFString, from: element)
        ]
    }.filter { !$0.isEmpty }
}

func retryButton(in application: AXUIElement) -> AXUIElement? {
    flattenedApplicationElements(from: application).first { element in
        guard stringAttribute(kAXRoleAttribute as CFString, from: element) == (kAXButtonRole as String) else {
            return false
        }
        return [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXValueAttribute as CFString, from: element)
        ].contains("Try Again")
    }
}

func hasOfflineFailure(_ text: [String], headline: String) -> Bool {
    let joined = text.joined(separator: "\n")
    return joined.contains(headline) &&
        (joined.localizedCaseInsensitiveContains("offline") ||
            joined.localizedCaseInsensitiveContains("not connected"))
}

do {
    guard (2...3).contains(CommandLine.arguments.count),
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw ReaderOfflineError.usage
    }
    let failureHeadline = CommandLine.arguments.count == 3
        ? CommandLine.arguments[2]
        : "Failed to Load Article"
    guard AXIsProcessTrusted() else { throw ReaderOfflineError.accessibilityUnavailable }

    let application = AXUIElementCreateApplication(pid)
    NSRunningApplication(processIdentifier: pid)?.activate()
    Thread.sleep(forTimeInterval: 0.2)
    let windows = attributeValue(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement] ?? []
    windows.forEach { _ = AXUIElementPerformAction($0, kAXRaiseAction as CFString) }
    let initialDeadline = Date().addingTimeInterval(20)
    var initialText: [String] = []
    var button: AXUIElement?
    while Date() < initialDeadline {
        initialText = visibleText(in: application)
        button = retryButton(in: application)
        if hasOfflineFailure(initialText, headline: failureHeadline), button != nil { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard hasOfflineFailure(initialText, headline: failureHeadline), let button else {
        fputs("Observed AX text:\n\(initialText.joined(separator: "\n"))\n", stderr)
        throw ReaderOfflineError.failureSurfaceMissing
    }

    let actionResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
    guard actionResult == .success else { throw ReaderOfflineError.retryActionFailed(actionResult) }

    let retryDeadline = Date().addingTimeInterval(12)
    var finalText: [String] = []
    while Date() < retryDeadline {
        finalText = visibleText(in: application)
        if hasOfflineFailure(finalText, headline: failureHeadline), retryButton(in: application) != nil { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard hasOfflineFailure(finalText, headline: failureHeadline), retryButton(in: application) != nil else {
        throw ReaderOfflineError.failureSurfaceDidNotReturn
    }

    let result = ReaderOfflineResult(
        pid: pid,
        initialText: initialText,
        retryAction: "AXPress",
        finalText: finalText
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_reader_offline_retry: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
