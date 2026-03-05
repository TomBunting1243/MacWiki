#!/usr/bin/swift

import AppKit
import ApplicationServices
import Foundation

struct Arguments {
    var appName: String = "MacWiki"
    var sourceIdentifier: String = ""
    var targetIdentifier: String = ""
    var timeoutSeconds: Double = 12.0
    var verbose: Bool = false
}

private func parseArguments() -> Arguments {
    var parsed = Arguments()
    var index = 1
    let args = CommandLine.arguments
    while index < args.count {
        let token = args[index]
        switch token {
        case "--app":
            index += 1
            if index < args.count { parsed.appName = args[index] }
        case "--source-id":
            index += 1
            if index < args.count { parsed.sourceIdentifier = args[index] }
        case "--target-id":
            index += 1
            if index < args.count { parsed.targetIdentifier = args[index] }
        case "--timeout":
            index += 1
            if index < args.count, let value = Double(args[index]) { parsed.timeoutSeconds = value }
        case "--verbose":
            parsed.verbose = true
        default:
            break
        }
        index += 1
    }
    return parsed
}

private func usage() {
    let text = """
    Usage:
      ax_drag_area.swift --source-id <AXIdentifier> --target-id <AXIdentifier> [--app <name>] [--timeout <seconds>] [--verbose]
    """
    fputs(text + "\n", stderr)
}

private func appError(_ message: String, exitCode: Int32 = 1) -> Never {
    fputs("ERROR: \(message)\n", stderr)
    exit(exitCode)
}

private func copyAttributeValue(_ element: AXUIElement, attribute: String) -> AnyObject? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success, let value else { return nil }
    return value
}

private func attributeString(_ element: AXUIElement, attribute: String) -> String? {
    copyAttributeValue(element, attribute: attribute) as? String
}

private func attributeElements(_ element: AXUIElement, attribute: String) -> [AXUIElement] {
    (copyAttributeValue(element, attribute: attribute) as? [AXUIElement]) ?? []
}

private func descendantElements(of element: AXUIElement) -> [AXUIElement] {
    var collected: [AXUIElement] = []
    let attributes = [
        kAXChildrenAttribute as String,
        "AXRows",
        "AXVisibleRows",
        "AXContents",
        "AXVisibleChildren",
        "AXUIElements",
        "AXColumns"
    ]

    for attribute in attributes {
        collected.append(contentsOf: attributeElements(element, attribute: attribute))
    }

    if let content = copyAttributeValue(element, attribute: "AXContent"),
       CFGetTypeID(content) == AXUIElementGetTypeID() {
        collected.append(content as! AXUIElement)
    }

    var deduped: [AXUIElement] = []
    var seen: Set<UInt> = []
    for child in collected {
        let key = pointerKey(for: child)
        if seen.insert(key).inserted {
            deduped.append(child)
        }
    }
    return deduped
}

private func elementIdentifier(_ element: AXUIElement) -> String? {
    attributeString(element, attribute: "AXIdentifier")
}

private func elementTitle(_ element: AXUIElement) -> String? {
    attributeString(element, attribute: kAXTitleAttribute as String)
}

private func frame(of element: AXUIElement) -> CGRect? {
    if let rawFrame = copyAttributeValue(element, attribute: "AXFrame"),
       CFGetTypeID(rawFrame) == AXValueGetTypeID() {
        let value = rawFrame as! AXValue
        var rect = CGRect.zero
        if AXValueGetValue(value, .cgRect, &rect) {
            return rect
        }
    }

    guard let rawPosition = copyAttributeValue(element, attribute: kAXPositionAttribute as String),
          let rawSize = copyAttributeValue(element, attribute: kAXSizeAttribute as String),
          CFGetTypeID(rawPosition) == AXValueGetTypeID(),
          CFGetTypeID(rawSize) == AXValueGetTypeID() else {
        return nil
    }

    var point = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point),
          AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else {
        return nil
    }
    return CGRect(origin: point, size: size)
}

private func centerPoint(of rect: CGRect) -> CGPoint {
    CGPoint(x: rect.midX, y: rect.midY)
}

private func pointerKey(for element: AXUIElement) -> UInt {
    UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
}

private func allWindowRoots(for applicationElement: AXUIElement) -> [AXUIElement] {
    var roots: [AXUIElement] = [applicationElement]
    if let focusedRaw = copyAttributeValue(applicationElement, attribute: kAXFocusedWindowAttribute as String),
       CFGetTypeID(focusedRaw) == AXUIElementGetTypeID() {
        let focused = focusedRaw as! AXUIElement
        roots.append(focused)
    }
    roots.append(contentsOf: attributeElements(applicationElement, attribute: kAXWindowsAttribute as String))

    var seen: Set<UInt> = []
    return roots.filter {
        let key = pointerKey(for: $0)
        guard !seen.contains(key) else { return false }
        seen.insert(key)
        return true
    }
}

