#!/usr/bin/env swift

import ApplicationServices
import AppKit
import Foundation

private enum LifecycleError: LocalizedError {
    case usage
    case failure(String)
    case action(String, AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_main_window_lifecycle.swift <pid> <app-bundle-path> [cycle-count] [--audit-close]"
        case .failure(let message):
            message
        case .action(let label, let error):
            "\(label) rejected AXPress (\(error.rawValue))."
        }
    }
}

private struct RectRecord: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    func approximatelyEquals(_ other: RectRecord, tolerance: Double = 1) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

private struct CycleRecord: Codable {
    let cycle: Int
    let pid: pid_t
    let minimizeLatencyMilliseconds: Double
    let reopenLatencyMilliseconds: Double
    let sameWindowIdentity: Bool
    let framePreserved: Bool
    let totalWindowCount: Int
    let mainWindowCount: Int
    let toolbarCount: Int
    let frameBefore: RectRecord
    let frameAfter: RectRecord
}

private struct LifecycleReport: Codable {
    let pid: pid_t
    let appBundlePath: String
    let bundleIdentifier: String
    let coldReadyLatencyMilliseconds: Double
    let stableObservationSeconds: Double
    let stableSampleCount: Int
    let initialWindowCount: Int
    let initialMainWindowCount: Int
    let initialToolbarCount: Int
    let cycles: [CycleRecord]
    let finalWindowCount: Int
    let finalMainWindowCount: Int
    let finalToolbarCount: Int
    let closeAudit: CloseAuditRecord?
}

private struct CloseAuditRecord: Codable {
    let closeLatencyMilliseconds: Double
    let residencyObservationSeconds: Double
    let processTerminatedAfterClose: Bool
    let processResidentAfterClose: Bool
    let windowCountAfterClose: Int
    let reopenedSamePID: Bool?
    let reopenLatencyMilliseconds: Double?
    let reopenedWindowCount: Int?
    let reopenedMainWindowCount: Int?
    let reopenedToolbarCount: Int?
    let reopenedFramePreserved: Bool?
}

private struct WindowSnapshot {
    let windows: [AXUIElement]
    let mainWindows: [AXUIElement]
    let toolbarCount: Int

    var mainWindow: AXUIElement? {
        mainWindows.count == 1 ? mainWindows[0] : nil
    }

    var isReady: Bool {
        windows.count == 1 && mainWindows.count == 1 && toolbarCount == 0
    }
}

private func attributeValue(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
    return value
}

private func stringAttribute(_ name: CFString, from element: AXUIElement) -> String {
    guard let value = attributeValue(name, from: element) else { return "" }
    if let string = value as? String { return string }
    if let number = value as? NSNumber { return number.stringValue }
    return ""
}

private func boolAttribute(_ name: CFString, from element: AXUIElement) -> Bool? {
    (attributeValue(name, from: element) as? NSNumber)?.boolValue
}

private func directChildren(of element: AXUIElement) -> [AXUIElement] {
    attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
}

private func frame(of element: AXUIElement) -> CGRect? {
    guard let positionValue = attributeValue(kAXPositionAttribute as CFString, from: element),
          let sizeValue = attributeValue(kAXSizeAttribute as CFString, from: element),
          CFGetTypeID(positionValue) == AXValueGetTypeID(),
          CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
        return nil
    }
    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
          AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
        return nil
    }
    return CGRect(origin: position, size: size)
}

private func snapshot(of application: AXUIElement) -> WindowSnapshot {
    let windows = attributeValue(kAXWindowsAttribute as CFString, from: application)
        as? [AXUIElement] ?? []
    let mainWindows = windows.filter {
        stringAttribute(kAXTitleAttribute as CFString, from: $0) == "MacWiki"
    }
    let toolbarCount = mainWindows.count == 1
        ? directChildren(of: mainWindows[0]).filter {
            stringAttribute(kAXRoleAttribute as CFString, from: $0) == kAXToolbarRole as String
        }.count
        : 0
    return WindowSnapshot(
        windows: windows,
        mainWindows: mainWindows,
        toolbarCount: toolbarCount
    )
}

