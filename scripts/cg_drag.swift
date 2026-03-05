#!/usr/bin/swift

import ApplicationServices
import Foundation

struct Args {
    var startX: Double = 0
    var startY: Double = 0
    var endX: Double = 0
    var endY: Double = 0
    var duration: Double = 0.40
    var flipY: Bool = false
}

private func parseArgs() -> Args? {
    var args = Args()
    var sawStartX = false
    var sawStartY = false
    var sawEndX = false
    var sawEndY = false

    var index = 1
    let tokens = CommandLine.arguments
    while index < tokens.count {
        let token = tokens[index]
        switch token {
        case "--start-x":
            index += 1
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            args.startX = value
            sawStartX = true
        case "--start-y":
            index += 1
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            args.startY = value
            sawStartY = true
        case "--end-x":
            index += 1
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            args.endX = value
            sawEndX = true
        case "--end-y":
            index += 1
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            args.endY = value
            sawEndY = true
        case "--duration":
            index += 1
            guard index < tokens.count, let value = Double(tokens[index]) else { return nil }
            args.duration = max(0.05, value)
        case "--flip-y":
            args.flipY = true
        default:
            return nil
        }
        index += 1
    }

    guard sawStartX, sawStartY, sawEndX, sawEndY else { return nil }
    return args
}

private func usage() {
    let text = """
    Usage:
      cg_drag.swift --start-x <x> --start-y <y> --end-x <x> --end-y <y> [--duration <seconds>]
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
        mouseButton: .left
    ) else { return }
    event.post(tap: .cghidEventTap)
}

private func drag(from start: CGPoint, to end: CGPoint, duration: Double) {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        fail("Unable to create CGEvent source")
    }

    postMouseEvent(type: .mouseMoved, point: start, source: source)
    usleep(70_000)
    postMouseEvent(type: .leftMouseDown, point: start, source: source)

    let steps = 32
    let sleepMicros = useconds_t(max(1, Int((duration / Double(steps)) * 1_000_000)))
    for step in 1...steps {
        let t = Double(step) / Double(steps)
        let x = start.x + ((end.x - start.x) * t)
        let y = start.y + ((end.y - start.y) * t)
        postMouseEvent(type: .leftMouseDragged, point: CGPoint(x: x, y: y), source: source)
        usleep(sleepMicros)
    }

    postMouseEvent(type: .leftMouseUp, point: end, source: source)
}

guard let args = parseArgs() else {
    usage()
    exit(64)
}

let trustOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(trustOptions) else {
    fail("Accessibility permission is required for drag simulation.", code: 2)
}

let start = screenSpacePoint(x: args.startX, y: args.startY, flipY: args.flipY)
let end = screenSpacePoint(x: args.endX, y: args.endY, flipY: args.flipY)
drag(from: start, to: end, duration: args.duration)
print("DRAG_OK \(Int(args.startX)),\(Int(args.startY)) -> \(Int(args.endX)),\(Int(args.endY))")
