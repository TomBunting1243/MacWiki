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
    while Date() < deadline {
        target = flattenedElements(from: application).first { element in
            let role: String = attribute(kAXRoleAttribute as CFString, from: element) ?? ""
            return role == (kAXButtonRole as String) && labels(for: element).contains(targetLabel)
        }
        if target != nil { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    guard let target else { throw SidebarSelectionError.rootMissing(targetLabel) }

    let result = AXUIElementPerformAction(target, kAXPressAction as CFString)
    guard result == .success else { throw SidebarSelectionError.pressFailed(result) }
    print("{\"pid\":\(pid),\"selected\":\"\(targetLabel)\",\"action\":\"AXPress\"}")
} catch {
    fputs("ax_select_sidebar_root: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
