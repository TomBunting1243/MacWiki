#!/usr/bin/env swift

import ApplicationServices
import Foundation

struct AboutNode: Codable {
    let role: String
    let subrole: String
    let title: String
    let description: String
    let value: String
}

struct AboutSnapshot: Codable {
    let pid: Int32
    let nodeCount: Int
    let nodes: [AboutNode]
}

enum AboutSnapshotError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case aboutPanelMissing
    case missingText(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_about_snapshot.swift <pid> <version> <build>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .aboutPanelMissing:
            "The exact process did not expose the native About dialog."
        case .missingText(let text):
            "The native About dialog is missing accessible text: \(text)"
        }
    }
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

func childElements(of element: AXUIElement) -> [AXUIElement] {
    attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
}

func flattenedElements(from root: AXUIElement, limit: Int = 2_000) -> [AXUIElement] {
    var elements: [AXUIElement] = []
    var pending = [root]
    while let element = pending.popLast(), elements.count < limit {
        elements.append(element)
        pending.append(contentsOf: childElements(of: element).reversed())
    }
    return elements
}

do {
    guard CommandLine.arguments.count == 4,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw AboutSnapshotError.usage
    }
    guard AXIsProcessTrusted() else { throw AboutSnapshotError.accessibilityUnavailable }

    let expectedVersion = CommandLine.arguments[2]
    let expectedBuild = CommandLine.arguments[3]
    let application = AXUIElementCreateApplication(pid)
    let deadline = Date().addingTimeInterval(8)
    var aboutElements: [AXUIElement] = []

    while Date() < deadline {
        let applicationWindows = attributeValue(
            kAXWindowsAttribute as CFString,
            from: application
        ) as? [AXUIElement] ?? []
        let windows = applicationWindows.filter {
            stringAttribute(kAXSubroleAttribute as CFString, from: $0) == (kAXDialogSubrole as String)
        }
        if let aboutWindow = windows.first(where: { window in
            flattenedElements(from: window).contains { element in
                stringAttribute(kAXValueAttribute as CFString, from: element)
                    .contains("Version \(expectedVersion) (\(expectedBuild))")
            }
        }) {
            aboutElements = flattenedElements(from: aboutWindow)
            break
        }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard !aboutElements.isEmpty else { throw AboutSnapshotError.aboutPanelMissing }

    let nodes = aboutElements.map { element in
        AboutNode(
            role: stringAttribute(kAXRoleAttribute as CFString, from: element),
            subrole: stringAttribute(kAXSubroleAttribute as CFString, from: element),
            title: stringAttribute(kAXTitleAttribute as CFString, from: element),
            description: stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            value: stringAttribute(kAXValueAttribute as CFString, from: element)
        )
    }
    let renderedText = nodes.flatMap { [$0.title, $0.description, $0.value] }.joined(separator: "\n")
    for required in [
        "MacWiki",
        "Version \(expectedVersion) (\(expectedBuild))",
        "A native macOS Wikipedia client.",
        "GitHub Repository",
        "Apache-2.0",
        "MacWiki Trademark"
    ] where !renderedText.contains(required) {
        throw AboutSnapshotError.missingText(required)
    }

    let snapshot = AboutSnapshot(pid: pid, nodeCount: nodes.count, nodes: nodes)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(snapshot))
    print()
} catch {
    fputs("ax_about_snapshot: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
