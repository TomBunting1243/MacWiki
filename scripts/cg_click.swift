#!/usr/bin/swift

import ApplicationServices
import Foundation

struct Args {
    var x: Double = 0
    var y: Double = 0
    var flipY = false
    var clickCount: Int = 1
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
        case "--double":
            args.clickCount = 2
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
      cg_click.swift --x <x> --y <y> [--flip-y] [--double]
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

private func postMouseEvent(type: CGEventType, point: CGPoint, source: CGEventSource, clickState: Int64 = 1) {
    guard let event = CGEvent(
        mouseEventSource: source,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else { return }
    event.setIntegerValueField(.mouseEventClickState, value: clickState)
    event.post(tap: .cghidEventTap)
}

private func click(at point: CGPoint, count: Int) {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        fail("Unable to create CGEvent source")
    }

    postMouseEvent(type: .mouseMoved, point: point, source: source)
    usleep(40_000)

    for tap in 1...max(1, count) {
        let clickState = Int64(tap)
        postMouseEvent(type: .leftMouseDown, point: point, source: source, clickState: clickState)
        usleep(10_000)
        postMouseEvent(type: .leftMouseUp, point: point, source: source, clickState: clickState)
        usleep(80_000)
    }
}

guard let args = parseArgs() else {
    usage()
    exit(64)
}

let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(trustOptions) else {
    fail("Accessibility permission is required for click simulation.", code: 2)
}

let point = screenSpacePoint(x: args.x, y: args.y, flipY: args.flipY)
click(at: point, count: args.clickCount)
print("CLICK_OK x=\(Int(args.x)) y=\(Int(args.y)) count=\(args.clickCount)")
