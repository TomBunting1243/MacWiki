#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

enum DiscoverProbeError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case surfaceMissing([String])
    case scrollUnavailable

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_discover_surface_probe.swift <pid>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .surfaceMissing(let values):
            "Discovery did not expose its reader page and Time Machine. Observed: \(values.joined(separator: " | "))"
        case .scrollUnavailable:
            "Discovery exposed its content but no native page-scroll action."
        }
    }
}

func attribute<T>(_ name: CFString, from element: AXUIElement, as type: T.Type = T.self) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value as? T
}

func flattenedElements(from root: AXUIElement, limit: Int = 6_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    while let element = pending.popLast(), result.count < limit {
        result.append(element)
        let children: [AXUIElement] = attribute(kAXChildrenAttribute as CFString, from: element) ?? []
        pending.append(contentsOf: children.reversed())
    }
    return result
}

func flattenedApplicationElements(from application: AXUIElement, limit: Int = 6_000) -> [AXUIElement] {
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

func strings(for element: AXUIElement) -> [String] {
    [
        attribute(kAXTitleAttribute as CFString, from: element) as String?,
        attribute(kAXDescriptionAttribute as CFString, from: element) as String?,
        attribute(kAXHelpAttribute as CFString, from: element) as String?,
        attribute(kAXValueAttribute as CFString, from: element) as String?,
        attribute(kAXPlaceholderValueAttribute as CFString, from: element) as String?
    ]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
}

func uniqueStrings(in elements: [AXUIElement]) -> [String] {
    var seen = Set<String>()
    return elements
        .flatMap(strings)
        .filter { seen.insert($0).inserted }
}

func contains(_ pattern: String, in values: [String]) -> Bool {
    values.contains { $0.localizedCaseInsensitiveContains(pattern) }
}

func supportsAction(_ name: String, element: AXUIElement) -> Bool {
    var values: CFArray?
    guard AXUIElementCopyActionNames(element, &values) == .success,
          let actions = values as? [String] else {
        return false
    }
    return actions.contains(name)
}

func actionNames(for element: AXUIElement) -> [String] {
    var values: CFArray?
    guard AXUIElementCopyActionNames(element, &values) == .success else { return [] }
    return (values as? [String]) ?? []
}

func role(of element: AXUIElement) -> String? {
    attribute(kAXRoleAttribute as CFString, from: element)
}

func numericAttribute(_ name: CFString, from element: AXUIElement) -> Double? {
    guard let number: NSNumber = attribute(name, from: element) else { return nil }
    return number.doubleValue
}

func setNumericAttribute(_ name: CFString, on element: AXUIElement, to value: Double) -> Bool {
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, name, &settable) == .success,
          settable.boolValue else {
        return false
    }
    return AXUIElementSetAttributeValue(element, name, NSNumber(value: value)) == .success
}

func advanceScrollbar(in scrollArea: AXUIElement) -> Bool {
    let directScrollbar: AXUIElement? = attribute(kAXVerticalScrollBarAttribute as CFString, from: scrollArea)
    let descendantScrollbar = flattenedElements(from: scrollArea, limit: 1_500).first {
        role(of: $0) == (kAXScrollBarRole as String)
    }
    guard let scrollbar = directScrollbar ?? descendantScrollbar else { return false }

    let current = numericAttribute(kAXValueAttribute as CFString, from: scrollbar) ?? 0
    let minimum = numericAttribute(kAXMinValueAttribute as CFString, from: scrollbar) ?? 0
    let maximum = numericAttribute(kAXMaxValueAttribute as CFString, from: scrollbar) ?? 1
    guard maximum > minimum else { return false }

    let step = max((maximum - minimum) * 0.25, 0.01)
    let target = min(maximum, max(current + step, minimum))
    guard target > current,
          setNumericAttribute(kAXValueAttribute as CFString, on: scrollbar, to: target) else {
        return false
    }

    Thread.sleep(forTimeInterval: 0.15)
    let updated = numericAttribute(kAXValueAttribute as CFString, from: scrollbar) ?? current
    return updated > current
}

func exposesNativeVerticalScrolling(_ scrollArea: AXUIElement, actions: [String]) -> Bool {
    if actions.contains(where: { supportsAction($0, element: scrollArea) }) {
        return true
    }
    if (attribute(kAXVerticalScrollBarAttribute as CFString, from: scrollArea) as AXUIElement?) != nil {
        return true
    }
    return flattenedElements(from: scrollArea, limit: 1_500).contains {
        role(of: $0) == (kAXScrollBarRole as String)
    }
}