private func press(_ element: AXUIElement, label: String) throws {
    let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
    guard result == .success else { throw LifecycleError.action(label, result) }
}

private func pause(_ duration: TimeInterval) {
    RunLoop.current.run(until: Date().addingTimeInterval(duration))
}

private func wait(
    timeout: TimeInterval,
    pollInterval: TimeInterval = 0.05,
    condition: () -> Bool
) -> Bool {
    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    repeat {
        if condition() { return true }
        pause(pollInterval)
    } while ProcessInfo.processInfo.systemUptime < deadline
    return false
}

private func milliseconds(since start: TimeInterval) -> Double {
    (ProcessInfo.processInfo.systemUptime - start) * 1_000
}

private func runningPIDs(bundleIdentifier: String) -> [pid_t] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { !$0.isTerminated }
        .map(\.processIdentifier)
        .sorted()
}

private func isFrontmost(_ application: AXUIElement) -> Bool {
    boolAttribute(kAXFrontmostAttribute as CFString, from: application) == true
}

private func reopenThroughLaunchServices(appBundlePath: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", appBundlePath]
    do {
        try process.run()
    } catch {
        throw LifecycleError.failure("LaunchServices reopen failed to start: \(error.localizedDescription)")
    }

    let exited = wait(timeout: 5) { !process.isRunning }
    guard exited else {
        process.terminate()
        _ = wait(timeout: 2) { !process.isRunning }
        throw LifecycleError.failure("LaunchServices reopen did not finish within five seconds.")
    }
    guard process.terminationStatus == 0 else {
        throw LifecycleError.failure(
            "LaunchServices reopen exited with status \(process.terminationStatus)."
        )
    }
}

private func describe(_ snapshot: WindowSnapshot) -> String {
    let titles = snapshot.windows.map {
        stringAttribute(kAXTitleAttribute as CFString, from: $0)
    }
    return "windows=\(snapshot.windows.count), main=\(snapshot.mainWindows.count), "
        + "toolbars=\(snapshot.toolbarCount), titles=\(titles)"
}

private func describeReopenState(
    _ snapshot: WindowSnapshot,
    originalWindow: AXUIElement,
    application: AXUIElement,
    runningApplication: NSRunningApplication,
    bundleIdentifier: String
) -> String {
    let currentWindow = snapshot.mainWindow
    let sameIdentity = currentWindow.map { CFEqual($0, originalWindow) }
    let minimized = currentWindow.flatMap {
        boolAttribute(kAXMinimizedAttribute as CFString, from: $0)
    }
    return "\(describe(snapshot)), sameIdentity=\(String(describing: sameIdentity)), "
        + "minimized=\(String(describing: minimized)), frontmost=\(isFrontmost(application)), "
        + "terminated=\(runningApplication.isTerminated), "
        + "bundlePIDs=\(runningPIDs(bundleIdentifier: bundleIdentifier))"
}

