#!/usr/bin/swift

import ApplicationServices
import Foundation

struct Args {
    var x: Double = 0
    var y: Double = 0
    var flipY: Bool = false
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
      cg_right_click.swift --x <x> --y <y>
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

    let mainDisplay = CGMainDisplayID()
    let displayHeight = Double(CGDisplayPixelsHigh(mainDisplay))
    return CGPoint(x: x, y: displayHeight - y)
}

private func postMouseEvent(type: CGEventType, point: CGPoint, source: CGEventSource) {
    guard let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .right
    ) else { return }
    event.post(tap: .cghidEventTap)
}

guard let args = parseArgs() else {
    usage()
    exit(64)
}

let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(trustOptions) else {
    fail("Accessibility permission is required for right-click simulation.", code: 2)
}

guard let source = CGEventSource(stateID: .combinedSessionState) else {
    fail("Unable to create CGEvent source")
}

let point = screenSpacePoint(x: args.x, y: args.y, flipY: args.flipY)
postMouseEvent(type: .mouseMoved, point: point, source: source)
usleep(70_000)
postMouseEvent(type: .rightMouseDown, point: point, source: source)
usleep(45_000)
postMouseEvent(type: .rightMouseUp, point: point, source: source)

print("RIGHT_CLICK_OK \(Int(args.x)),\(Int(args.y))")
