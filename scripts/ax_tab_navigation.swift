#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

enum TabNavigationError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case windowMissing
    case activationFailed
    case tabCount(expected: Int, observed: Int)
    case activeTabMissing
    case selectionUnchanged
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_tab_navigation.swift <pid>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .windowMissing:
            "The exact process did not expose a window."
        case .activationFailed:
            "The exact process did not become frontmost."
        case let .tabCount(expected, observed):
            "Expected \(expected) tabs; observed \(observed)."
        case .activeTabMissing:
            "No tab exposed the Active tab accessibility value."
        case .selectionUnchanged:
            "The active tab did not change after the native shortcut."
        case .eventCreationFailed:
            "Could not create a native keyboard event."
        }
    }
}

struct TabNavigationResult: Codable {
    let initialCount: Int
    let createdCount: Int
    let closedCount: Int
    let reopenedCount: Int
    let durations: [Double]
}

func attribute<T>(_ name: CFString, from element: AXUIElement, as type: T.Type = T.self) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value as? T
}

func flattenedElements(from root: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending: [AXUIElement] = [root]
    while let element = pending.popLast(), result.count < limit {
        result.append(element)
        let children: [AXUIElement] = attribute(kAXChildrenAttribute as CFString, from: element) ?? []
        pending.append(contentsOf: children.reversed())
    }
    return result
}

func tabElements(in application: AXUIElement) -> [AXUIElement] {
    flattenedElements(from: application).filter { element in
        let role: String = attribute(kAXRoleAttribute as CFString, from: element) ?? ""
        let value: String = attribute(kAXValueAttribute as CFString, from: element) ?? ""
        return role == (kAXButtonRole as String) &&
            (value.hasPrefix("Active tab") || value.hasPrefix("Inactive tab"))
    }.sorted { left, right in
        var leftPoint = CGPoint.zero
        var rightPoint = CGPoint.zero
        if let leftValue: AXValue = attribute(kAXPositionAttribute as CFString, from: left) {
            AXValueGetValue(leftValue, .cgPoint, &leftPoint)
        }
        if let rightValue: AXValue = attribute(kAXPositionAttribute as CFString, from: right) {
            AXValueGetValue(rightValue, .cgPoint, &rightPoint)
        }
        return leftPoint.x < rightPoint.x
    }
}

func activeIndex(in tabs: [AXUIElement]) -> Int? {
    tabs.firstIndex { element in
        let value: String = attribute(kAXValueAttribute as CFString, from: element) ?? ""
        return value.hasPrefix("Active tab")
    }
}

func waitForWindows(in application: AXUIElement, timeout: TimeInterval) throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let windows: [AXUIElement] = attribute(kAXWindowsAttribute as CFString, from: application) ?? []
        if !windows.isEmpty { return }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw TabNavigationError.windowMissing
}

func activateTarget(processID: pid_t, application: AXUIElement) throws {
    guard let runningApplication = NSRunningApplication(processIdentifier: processID),
          !runningApplication.isTerminated else {
        throw TabNavigationError.activationFailed
    }
    _ = runningApplication.activate(options: [.activateAllWindows])
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute as CFString, from: application) ?? []
    if let window = windows.first {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline {
        let frontmost: NSNumber? = attribute(kAXFrontmostAttribute as CFString, from: application)
        if frontmost?.boolValue == true,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == processID {
            return
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw TabNavigationError.activationFailed
}

func waitForTabCount(
    _ expected: Int,
    in application: AXUIElement,
    timeout: TimeInterval
) throws -> [AXUIElement] {
    let deadline = Date().addingTimeInterval(timeout)
    var observed: [AXUIElement] = []
    while Date() < deadline {
        observed = tabElements(in: application)
        if observed.count == expected, activeIndex(in: observed) != nil { return observed }
        Thread.sleep(forTimeInterval: 0.05)
    }
    throw TabNavigationError.tabCount(expected: expected, observed: observed.count)
}

func pressKey(_ keyCode: CGKeyCode, flags: CGEventFlags) throws {
    guard let source = CGEventSource(stateID: .combinedSessionState),
          let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        throw TabNavigationError.eventCreationFailed
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
}

func switchAndMeasure(in application: AXUIElement, flags: CGEventFlags) throws -> Double {
    let beforeTabs = tabElements(in: application)
    guard let before = activeIndex(in: beforeTabs) else { throw TabNavigationError.activeTabMissing }
    let startedAt = DispatchTime.now().uptimeNanoseconds
    try pressKey(48, flags: flags)
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
        let afterTabs = tabElements(in: application)
        if let after = activeIndex(in: afterTabs), after != before {
            return Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    throw TabNavigationError.selectionUnchanged
}

do {
    guard CommandLine.arguments.count == 2,
          let processID = pid_t(CommandLine.arguments[1]) else {
        throw TabNavigationError.usage
    }
    guard AXIsProcessTrusted() else { throw TabNavigationError.accessibilityUnavailable }

    let application = AXUIElementCreateApplication(processID)
    try waitForWindows(in: application, timeout: 6)
    try activateTarget(processID: processID, application: application)
    let initialCount = tabElements(in: application).count
    for _ in 0..<3 {
        try pressKey(17, flags: .maskCommand)
        Thread.sleep(forTimeInterval: 0.15)
    }
    let createdTabs = try waitForTabCount(initialCount + 3, in: application, timeout: 5)

    var durations: [Double] = []
    for _ in 0..<2 {
        durations.append(try switchAndMeasure(in: application, flags: .maskControl))
    }
    for _ in 0..<2 {
        durations.append(try switchAndMeasure(in: application, flags: [.maskControl, .maskShift]))
    }

    try pressKey(13, flags: .maskCommand)
    let closedTabs = try waitForTabCount(createdTabs.count - 1, in: application, timeout: 5)
    try pressKey(17, flags: [.maskCommand, .maskShift])
    let reopenedTabs = try waitForTabCount(createdTabs.count, in: application, timeout: 5)

    let result = TabNavigationResult(
        initialCount: initialCount,
        createdCount: createdTabs.count,
        closedCount: closedTabs.count,
        reopenedCount: reopenedTabs.count,
        durations: durations
    )
    FileHandle.standardOutput.write(try JSONEncoder().encode(result))
    print()
} catch {
    fputs("ax_tab_navigation: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
