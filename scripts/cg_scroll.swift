#!/usr/bin/swift

import ApplicationServices
import Foundation

struct Args {
    var x: Double = 0
    var y: Double = 0
    var deltaY: Int32 = -6
    var steps: Int = 24
    var intervalMs: Int = 18
    var flipY = false
}

private func parseArgs() -> Args? {
    var args = Args()
    var sawX = false
    var sawY = false
    var index = 1
    let tokens = CommandLine.arguments

    while index < tokens.count {
        let token = tokens[index]
        switch token {
        case "--x":
            index += 1
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            args.x = value
            sawX = true
        case "--y":
            index += 1
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            args.y = value
            sawY = true
        case "--delta-y":
            index += 1
            guard index < tokens.count, let value = Int32(tokens[index]) else { return nil }
            args.deltaY = value
        case "--steps":
            index += 1
            guard index < tokens.count, let value = Int(tokens[index]) else { return nil }
            args.steps = max(1, value)
        case "--interval-ms":
            index += 1
            guard index < tokens.count, let value = Int(tokens[index]) else { return nil }
            args.intervalMs = max(1, value)
        case "--flip-y":
            args.flipY = true
        default:
            return nil
        }
        index += 1
    }

    guard sawX, sawY else { return nil }
    return args
}

private func usage() {
    let text = """
    Usage:
      cg_scroll.swift --x <x> --y <y> [--delta-y <-6>] [--steps 24] [--interval-ms 18] [--flip-y]
    """
    fputs(text + "\n", stderr)
}

private func fail(_ message: String, code: Int32 = 1) -> Never {
    fputs("ERROR: \(message)\n", stderr)
    exit(code)
}

private func screenSpacePoint(x: Double, y: Double, flipY: Bool) -> CGPoint {
    guard flipY else {
        return CGPoint(x: x, y: y)
    }
    let displayHeight = Double(CGDisplayPixelsHigh(CGMainDisplayID()))
    return CGPoint(x: x, y: displayHeight - y)
}

private func moveMouse(to point: CGPoint, source: CGEventSource) {
    guard let moveEvent = CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else { return }
    moveEvent.post(tap: .cghidEventTap)
}

private func postScroll(deltaY: Int32, source: CGEventSource) {
    guard let scrollEvent = CGEvent(
        scrollWheelEvent2Source: source,
        units: .line,
        wheelCount: 1,
        wheel1: deltaY,
        wheel2: 0,
        wheel3: 0
    ) else { return }
    scrollEvent.post(tap: .cghidEventTap)
}

guard let args = parseArgs() else {
    usage()
    exit(64)
}

let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(trustOptions) else {
    fail("Accessibility permission is required for scroll simulation.", code: 2)
}

guard let source = CGEventSource(stateID: .combinedSessionState) else {
    fail("Unable to create CGEvent source")
}

let point = screenSpacePoint(x: args.x, y: args.y, flipY: args.flipY)
moveMouse(to: point, source: source)
usleep(50_000)

for _ in 0..<args.steps {
    postScroll(deltaY: args.deltaY, source: source)
    usleep(useconds_t(args.intervalMs * 1_000))
}

print("SCROLL_OK x=\(Int(args.x)) y=\(Int(args.y)) deltaY=\(args.deltaY) steps=\(args.steps)")
