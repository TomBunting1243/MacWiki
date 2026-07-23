#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

enum SidebarSelectionError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case rootMissing(String)
    case pressFailed(AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_select_sidebar_root.swift <pid> <root label>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .rootMissing(let label):
            "The exact process did not expose the \(label) sidebar button."
        case .pressFailed(let error):
            "The sidebar button rejected AXPress (\(error.rawValue))."
        }
    }
}

func attribute<T>(_ name: CFString, from element: AXUIElement, as type: T.Type = T.self) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value as? T
}

func flattenedElements(from root: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    while let element = pending.popLast(), result.count < limit {
        result.append(element)
        let children: [AXUIElement] = attribute(kAXChildrenAttribute as CFString, from: element) ?? []
        pending.append(contentsOf: children.reversed())
    }
    return result
}

func flattenedApplicationElements(from application: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute as CFString, from: application) ?? []
    let focusedWindow: AXUIElement? = attribute(kAXFocusedWindowAttribute as CFString, from: application)
    let roots = windows.isEmpty ? focusedWindow.map { [$0] } ?? [] : windows
    guard !roots.isEmpty else { return flattenedElements(from: application, limit: limit) }

    var result: [AXUIElement] = []
    for window in roots where result.count < limit {
        result.append(contentsOf: flattenedElements(from: window, limit: limit - result.count))
    }
    return result
}

func labels(for element: AXUIElement) -> [String] {
    [
        attribute(kAXTitleAttribute as CFString, from: element) as String?,
        attribute(kAXDescriptionAttribute as CFString, from: element) as String?,
        attribute(kAXValueAttribute as CFString, from: element) as String?
    ].compactMap { $0 }
}

func supportsPress(_ element: AXUIElement) -> Bool {
    var values: CFArray?
    guard AXUIElementCopyActionNames(element, &values) == .success,
          let actions = values as? [String] else {
        return false
    }
    return actions.contains(kAXPressAction as String)
}

func supportsSelectedMutation(_ element: AXUIElement) -> Bool {
    var isSettable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(
        element,
        kAXSelectedAttribute as CFString,
        &isSettable
    ) == .success && isSettable.boolValue
}

do {
    guard CommandLine.arguments.count == 3,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw SidebarSelectionError.usage
    }
    guard AXIsProcessTrusted() else { throw SidebarSelectionError.accessibilityUnavailable }

    let targetLabel = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid)
    NSRunningApplication(processIdentifier: pid)?.activate()
    Thread.sleep(forTimeInterval: 0.2)
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute as CFString, from: application) ?? []
    windows.forEach { _ = AXUIElementPerformAction($0, kAXRaiseAction as CFString) }
    let deadline = Date().addingTimeInterval(15)
    var target: AXUIElement?
    var selectableRow: AXUIElement?
    while Date() < deadline {
        let applicationElements = flattenedApplicationElements(from: application)
        // Prefer the semantic Sidebar row. Discover also appears as a button
        // inside the reader page, and a global button-first lookup can report a
        // false-positive route change while leaving List Contents on Recents.
        for row in applicationElements where
            (attribute(kAXRoleAttribute as CFString, from: row) as String?) == (kAXRowRole as String)
        {
            let rowElements = flattenedElements(from: row, limit: 50)
            guard rowElements.flatMap(labels).contains(targetLabel) else { continue }
            if let pressableDescendant = rowElements.first(where: supportsPress) {
                target = pressableDescendant
                break
            }
            if supportsPress(row) {
                target = row
                break
            }
            if supportsSelectedMutation(row) {
                selectableRow = row
                break
            }
        }
        if target == nil, selectableRow == nil {
            target = applicationElements.first { element in
                let role: String = attribute(kAXRoleAttribute as CFString, from: element) ?? ""
                return role == (kAXButtonRole as String)
                    && labels(for: element).contains(targetLabel)
                    && supportsPress(element)
            }
        }
        if target != nil || selectableRow != nil { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    if let target {
        let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
        guard result == .success else { throw SidebarSelectionError.pressFailed(result) }
        print("{\"pid\":\(pid),\"selected\":\"\(targetLabel)\",\"action\":\"AXPress\"}")
    } else if let selectableRow {
        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            selectableRow,
            kAXSelectedAttribute as CFString,
            &isSettable
        )
        guard settableResult == .success, isSettable.boolValue else {
            throw SidebarSelectionError.rootMissing(targetLabel)
        }
        let result = AXUIElementSetAttributeValue(
            selectableRow,
            kAXSelectedAttribute as CFString,
            kCFBooleanTrue
        )
        guard result == .success else { throw SidebarSelectionError.pressFailed(result) }
        print("{\"pid\":\(pid),\"selected\":\"\(targetLabel)\",\"action\":\"AXSelected\"}")
    } else {
        throw SidebarSelectionError.rootMissing(targetLabel)
    }
} catch {
    fputs("ax_select_sidebar_root: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
