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
            "Usage: ax_verify_toolbar_popover.swift <pid> <toolbar label> <expected content>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missing(let message):
            message
        case .actionFailed(let label, let error):
            "\(label) rejected AXPress (\(error.rawValue))."
        }
    }
}

private struct VerificationResult: Codable {
    let pid: Int32
    let toolbarLabel: String
    let expectedContent: String
    let baselineWindowCount: Int
    let presentedWindowCount: Int
    let observedContent: [String]
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

private func elements(in root: AXUIElement, limit: Int = 8_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    var index = 0
    while index < pending.count, result.count < limit {
        let element = pending[index]
        index += 1
        result.append(element)
        if stringAttribute(kAXRoleAttribute as CFString, from: element) == "AXWebArea" {
            continue
        }
        let children = attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
        pending.append(contentsOf: children)
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

private func supportsPress(_ element: AXUIElement) -> Bool {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let actions = names as? [String] else {
        return false
    }
    return actions.contains(kAXPressAction as String)
}

private func windowCount(in application: AXUIElement) -> Int {
    (attributeValue(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement])?.count ?? 0
}

private func processIsAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0
}

do {
    guard CommandLine.arguments.count == 4,
          let pid = Int32(CommandLine.arguments[1]) else {
        throw VerificationError.usage
    }
    guard AXIsProcessTrusted() else {
        throw VerificationError.accessibilityUnavailable
    }

    let toolbarLabel = CommandLine.arguments[2]
    let expectedContent = CommandLine.arguments[3]
    let application = AXUIElementCreateApplication(pid)
    let baselineWindowCount = windowCount(in: application)
    guard baselineWindowCount > 0 else {
        throw VerificationError.missing("PID \(pid) has no accessible window.")
    }

    guard let control = elements(in: application, limit: 2_500).first(where: { element in
        supportsPress(element) && labels(of: element).contains(toolbarLabel)
    }) else {
        throw VerificationError.missing("Could not find enabled toolbar control \(toolbarLabel).")
    }

    let actionResult = AXUIElementPerformAction(control, kAXPressAction as CFString)
    guard actionResult == .success else {
        throw VerificationError.actionFailed(toolbarLabel, actionResult)
    }

    let deadline = Date().addingTimeInterval(6)
    var observedContent: [String] = []
    var presentedWindowCount = baselineWindowCount
    repeat {
        guard processIsAlive(pid) else {
            throw VerificationError.missing("\(toolbarLabel) terminated PID \(pid).")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        presentedWindowCount = windowCount(in: application)
        observedContent = Array(
            Set(elements(in: application).flatMap(labels))
        ).sorted()
        if observedContent.contains(where: {
            $0.localizedCaseInsensitiveCompare(expectedContent) == .orderedSame
        }) {
            let result = VerificationResult(
                pid: pid,
                toolbarLabel: toolbarLabel,
                expectedContent: expectedContent,
                baselineWindowCount: baselineWindowCount,
                presentedWindowCount: presentedWindowCount,
                observedContent: observedContent.filter {
                    $0.localizedCaseInsensitiveContains(expectedContent)
                        || $0.localizedCaseInsensitiveContains("loading")
                        || $0.localizedCaseInsensitiveContains("unavailable")
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            print()
            exit(EXIT_SUCCESS)
        }
    } while Date() < deadline

    let diagnosticLabels = observedContent.filter {
        $0.localizedCaseInsensitiveContains(toolbarLabel)
            || $0.localizedCaseInsensitiveContains("view")
            || $0.localizedCaseInsensitiveContains("loading")
            || $0.localizedCaseInsensitiveContains("unavailable")
    }
    throw VerificationError.missing(
        "\(toolbarLabel) produced no visible \(expectedContent) content "
            + "(windows \(baselineWindowCount) -> \(presentedWindowCount)); "
            + "observed: \(diagnosticLabels.joined(separator: " | "))."
    )
} catch {
    fputs("ax_verify_toolbar_popover: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