private func run() throws {
    let arguments = CommandLine.arguments
    guard (3...5).contains(arguments.count),
          let rawPID = Int32(arguments[1]) else {
        throw LifecycleError.usage
    }
    let pid = pid_t(rawPID)
    let appBundlePath = URL(fileURLWithPath: arguments[2]).standardizedFileURL.path
    let options = Array(arguments.dropFirst(3))
    let unknownOptions = options.filter { $0 != "--audit-close" && Int($0) == nil }
    let cycleOptions = options.compactMap(Int.init)
    guard unknownOptions.isEmpty, cycleOptions.count <= 1 else {
        throw LifecycleError.usage
    }
    let cycleCount = cycleOptions.first ?? 5
    let auditClose = options.contains("--audit-close")
    guard (1...5).contains(cycleCount) else {
        throw LifecycleError.failure("Cycle count must be between one and five.")
    }
    guard FileManager.default.fileExists(atPath: appBundlePath),
          let bundleIdentifier = Bundle(url: URL(fileURLWithPath: appBundlePath))?.bundleIdentifier,
          !bundleIdentifier.isEmpty else {
        throw LifecycleError.failure("The supplied app bundle is missing or has no bundle identifier.")
    }
    guard AXIsProcessTrusted() else {
        throw LifecycleError.failure("Accessibility permission is required for the lifecycle driver.")
    }
    guard let runningApplication = NSRunningApplication(processIdentifier: pid),
          !runningApplication.isTerminated else {
        throw LifecycleError.failure("The target process is not running.")
    }

    let application = AXUIElementCreateApplication(pid)
    let readinessStart = ProcessInfo.processInfo.systemUptime
    var initialSnapshot = snapshot(of: application)
    guard wait(timeout: 15, condition: {
        initialSnapshot = snapshot(of: application)
        return initialSnapshot.isReady
            && runningPIDs(bundleIdentifier: bundleIdentifier) == [pid]
    }), let initialWindow = initialSnapshot.mainWindow else {
        throw LifecycleError.failure(
            "The native main window did not become uniquely ready: \(describe(initialSnapshot))."
        )
    }
    let coldReadyLatency = milliseconds(since: readinessStart)

    let stableObservationSeconds: TimeInterval = 3.25
    let stableDeadline = ProcessInfo.processInfo.systemUptime + stableObservationSeconds
    var stableSampleCount = 0
    repeat {
        let current = snapshot(of: application)
        guard current.isReady,
              let currentWindow = current.mainWindow,
              CFEqual(currentWindow, initialWindow),
              runningPIDs(bundleIdentifier: bundleIdentifier) == [pid],
              !runningApplication.isTerminated else {
            throw LifecycleError.failure(
                "The main window was not stable during the 3.25-second observation: \(describe(current))."
            )
        }
        stableSampleCount += 1
        pause(0.1)
    } while ProcessInfo.processInfo.systemUptime < stableDeadline

    var cycleRecords: [CycleRecord] = []
    for cycle in 1...cycleCount {
        let before = snapshot(of: application)
        guard before.isReady,
              let beforeWindow = before.mainWindow,
              CFEqual(beforeWindow, initialWindow),
              let beforeFrame = frame(of: beforeWindow),
              let minimizeButton = attributeValue(
                kAXMinimizeButtonAttribute as CFString,
                from: beforeWindow
              ),
              CFGetTypeID(minimizeButton) == AXUIElementGetTypeID() else {
            throw LifecycleError.failure(
                "Cycle \(cycle) could not acquire the native main-window controls: \(describe(before))."
            )
        }

        let minimizeStart = ProcessInfo.processInfo.systemUptime
        try press(minimizeButton as! AXUIElement, label: "Minimize")
        guard wait(timeout: 5, condition: {
            boolAttribute(kAXMinimizedAttribute as CFString, from: initialWindow) == true
                && runningPIDs(bundleIdentifier: bundleIdentifier) == [pid]
        }) else {
            throw LifecycleError.failure("Cycle \(cycle) did not minimize the main window within five seconds.")
        }
        let minimizeLatency = milliseconds(since: minimizeStart)

        let minimized = snapshot(of: application)
        guard minimized.isReady,
              let minimizedWindow = minimized.mainWindow,
              CFEqual(minimizedWindow, initialWindow) else {
            throw LifecycleError.failure(
                "Cycle \(cycle) changed the window graph while minimized: \(describe(minimized))."
            )
        }

        let reopenStart = ProcessInfo.processInfo.systemUptime
        try reopenThroughLaunchServices(appBundlePath: appBundlePath)
        var reopened = snapshot(of: application)
        guard wait(timeout: 8, condition: {
            reopened = snapshot(of: application)
            guard reopened.isReady, let reopenedWindow = reopened.mainWindow else { return false }
            return CFEqual(reopenedWindow, initialWindow)
                && boolAttribute(kAXMinimizedAttribute as CFString, from: reopenedWindow) == false
                && runningPIDs(bundleIdentifier: bundleIdentifier) == [pid]
                && !runningApplication.isTerminated
        }), let reopenedWindow = reopened.mainWindow,
              let reopenedFrame = frame(of: reopenedWindow) else {
            throw LifecycleError.failure(
                "Cycle \(cycle) did not reopen the original native window: "
                    + describeReopenState(
                        reopened,
                        originalWindow: initialWindow,
                        application: application,
                        runningApplication: runningApplication,
                        bundleIdentifier: bundleIdentifier
                    )
                    + "."
            )
        }
        let reopenLatency = milliseconds(since: reopenStart)
        let beforeRecord = RectRecord(beforeFrame)
        let afterRecord = RectRecord(reopenedFrame)
        guard beforeRecord.approximatelyEquals(afterRecord) else {
            throw LifecycleError.failure(
                "Cycle \(cycle) changed the main-window frame from \(beforeRecord) to \(afterRecord)."
            )
        }

        let settled = wait(timeout: 0.6, pollInterval: 0.1) {
            let current = snapshot(of: application)
            guard current.isReady, let currentWindow = current.mainWindow else { return false }
            return CFEqual(currentWindow, initialWindow)
                && boolAttribute(kAXMinimizedAttribute as CFString, from: currentWindow) == false
                && runningPIDs(bundleIdentifier: bundleIdentifier) == [pid]
        }
        guard settled else {
            throw LifecycleError.failure(
                "Cycle \(cycle) did not settle with one native window and no window-wide toolbar."
            )
        }

        cycleRecords.append(
            CycleRecord(
                cycle: cycle,
                pid: pid,
                minimizeLatencyMilliseconds: minimizeLatency,
                reopenLatencyMilliseconds: reopenLatency,
                sameWindowIdentity: CFEqual(reopenedWindow, initialWindow),
                framePreserved: beforeRecord.approximatelyEquals(afterRecord),
                totalWindowCount: reopened.windows.count,
                mainWindowCount: reopened.mainWindows.count,
                toolbarCount: reopened.toolbarCount,
                frameBefore: beforeRecord,
                frameAfter: afterRecord
            )
        )
    }

    let finalSnapshot = snapshot(of: application)
    guard finalSnapshot.isReady,
          let finalWindow = finalSnapshot.mainWindow,
          CFEqual(finalWindow, initialWindow),
          runningPIDs(bundleIdentifier: bundleIdentifier) == [pid] else {
        throw LifecycleError.failure(
            "The final main-window graph is not unique and stable: \(describe(finalSnapshot))."
        )
    }

    var closeAudit: CloseAuditRecord?
    if auditClose {
        guard let finalFrame = frame(of: finalWindow),
              let closeButton = attributeValue(
                kAXCloseButtonAttribute as CFString,
                from: finalWindow
              ),
              CFGetTypeID(closeButton) == AXUIElementGetTypeID() else {
            throw LifecycleError.failure("The native main-window close control is unavailable.")
        }

        let closeStart = ProcessInfo.processInfo.systemUptime
        try press(closeButton as! AXUIElement, label: "Close")
        guard wait(timeout: 5, condition: {
            runningApplication.isTerminated || snapshot(of: application).windows.isEmpty
        }) else {
            throw LifecycleError.failure(
                "Red close neither terminated the app nor removed the main window within five seconds."
            )
        }
        let closeLatency = milliseconds(since: closeStart)
        let residencyObservationSeconds: TimeInterval = 2.5
        let residencyDeadline = ProcessInfo.processInfo.systemUptime + residencyObservationSeconds
        while !runningApplication.isTerminated,
              ProcessInfo.processInfo.systemUptime < residencyDeadline {
            let residentSnapshot = snapshot(of: application)
            guard residentSnapshot.windows.isEmpty,
                  runningPIDs(bundleIdentifier: bundleIdentifier) == [pid] else {
                throw LifecycleError.failure(
                    "The red-closed app did not remain in a stable windowless state: "
                        + describe(residentSnapshot)
                        + "."
                )
            }
            pause(0.1)
        }
        let processTerminated = runningApplication.isTerminated
        let afterClose = snapshot(of: application)

        if processTerminated {
            closeAudit = CloseAuditRecord(
                closeLatencyMilliseconds: closeLatency,
                residencyObservationSeconds: residencyObservationSeconds,
                processTerminatedAfterClose: true,
                processResidentAfterClose: false,
                windowCountAfterClose: afterClose.windows.count,
                reopenedSamePID: nil,
                reopenLatencyMilliseconds: nil,
                reopenedWindowCount: nil,
                reopenedMainWindowCount: nil,
                reopenedToolbarCount: nil,
                reopenedFramePreserved: nil
            )
        } else {
            guard afterClose.windows.isEmpty,
                  runningPIDs(bundleIdentifier: bundleIdentifier) == [pid] else {
                throw LifecycleError.failure(
                    "Red close left an unexpected resident window/process graph: \(describe(afterClose))."
                )
            }
            let reopenStart = ProcessInfo.processInfo.systemUptime
            try reopenThroughLaunchServices(appBundlePath: appBundlePath)
            var reopened = snapshot(of: application)
            guard wait(timeout: 8, condition: {
                reopened = snapshot(of: application)
                return reopened.isReady
                    && runningPIDs(bundleIdentifier: bundleIdentifier) == [pid]
                    && !runningApplication.isTerminated
            }), let reopenedWindow = reopened.mainWindow,
                  let reopenedFrame = frame(of: reopenedWindow) else {
                throw LifecycleError.failure(
                    "LaunchServices did not recreate one native main window in the resident process: "
                        + describeReopenState(
                            reopened,
                            originalWindow: finalWindow,
                            application: application,
                            runningApplication: runningApplication,
                            bundleIdentifier: bundleIdentifier
                        )
                        + "."
                )
            }
            closeAudit = CloseAuditRecord(
                closeLatencyMilliseconds: closeLatency,
                residencyObservationSeconds: residencyObservationSeconds,
                processTerminatedAfterClose: false,
                processResidentAfterClose: true,
                windowCountAfterClose: afterClose.windows.count,
                reopenedSamePID: runningPIDs(bundleIdentifier: bundleIdentifier) == [pid],
                reopenLatencyMilliseconds: milliseconds(since: reopenStart),
                reopenedWindowCount: reopened.windows.count,
                reopenedMainWindowCount: reopened.mainWindows.count,
                reopenedToolbarCount: reopened.toolbarCount,
                reopenedFramePreserved: RectRecord(finalFrame)
                    .approximatelyEquals(RectRecord(reopenedFrame))
            )
        }
    }

    let report = LifecycleReport(
        pid: pid,
        appBundlePath: appBundlePath,
        bundleIdentifier: bundleIdentifier,
        coldReadyLatencyMilliseconds: coldReadyLatency,
        stableObservationSeconds: stableObservationSeconds,
        stableSampleCount: stableSampleCount,
        initialWindowCount: initialSnapshot.windows.count,
        initialMainWindowCount: initialSnapshot.mainWindows.count,
        initialToolbarCount: initialSnapshot.toolbarCount,
        cycles: cycleRecords,
        finalWindowCount: finalSnapshot.windows.count,
        finalMainWindowCount: finalSnapshot.mainWindows.count,
        finalToolbarCount: finalSnapshot.toolbarCount,
        closeAudit: closeAudit
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(report))
    FileHandle.standardOutput.write(Data("\n".utf8))
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
    exit(1)
}
