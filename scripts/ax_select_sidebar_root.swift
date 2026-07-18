#!/usr/bin/env swift

import ApplicationServices
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

do {
    guard CommandLine.arguments.count == 3,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw SidebarSelectionError.usage
    }
    guard AXIsProcessTrusted() else { throw SidebarSelectionError.accessibilityUnavailable }

    let targetLabel = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid)
    let deadline = Date().addingTimeInterval(15)
    var target: AXUIElement?
    var selectableRow: AXUIElement?
    while Date() < deadline {
        let applicationElements = flattenedElements(from: application)
        target = applicationElements.first { element in
            let role: String = attribute(kAXRoleAttribute as CFString, from: element) ?? ""
            return role == (kAXButtonRole as String)
                && labels(for: element).contains(targetLabel)
                && supportsPress(element)
        }
        if target == nil {
            for row in applicationElements where
                (attribute(kAXRoleAttribute as CFString, from: row) as String?) == (kAXRowRole as String)
            {
                let rowElements = flattenedElements(from: row, limit: 50)
                guard rowElements.flatMap(labels).contains(targetLabel) else { continue }
                selectableRow = row
                target = rowElements.first(where: supportsPress)
                if target == nil, supportsPress(row) {
                    target = row
                }
                break
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