do {
    guard CommandLine.arguments.count == 2,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw DiscoverProbeError.usage
    }
    guard AXIsProcessTrusted() else { throw DiscoverProbeError.accessibilityUnavailable }

    let application = AXUIElementCreateApplication(pid)
    NSRunningApplication(processIdentifier: pid)?.activate()
    Thread.sleep(forTimeInterval: 0.2)
    let windows: [AXUIElement] = attribute(kAXWindowsAttribute as CFString, from: application) ?? []
    windows.forEach { _ = AXUIElementPerformAction($0, kAXRaiseAction as CFString) }
    let deadline = Date().addingTimeInterval(30)
    var lastObserved: [String] = []
    var discoverElements: [AXUIElement] = []
    var didOpenTimeMachine = false

    while Date() < deadline {
        discoverElements = flattenedApplicationElements(from: application)
        lastObserved = uniqueStrings(in: discoverElements)

        let hasReaderSearch = contains("Search Wikipedia", in: lastObserved)
        let hasTimeMachineButton = contains("Time Machine", in: lastObserved)
        let hasTimeMachineControls = contains("Edition Date", in: lastObserved)
            || contains("Previous Day", in: lastObserved)
        let hasEdition = [
            "Featured Article",
            "Most Read",
            "News Briefing",
            "Loading discover feed",
            "Discover Unavailable"
        ].contains { contains($0, in: lastObserved) }

        if hasReaderSearch && hasTimeMachineButton && hasTimeMachineControls && hasEdition {
            break
        }

        if hasTimeMachineButton, !hasTimeMachineControls, !didOpenTimeMachine,
           let timeMachineButton = discoverElements.first(where: { element in
               role(of: element) == (kAXButtonRole as String)
                   && strings(for: element).contains(where: {
                       $0.localizedCaseInsensitiveContains("Time Machine")
                   })
                   && supportsAction(kAXPressAction as String, element: element)
           }) {
            let pressResult = AXUIElementPerformAction(timeMachineButton, kAXPressAction as CFString)
            didOpenTimeMachine = pressResult == .success
            Thread.sleep(forTimeInterval: 0.2)
            continue
        }

        Thread.sleep(forTimeInterval: 0.15)
    }

    let hasReaderSearch = contains("Search Wikipedia", in: lastObserved)
    let hasTimeMachine = contains("Time Machine", in: lastObserved)
        && (contains("Edition Date", in: lastObserved) || contains("Previous Day", in: lastObserved))
    let hasEdition = [
        "Featured Article",
        "Most Read",
        "News Briefing",
        "Loading discover feed",
        "Discover Unavailable"
    ].contains { contains($0, in: lastObserved) }
    guard hasReaderSearch, hasTimeMachine, hasEdition else {
        throw DiscoverProbeError.surfaceMissing(Array(lastObserved.prefix(160)))
    }

    let scrollActions = ["AXScrollDownByPage", "AXScrollDown"]
    let scrollAreas = discoverElements.filter {
        (attribute(kAXRoleAttribute as CFString, from: $0) as String?) == (kAXScrollAreaRole as String)
    }
    let readerScrollArea = scrollAreas.first { area in
        let values = uniqueStrings(in: flattenedElements(from: area, limit: 1_500))
        return contains("Search Wikipedia", in: values)
            && exposesNativeVerticalScrolling(area, actions: scrollActions)
    }
    guard let readerScrollArea else {
        let summaries = scrollAreas.map { area in
            let actions = actionNames(for: area).joined(separator: ",")
            let values = uniqueStrings(in: flattenedElements(from: area, limit: 1_500))
                .prefix(16)
                .joined(separator: ",")
            return "Actions=[\(actions)] Values=[\(values)]"
        }
        throw DiscoverProbeError.surfaceMissing(["Scroll areas: \(summaries.joined(separator: " | "))"])
    }
    NSRunningApplication(processIdentifier: pid)?.activate()
    Thread.sleep(forTimeInterval: 0.15)
    let supportedScrollActions = scrollActions.filter { supportsAction($0, element: readerScrollArea) }
    let performedScrollAction = supportedScrollActions.first { action in
        AXUIElementPerformAction(readerScrollArea, action as CFString) == .success
    }
    let advancedScrollbar = performedScrollAction == nil && advanceScrollbar(in: readerScrollArea)
    guard performedScrollAction != nil || advancedScrollbar else {
        throw DiscoverProbeError.surfaceMissing([
            "Native scroll actions and scrollbar value could not advance: \(supportedScrollActions.joined(separator: ","))"
        ])
    }

    Thread.sleep(forTimeInterval: 0.35)
    guard kill(pid, 0) == 0 else {
        throw DiscoverProbeError.surfaceMissing(["Exact process exited after native page scroll"])
    }

    print("DISCOVER_VISIBLE=true")
    print("TIME_MACHINE_VISIBLE=true")
    print("READER_PAGE_VISIBLE=true")
    let scrollMethod = performedScrollAction ?? "AXValue"
    print("NATIVE_PAGE_SCROLL=true method=\(scrollMethod)")
    print("OBSERVED=\(lastObserved.prefix(160).joined(separator: " | "))")
} catch {
    fputs("ax_discover_surface_probe: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