private func findElement(
    in roots: [AXUIElement],
    identifier expectedIdentifier: String,
    timeout: TimeInterval,
    verbose: Bool
) -> AXUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        var queue = roots
        var visited: Set<UInt> = []
        var nodesVisited = 0

        while !queue.isEmpty && nodesVisited < 50_000 {
            let element = queue.removeFirst()
            let key = pointerKey(for: element)
            guard !visited.contains(key) else { continue }
            visited.insert(key)
            nodesVisited += 1

            if elementIdentifier(element) == expectedIdentifier {
                return element
            }

            queue.append(contentsOf: descendantElements(of: element))
        }

        if verbose {
            fputs("Waiting for AXIdentifier '\(expectedIdentifier)' (visited \(nodesVisited) nodes)\n", stderr)
        }
        usleep(150_000)
    }
    return nil
}

private func postMouseEvent(type: CGEventType, point: CGPoint, source: CGEventSource) {
    guard let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else { return }
    event.post(tap: .cghidEventTap)
}

private func performDrag(from start: CGPoint, to end: CGPoint, duration: TimeInterval = 0.40, steps: Int = 36) {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        appError("Failed to create CGEvent source")
    }

    postMouseEvent(type: .mouseMoved, point: start, source: source)
    usleep(90_000)
    postMouseEvent(type: .leftMouseDown, point: start, source: source)

    let total = max(steps, 1)
    let delayMicros = useconds_t(max(1, Int((duration / Double(total)) * 1_000_000)))

    for step in 1...total {
        let t = CGFloat(step) / CGFloat(total)
        let point = CGPoint(
            x: start.x + ((end.x - start.x) * t),
            y: start.y + ((end.y - start.y) * t)
        )
        postMouseEvent(type: .leftMouseDragged, point: point, source: source)
        usleep(delayMicros)
    }

    postMouseEvent(type: .leftMouseUp, point: end, source: source)
}

private func locateRunningApp(named appName: String, timeout: TimeInterval) -> NSRunningApplication? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName && !$0.isTerminated }) {
            return running
        }
        usleep(120_000)
    }
    return nil
}

let args = parseArguments()
guard !args.sourceIdentifier.isEmpty, !args.targetIdentifier.isEmpty else {
    usage()
    exit(64)
}

let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(trustOptions) else {
    appError("Accessibility permission not granted. Enable Terminal/Codex in System Settings > Privacy & Security > Accessibility.", exitCode: 2)
}

guard let app = locateRunningApp(named: args.appName, timeout: args.timeoutSeconds) else {
    appError("Could not find running app named '\(args.appName)'")
}

app.activate()
usleep(350_000)

let appElement = AXUIElementCreateApplication(app.processIdentifier)
let roots = allWindowRoots(for: appElement)
guard !roots.isEmpty else {
    appError("No windows found for '\(args.appName)'")
}

guard let sourceElement = findElement(
    in: roots,
    identifier: args.sourceIdentifier,
    timeout: args.timeoutSeconds,
    verbose: args.verbose
) else {
    appError("Source element not found: \(args.sourceIdentifier)")
}

guard let targetElement = findElement(
    in: roots,
    identifier: args.targetIdentifier,
    timeout: args.timeoutSeconds,
    verbose: args.verbose
) else {
    appError("Target element not found: \(args.targetIdentifier)")
}

guard let sourceFrame = frame(of: sourceElement) else {
    appError("Could not read source frame for \(args.sourceIdentifier)")
}
guard let targetFrame = frame(of: targetElement) else {
    appError("Could not read target frame for \(args.targetIdentifier)")
}

let start = centerPoint(of: sourceFrame)
let end = centerPoint(of: targetFrame)

if args.verbose {
    let sourceTitle = elementTitle(sourceElement) ?? "<no-title>"
    let targetTitle = elementTitle(targetElement) ?? "<no-title>"
    print("Dragging from \(args.sourceIdentifier) title=\(sourceTitle) frame=\(NSStringFromRect(sourceFrame))")
    print("Dragging to   \(args.targetIdentifier) title=\(targetTitle) frame=\(NSStringFromRect(targetFrame))")
}

performDrag(from: start, to: end)
usleep(500_000)
print("DRAG_OK source=\(args.sourceIdentifier) target=\(args.targetIdentifier)")
