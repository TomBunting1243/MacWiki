#!/usr/bin/env swift

import ApplicationServices
import Foundation

private let traceEnabled = ProcessInfo.processInfo.environment["MACWIKI_QA_AX_TRACE"] == "1"

private func trace(_ message: String) {
    guard traceEnabled else { return }
    fputs("ax_reader_inspector_journey: \(message)\n", stderr)
}

private func traceRuntimeDiagnostics(_ stage: String) {
    guard traceEnabled,
          let path = ProcessInfo.processInfo.environment["MACWIKI_QA_APP_LOG"],
          let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
        return
    }
    let cycleCount = contents.components(separatedBy: "AttributeGraph: cycle detected").count - 1
    trace("runtime diagnostics after \(stage): \(cycleCount) AttributeGraph cycles")
}

private enum JourneyError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case missing(String)
    case actionFailed(String, AXError)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_reader_inspector_journey.swift <pid> <article title>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missing(let description):
            description
        case .actionFailed(let label, let error):
            "\(label) rejected AXPress (\(error.rawValue))."
        }
    }
}

private struct JourneyResult: Codable {
    let pid: Int32
    let articleTitle: String
    let readerControls: [String]
    let readStateControlCycle: String
    let inspectorStates: [String: [String]]
    let findBar: [String]
    let workspaceStructure: String
    let toolbarPlaneContainment: String
    let toolbarModeSwitchStability: String
    let toolbarModeSwitchSampleCount: Int
    let inspectorAccessoryAlignment: String
    let auxiliaryPaneMatrix: String
    let inspectorToggleCycle: String
    let narrowPaneRestoreCycle: String
}

private struct PaneVisibilityState: Equatable {
    let lists: Bool
    let directory: Bool
    let inspector: Bool

    var summary: String {
        "Lists=\(lists), List Contents=\(directory), Inspector=\(inspector)"
    }

    var expectedVisiblePaneCount: Int {
        1 + [lists, directory, inspector].filter { $0 }.count
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
    if let attributed = value as? NSAttributedString { return attributed.string }
    if let number = value as? NSNumber { return number.stringValue }
    return ""
}

private func accessibilityLabels(of element: AXUIElement) -> [String] {
    [
        stringAttribute(kAXTitleAttribute as CFString, from: element),
        stringAttribute(kAXDescriptionAttribute as CFString, from: element),
        stringAttribute(kAXValueAttribute as CFString, from: element)
    ].filter { !$0.isEmpty }
}

private func elements(in root: AXUIElement, limit: Int = 5_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [root]
    var nextIndex = 0
    while nextIndex < pending.count, result.count < limit {
        let element = pending[nextIndex]
        nextIndex += 1
        result.append(element)
        if stringAttribute(kAXRoleAttribute as CFString, from: element) == "AXWebArea" {
            continue
        }
        let children = attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
        pending.append(contentsOf: children)
    }
    return result
}

private func directChildren(of element: AXUIElement) -> [AXUIElement] {
    attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
}

private func hasRole(_ element: AXUIElement, _ role: String) -> Bool {
    stringAttribute(kAXRoleAttribute as CFString, from: element) == role
}

private func parent(of element: AXUIElement) -> AXUIElement? {
    guard let value = attributeValue(kAXParentAttribute as CFString, from: element),
          CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return nil
    }
    return (value as! AXUIElement)
}

private func nativeWindowToolbar(in window: AXUIElement) -> AXUIElement? {
    elements(in: window, limit: 1_000).first {
        hasRole($0, kAXToolbarRole as String)
    }
}

private func inspectorModeGroup(in window: AXUIElement) -> AXUIElement? {
    elements(in: window, limit: 1_500).first { candidate in
        let role = stringAttribute(kAXRoleAttribute as CFString, from: candidate)
        guard [kAXRadioGroupRole as String, "AXTabGroup", "AXSegmentedControl"].contains(role) else {
            return false
        }
        let candidateLabels = Set(elements(in: candidate, limit: 30).flatMap(accessibilityLabels))
        return candidateLabels.isSuperset(of: ["Info", "Notes", "References"])
    }
}

private func inspectorPane(in window: AXUIElement) -> AXUIElement? {
    guard let workspace = workspaceSplitGroup(in: window) else { return nil }
    return visibleWorkspacePaneGroups(in: workspace)
        .compactMap { element -> (AXUIElement, CGRect)? in
            guard let frame = elementFrame(element) else { return nil }
            return (element, frame)
        }
        .max { $0.1.maxX < $1.1.maxX }?
        .0
}

private func readerPane(in window: AXUIElement, articleTitle: String) -> AXUIElement? {
    guard let workspace = workspaceSplitGroup(in: window) else { return nil }
    return visibleWorkspacePaneGroups(in: workspace).first { candidate in
        elements(in: candidate, limit: 1_000).contains { element in
            hasRole(element, "AXWebArea") && containsLabel(articleTitle, in: element)
        }
    }
}

private func readerWebArea(in window: AXUIElement, articleTitle: String) -> AXUIElement? {
    guard let reader = readerPane(in: window, articleTitle: articleTitle) else { return nil }
    return elements(in: reader, limit: 1_000).first {
        hasRole($0, "AXWebArea")
    }
}

private func workspaceSplitGroup(in window: AXUIElement) -> AXUIElement? {
    elements(in: window, limit: 2_000).first { candidate in
        guard hasRole(candidate, kAXSplitGroupRole as String) else { return false }
        let directGroups = directChildren(of: candidate).filter {
            hasRole($0, kAXGroupRole as String)
        }
        // macOS 26 exposes each native split-item accessory as a sibling AXGroup
        // of its pane content. Identify the semantic workspace by the Reader's
        // native tab accessory rather than assuming one direct group per pane.
        return directGroups.contains {
            button(in: $0, label: "New Tab") != nil
        }
    }
}

private func traceWorkspaceCandidates(in window: AXUIElement) {
    guard traceEnabled else { return }
    let candidates = elements(in: window, limit: 2_000).filter {
        hasRole($0, kAXSplitGroupRole as String)
    }
    trace("workspace candidate count: \(candidates.count)")
    for (candidateIndex, candidate) in candidates.enumerated() {
        let children = directChildren(of: candidate)
        trace("workspace candidate \(candidateIndex) direct children: \(children.count)")
        for (childIndex, child) in children.enumerated() {
            let role = stringAttribute(kAXRoleAttribute as CFString, from: child)
            let frame = elementFrame(child).map {
                "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))"
            } ?? "no-frame"
            let childLabels = accessibilityLabels(of: child).joined(separator: " / ")
            trace("  child \(childIndex): \(role) \(frame) [\(childLabels)]")
        }
    }
}

private func visibleWorkspacePaneGroups(in splitGroup: AXUIElement) -> [AXUIElement] {
    let visibleGroups = directChildren(of: splitGroup)
        .filter { hasRole($0, kAXGroupRole as String) }
        .filter { elementSize($0).map { $0.width > 1 && $0.height > 1 } == true }
    let referenceHeight = elementSize(splitGroup)?.height
        ?? visibleGroups.compactMap(elementSize).map(\.height).max()
        ?? 0
    guard referenceHeight > 0 else { return [] }
    return visibleGroups.filter {
        elementSize($0).map { $0.height >= referenceHeight * 0.5 } == true
    }
}

private func nativeSplitPaneSizes(in window: AXUIElement) -> String {
    guard let workspace = workspaceSplitGroup(in: window) else { return "unavailable" }
    let sizes = visibleWorkspacePaneGroups(in: workspace)
        .compactMap(elementSize)
        .map { "\(Int($0.width))x\(Int($0.height))" }
    return sizes.isEmpty ? "unavailable" : sizes.joined(separator: ", ")
}

private func mainWindow(in application: AXUIElement) -> AXUIElement? {
    let windows = attributeValue(kAXWindowsAttribute as CFString, from: application) as? [AXUIElement] ?? []
    return windows.first { window in
        stringAttribute(kAXTitleAttribute as CFString, from: window) == "MacWiki"
    }
}

private func labels(in application: AXUIElement) -> [String] {
    var seen = Set<String>()
    return elements(in: application)
        .flatMap(accessibilityLabels)
        .filter { seen.insert($0).inserted }
}

private func matchesAXLabel(_ candidate: String, expected: String) -> Bool {
    candidate == expected || candidate.hasPrefix("\(expected),")
}

private func containsLabel(_ label: String, in root: AXUIElement) -> Bool {
    labels(in: root).contains { $0.localizedCaseInsensitiveContains(label) }
}

private func element(
    in application: AXUIElement,
    role: String,
    label: String
) -> AXUIElement? {
    elements(in: application).first { element in
        guard stringAttribute(kAXRoleAttribute as CFString, from: element) == role else { return false }
        return [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXHelpAttribute as CFString, from: element),
            stringAttribute(kAXPlaceholderValueAttribute as CFString, from: element)
        ].contains { matchesAXLabel($0, expected: label) }
    }
}

private func labeledElement(in root: AXUIElement, label: String) -> AXUIElement? {
    elements(in: root).first { element in
        [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXHelpAttribute as CFString, from: element)
        ].contains { matchesAXLabel($0, expected: label) }
    }
}

private func matchingElements(
    in application: AXUIElement,
    role: String,
    label: String
) -> [AXUIElement] {
    elements(in: application).filter { element in
        guard stringAttribute(kAXRoleAttribute as CFString, from: element) == role else { return false }
        return [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            stringAttribute(kAXHelpAttribute as CFString, from: element),
            stringAttribute(kAXPlaceholderValueAttribute as CFString, from: element)
        ].contains { matchesAXLabel($0, expected: label) }
    }
}

private func button(in application: AXUIElement, label: String) -> AXUIElement? {
    element(in: application, role: kAXButtonRole as String, label: label)
}

private func toolbarControl(in toolbar: AXUIElement, label: String) -> AXUIElement? {
    toolbarControl(in: elements(in: toolbar, limit: 300), label: label)
}

private func toolbarControl(in candidates: [AXUIElement], label: String) -> AXUIElement? {
    for role in [kAXButtonRole as String, kAXMenuButtonRole as String] {
        if let result = candidates.first(where: { candidate in
            guard hasRole(candidate, role) else { return false }
            return [
                stringAttribute(kAXTitleAttribute as CFString, from: candidate),
                stringAttribute(kAXDescriptionAttribute as CFString, from: candidate),
                stringAttribute(kAXHelpAttribute as CFString, from: candidate),
                stringAttribute(kAXPlaceholderValueAttribute as CFString, from: candidate)
            ].contains { matchesAXLabel($0, expected: label) }
        }) {
            return result
        }
    }
    return nil
}

private func isSelected(_ element: AXUIElement) -> Bool {
    let selected = stringAttribute(kAXSelectedAttribute as CFString, from: element)
    if ["1", "true", "selected"].contains(selected.lowercased()) {
        return true
    }
    return ["1", "true", "selected"].contains(
        stringAttribute(kAXValueAttribute as CFString, from: element).lowercased()
    )
}

private func isEnabled(_ element: AXUIElement) -> Bool {
    ["1", "true"].contains(
        stringAttribute(kAXEnabledAttribute as CFString, from: element).lowercased()
    )
}

private func supportsAction(_ action: CFString, on element: AXUIElement) -> Bool {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success,
          let actionNames = names as? [String] else {
        return false
    }
    return actionNames.contains(action as String)
}

private func press(_ element: AXUIElement, label: String) throws {
    var result: AXError = .cannotComplete
    for _ in 0..<10 {
        result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if result == .success { return }
        guard result == .cannotComplete else { break }
        Thread.sleep(forTimeInterval: 0.1)
    }
    throw JourneyError.actionFailed(label, result)
}

private func setWindowSize(_ requestedSize: CGSize, for window: AXUIElement) throws {
    var targetSize = requestedSize
    guard let value = AXValueCreate(.cgSize, &targetSize) else {
        throw JourneyError.missing("Could not create the reader journey window size.")
    }
    let result = AXUIElementSetAttributeValue(
        window,
        kAXSizeAttribute as CFString,
        value
    )
    guard result == .success else {
        throw JourneyError.actionFailed("Resize reader window", result)
    }
}

private func ensureInspectorTestWidth(for window: AXUIElement) throws {
    try setWindowSize(CGSize(width: 1_760, height: 900), for: window)
}

private func windowSize(_ window: AXUIElement) -> CGSize? {
    guard let rawValue = attributeValue(kAXSizeAttribute as CFString, from: window),
          CFGetTypeID(rawValue) == AXValueGetTypeID() else {
        return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(rawValue as! AXValue, .cgSize, &size) else { return nil }
    return size
}

private func elementSize(_ element: AXUIElement) -> CGSize? {
    guard let rawValue = attributeValue(kAXSizeAttribute as CFString, from: element),
          CFGetTypeID(rawValue) == AXValueGetTypeID() else {
        return nil
    }
    var size = CGSize.zero
    guard AXValueGetValue(rawValue as! AXValue, .cgSize, &size) else { return nil }
    return size
}

private func elementPosition(_ element: AXUIElement) -> CGPoint? {
    guard let rawValue = attributeValue(kAXPositionAttribute as CFString, from: element),
          CFGetTypeID(rawValue) == AXValueGetTypeID() else {
        return nil
    }
    var position = CGPoint.zero
    guard AXValueGetValue(rawValue as! AXValue, .cgPoint, &position) else { return nil }
    return position
}

private func elementFrame(_ element: AXUIElement) -> CGRect? {
    guard let position = elementPosition(element), let size = elementSize(element) else { return nil }
    return CGRect(origin: position, size: size)
}

private func wait(
    timeout: TimeInterval = 20,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.12)
    } while Date() < deadline
    return false
}

private func settleAccessibility(for duration: TimeInterval = 0.35) {
    Thread.sleep(forTimeInterval: duration)
}

do {
    guard CommandLine.arguments.count == 3,
          let pid = pid_t(CommandLine.arguments[1]) else {
        throw JourneyError.usage
    }
    guard AXIsProcessTrusted() else { throw JourneyError.accessibilityUnavailable }

    let articleTitle = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid)
    var resolvedArticleWindow: AXUIElement?
    guard wait(timeout: 35, condition: {
        guard let window = mainWindow(in: application) else { return false }
        resolvedArticleWindow = window
        return true
    }) else {
        throw JourneyError.missing("The article window did not become accessible.")
    }
    guard let contentWindow = resolvedArticleWindow else {
        throw JourneyError.missing("The article window disappeared during accessibility setup.")
    }

    // Do not recursively enumerate a newly published NSHostingView. SwiftUI may
    // still be bridging its accessibility graph immediately after the window is
    // announced, and querying AXChildren during that update is re-entrant.
    settleAccessibility(for: 1.0)
    guard wait(timeout: 10, condition: {
        readerWebArea(in: contentWindow, articleTitle: articleTitle) != nil
    }) else {
        traceWorkspaceCandidates(in: contentWindow)
        throw JourneyError.missing("The seeded article did not become accessible in the main window.")
    }
    traceRuntimeDiagnostics("initial window discovery")
    try ensureInspectorTestWidth(for: contentWindow)
    settleAccessibility(for: 0.75)
    traceRuntimeDiagnostics("window resize")

    func refreshNativeToolbar() throws -> AXUIElement {
        guard let toolbar = nativeWindowToolbar(in: contentWindow) else {
            throw JourneyError.missing("The native window toolbar disappeared during the journey.")
        }
        return toolbar
    }

    func toolbarButton(_ label: String) throws -> AXUIElement {
        let toolbar = try refreshNativeToolbar()
        guard let result = toolbarControl(in: toolbar, label: label) else {
            throw JourneyError.missing("The native window toolbar omitted \(label).")
        }
        return result
    }

    func inspectorToggleButton(_ label: String) throws -> AXUIElement {
        let toolbar = try refreshNativeToolbar()
        guard let result = toolbarControl(in: toolbar, label: label) else {
            throw JourneyError.missing("The native Reader toolbar omitted \(label).")
        }
        return result
    }

    let listContentsControlReport: String
    let initialToolbar = try refreshNativeToolbar()
    var modeGroup = inspectorModeGroup(in: initialToolbar)
    if toolbarControl(in: initialToolbar, label: "Hide List Contents") != nil {
        listContentsControlReport = "Hide List Contents"
    } else if toolbarControl(in: initialToolbar, label: "Show List Contents") != nil {
        listContentsControlReport = "Show List Contents"
    } else {
        throw JourneyError.missing("The native window toolbar omitted its List Contents control.")
    }
    let listsControlReport: String
    if toolbarControl(in: initialToolbar, label: "Hide Lists") != nil {
        listsControlReport = "Hide Lists"
    } else if toolbarControl(in: initialToolbar, label: "Show Lists") != nil {
        listsControlReport = "Show Lists"
    } else {
        throw JourneyError.missing("The native window toolbar omitted its Lists control.")
    }
    guard wait(timeout: 4, condition: {
        containsLabel("Tab History", in: contentWindow)
    }) else {
        traceWorkspaceCandidates(in: contentWindow)
        trace("toolbar labels: \(labels(in: initialToolbar).joined(separator: " | "))")
        throw JourneyError.missing("The seeded List Contents pane was not initially visible.")
    }
    if modeGroup.map(isEnabled) != true {
        guard wait(condition: {
            guard let inspector = try? inspectorToggleButton("Show Inspector") else { return false }
            return isEnabled(inspector)
        }), let inspector = try? inspectorToggleButton("Show Inspector") else {
            throw JourneyError.missing(
                "Inspector never became enabled at the wide test size \(String(describing: windowSize(contentWindow)))."
            )
        }
        try press(inspector, label: "Show Inspector")
        settleAccessibility(for: 0.45)
    }
    guard wait(condition: {
        guard let toolbar = try? refreshNativeToolbar() else { return false }
        modeGroup = inspectorModeGroup(in: toolbar)
        return modeGroup.map(isEnabled) == true
    }) else {
        throw JourneyError.missing("The native inspector did not become accessible.")
    }
    traceRuntimeDiagnostics("inspector readiness")
    trace("native window toolbar and four-pane AppKit workspace ready")

    guard let initialReaderWebArea = readerWebArea(
        in: contentWindow,
        articleTitle: articleTitle
    ) else {
        throw JourneyError.missing("The seeded Reader did not expose a stable Web area.")
    }
    guard let initialWorkspaceSplit = workspaceSplitGroup(in: contentWindow) else {
        throw JourneyError.missing("The main window did not expose four visible workspace pane groups.")
    }
    let initialPaneFrames = visibleWorkspacePaneGroups(in: initialWorkspaceSplit)
        .compactMap(elementFrame)
        .sorted { $0.minX < $1.minX }
    guard initialPaneFrames.count == 4 else {
        throw JourneyError.missing(
            "The workspace exposed \(initialPaneFrames.count) visible pane frames instead of four."
        )
    }
    let readerFrame = initialPaneFrames[2]
    let inspectorFrame = initialPaneFrames[3]
    let paneAlignmentTolerance: CGFloat = 2
    guard inspectorFrame.minY <= readerFrame.minY + paneAlignmentTolerance,
          inspectorFrame.maxY >= readerFrame.maxY - paneAlignmentTolerance,
          inspectorFrame.height + paneAlignmentTolerance >= readerFrame.height else {
        throw JourneyError.missing(
            "The Inspector pane region did not span the full Reader pane height: "
                + "Reader=\(readerFrame), Inspector=\(inspectorFrame)."
        )
    }
    let workspaceStructure = "four visible AppKit pane regions; Inspector spans the full Reader pane height"

    func readerWebAreaIdentityIsStable() -> Bool {
        guard let current = readerWebArea(in: contentWindow, articleTitle: articleTitle) else {
            return false
        }
        return CFEqual(current, initialReaderWebArea)
    }

    func paneStateMatches(_ expected: PaneVisibilityState) -> Bool {
        guard let toolbar = try? refreshNativeToolbar(),
              let workspace = workspaceSplitGroup(in: contentWindow) else { return false }
        let listsVisible = containsLabel("Explore", in: contentWindow)
        let directoryVisible = containsLabel("Tab History", in: contentWindow)
        let inspectorVisible = inspectorModeGroup(in: toolbar).map(isEnabled) == true
        let visiblePaneCount = visibleWorkspacePaneGroups(in: workspace).count
        let expectedListsControl = expected.lists ? "Hide Lists" : "Show Lists"
        let expectedDirectoryControl = expected.directory ? "Hide List Contents" : "Show List Contents"
        let expectedInspectorControl = expected.inspector ? "Hide Inspector" : "Show Inspector"
        return listsVisible == expected.lists
            && directoryVisible == expected.directory
            && inspectorVisible == expected.inspector
            && visiblePaneCount == expected.expectedVisiblePaneCount
            && toolbarControl(in: toolbar, label: expectedListsControl) != nil
            && toolbarControl(in: toolbar, label: expectedDirectoryControl) != nil
            && toolbarControl(in: toolbar, label: expectedInspectorControl) != nil
            && readerWebAreaIdentityIsStable()
    }

    var currentPaneState = PaneVisibilityState(lists: true, directory: true, inspector: true)

    func movePanes(to target: PaneVisibilityState, context: String) throws {
        let widthBefore = windowSize(contentWindow)?.width
        if currentPaneState.lists != target.lists {
            let label = currentPaneState.lists ? "Hide Lists" : "Show Lists"
            try press(try toolbarButton(label), label: label)
            currentPaneState = PaneVisibilityState(
                lists: target.lists,
                directory: currentPaneState.directory,
                inspector: currentPaneState.inspector
            )
            guard wait(timeout: 4, condition: { paneStateMatches(currentPaneState) }) else {
                throw JourneyError.missing("\(context) did not settle after \(label).")
            }
        }
        if currentPaneState.directory != target.directory {
            let label = currentPaneState.directory ? "Hide List Contents" : "Show List Contents"
            try press(try toolbarButton(label), label: label)
            currentPaneState = PaneVisibilityState(
                lists: currentPaneState.lists,
                directory: target.directory,
                inspector: currentPaneState.inspector
            )
            guard wait(timeout: 4, condition: { paneStateMatches(currentPaneState) }) else {
                throw JourneyError.missing("\(context) did not settle after \(label).")
            }
        }
        if currentPaneState.inspector != target.inspector {
            let label = currentPaneState.inspector ? "Hide Inspector" : "Show Inspector"
            try press(try inspectorToggleButton(label), label: label)
            currentPaneState = PaneVisibilityState(
                lists: currentPaneState.lists,
                directory: currentPaneState.directory,
                inspector: target.inspector
            )
            guard wait(timeout: 4, condition: { paneStateMatches(currentPaneState) }) else {
                throw JourneyError.missing("\(context) did not settle after Inspector.")
            }
        }
        guard paneStateMatches(target) else {
            throw JourneyError.missing("\(context) did not reach \(target.summary).")
        }
        if let widthBefore, let widthAfter = windowSize(contentWindow)?.width,
           abs(widthAfter - widthBefore) >= 2 {
            throw JourneyError.missing("\(context) resized the whole window from \(widthBefore) to \(widthAfter).")
        }
    }

    let expectedReaderControls = [
        "Back", "Forward", "Search Wikipedia", "Save Article",
        "Mark as Read", "Find in Page", "Reader Style",
        "Page Views", "Open in Browser", "Share"
    ]
    let contractToolbar = try refreshNativeToolbar()
    let missingToolbarControls = expectedReaderControls.filter {
        toolbarControl(in: contractToolbar, label: $0) == nil
    }
    guard missingToolbarControls.isEmpty else {
        if traceEnabled,
           let currentToolbar = try? refreshNativeToolbar() {
            let summary = elements(in: currentToolbar, limit: 300).map { element in
                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
                let description = stringAttribute(kAXDescriptionAttribute as CFString, from: element)
                return "\(role)|\(title)|\(description)"
            }
            trace("native toolbar AX: \(summary)")
        }
        throw JourneyError.missing(
            "Native window toolbar omitted accessible controls: \(missingToolbarControls.joined(separator: ", "))"
        )
    }
    traceRuntimeDiagnostics("toolbar presence and enabled-state checks")

    for label in [
        "Search Wikipedia", "Save Article", "Mark as Read", "Find in Page",
        "Reader Style", "Page Views", "Open in Browser", "Share", "Hide Inspector"
    ] {
        guard let control = toolbarControl(in: contractToolbar, label: label),
              isEnabled(control),
              supportsAction(kAXPressAction as CFString, on: control) else {
            throw JourneyError.missing("Native Reader control \(label) was not enabled.")
        }
    }

    let readCycleToolbar = try refreshNativeToolbar()
    let readCycleToolbarElementCount = elements(in: readCycleToolbar, limit: 300).count
    let initialReadControl = try toolbarButton("Mark as Read")
    guard let initialReadFrame = elementFrame(initialReadControl) else {
        throw JourneyError.missing("Mark as Read did not expose a stable AX frame.")
    }
    try press(initialReadControl, label: "Mark as Read")
    guard wait(timeout: 4, condition: {
        guard let toolbar = try? refreshNativeToolbar() else { return false }
        return CFEqual(toolbar, readCycleToolbar)
            && elements(in: toolbar, limit: 300).count == readCycleToolbarElementCount
            && toolbarControl(in: toolbar, label: "Mark as Unread") != nil
            && toolbarControl(in: toolbar, label: "Mark as Read") == nil
    }), let unreadControl = try? toolbarButton("Mark as Unread"),
          let unreadFrame = elementFrame(unreadControl),
          abs(unreadFrame.minX - initialReadFrame.minX) <= 1,
          abs(unreadFrame.minY - initialReadFrame.minY) <= 1,
          abs(unreadFrame.width - initialReadFrame.width) <= 1,
          abs(unreadFrame.height - initialReadFrame.height) <= 1 else {
        throw JourneyError.missing(
            "Mark as Read did not become Mark as Unread in place on the native toolbar."
        )
    }
    traceRuntimeDiagnostics("Mark as Read")
    try press(unreadControl, label: "Mark as Unread")
    guard wait(timeout: 4, condition: {
        guard let toolbar = try? refreshNativeToolbar() else { return false }
        return CFEqual(toolbar, readCycleToolbar)
            && elements(in: toolbar, limit: 300).count == readCycleToolbarElementCount
            && toolbarControl(in: toolbar, label: "Mark as Read") != nil
            && toolbarControl(in: toolbar, label: "Mark as Unread") == nil
    }), let restoredReadControl = try? toolbarButton("Mark as Read"),
          let restoredReadFrame = elementFrame(restoredReadControl),
          abs(restoredReadFrame.minX - initialReadFrame.minX) <= 1,
          abs(restoredReadFrame.minY - initialReadFrame.minY) <= 1,
          abs(restoredReadFrame.width - initialReadFrame.width) <= 1,
          abs(restoredReadFrame.height - initialReadFrame.height) <= 1 else {
        throw JourneyError.missing(
            "Mark as Unread did not restore Mark as Read in place on the native toolbar."
        )
    }
    traceRuntimeDiagnostics("Mark as Unread")
    let readStateControlCycle =
        "Mark as Read changed to Mark as Unread and restored in place without replacing the toolbar"

    guard labeledElement(in: contentWindow, label: "More Reader Actions") == nil else {
        throw JourneyError.missing("The retired custom More Reader Actions control is still exposed.")
    }

    let reportedReaderControls = [listsControlReport, listContentsControlReport]
        + expectedReaderControls + ["Hide Inspector", "Show Inspector"]

    let readerPlaneLabels = expectedReaderControls + ["Hide Inspector"]
    let inspectorModeLabels = Set(["Info", "Notes", "References"])
    func inspectorModeButtons(in group: AXUIElement) -> [AXUIElement] {
        elements(in: group, limit: 20).filter { candidate in
            [kAXRadioButtonRole as String, "AXTab", kAXButtonRole as String].contains(
                stringAttribute(kAXRoleAttribute as CFString, from: candidate)
            )
                && !inspectorModeLabels.isDisjoint(
                    with: accessibilityLabels(of: candidate)
                )
                && supportsAction(kAXPressAction as CFString, on: candidate)
        }
    }

    func frameMatches(_ candidate: CGRect, _ baseline: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(candidate.minX - baseline.minX) <= tolerance
            && abs(candidate.minY - baseline.minY) <= tolerance
            && abs(candidate.width - baseline.width) <= tolerance
            && abs(candidate.height - baseline.height) <= tolerance
    }

    func toolbarFrames(
        for labels: [String],
        in toolbarElements: [AXUIElement]
    ) throws -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        for label in labels {
            guard let control = toolbarControl(in: toolbarElements, label: label),
                  let frame = elementFrame(control),
                  frame.width > 1,
                  frame.height > 1 else {
                throw JourneyError.missing(
                    "The native Reader toolbar lost \(label) or its AX frame."
                )
            }
            frames[label] = frame
        }
        return frames
    }

    let baselineToolbar = try refreshNativeToolbar()
    let baselineToolbarElements = elements(in: baselineToolbar, limit: 300)
    let baselineToolbarElementCount = baselineToolbarElements.count
    let baselineToolbarFrames = try toolbarFrames(
        for: readerPlaneLabels,
        in: baselineToolbarElements
    )
    for (label, frame) in baselineToolbarFrames {
        guard frame.minX >= readerFrame.minX - paneAlignmentTolerance,
              frame.maxX <= readerFrame.maxX + paneAlignmentTolerance,
              frame.maxX <= inspectorFrame.minX + paneAlignmentTolerance else {
            throw JourneyError.missing(
                "Reader toolbar control \(label) escaped the Reader plane: "
                    + "control=\(frame), Reader=\(readerFrame), Inspector=\(inspectorFrame)."
            )
        }
    }
    guard let inspectorToggleFrame = baselineToolbarFrames["Hide Inspector"],
          inspectorToggleFrame.midX > readerFrame.midX,
          inspectorToggleFrame.maxX <= inspectorFrame.minX + paneAlignmentTolerance else {
        throw JourneyError.missing(
            "The Inspector toggle was not right-aligned inside the Reader plane."
        )
    }
    let toolbarPlaneContainment =
        "all 11 Reader controls, including Inspector toggle, remained between Reader dividers 1 and 2"

    guard let initialModeGroup = inspectorModeGroup(in: contentWindow),
          let modeGroupFrame = elementFrame(initialModeGroup),
          let toolbarModeGroup = inspectorModeGroup(in: baselineToolbar),
          CFEqual(initialModeGroup, toolbarModeGroup),
          modeGroupFrame.minX >= inspectorFrame.minX - paneAlignmentTolerance,
          modeGroupFrame.maxX <= inspectorFrame.maxX + paneAlignmentTolerance,
          abs(modeGroupFrame.midY - inspectorToggleFrame.midY) <= 4 else {
        throw JourneyError.missing(
            "The Inspector mode selector was not aligned in the Inspector's native toolbar plane."
        )
    }
    let inspectorAccessoryAlignment =
        "Inspector mode selector stayed within the Inspector plane and aligned with the native window toolbar"
    let baselineInspectorToggleTrailingInset = readerFrame.maxX - inspectorToggleFrame.maxX

    func verifyInspectorToggleAlignment(_ label: String) throws {
        let toolbar = try refreshNativeToolbar()
        let toolbarElements = elements(in: toolbar, limit: 300)
        guard let currentReader = readerPane(in: contentWindow, articleTitle: articleTitle),
              let currentReaderFrame = elementFrame(currentReader),
              let toggle = toolbarControl(in: toolbarElements, label: label),
              let toggleFrame = elementFrame(toggle),
              toggleFrame.minX >= currentReaderFrame.minX - paneAlignmentTolerance,
              toggleFrame.maxX <= currentReaderFrame.maxX + paneAlignmentTolerance,
              abs(
                  (currentReaderFrame.maxX - toggleFrame.maxX)
                      - baselineInspectorToggleTrailingInset
              ) <= 2 else {
            throw JourneyError.missing(
                "The \(label) control left a toolbar gap or escaped the live Reader plane: "
                    + "Reader=\(String(describing: readerPane(in: contentWindow, articleTitle: articleTitle).flatMap(elementFrame))), "
                    + "control=\(String(describing: toolbarControl(in: toolbarElements, label: label).flatMap(elementFrame))), "
                    + "expected trailing inset=\(baselineInspectorToggleTrailingInset)."
            )
        }
    }

    func framesMatchBaseline(_ current: [String: CGRect], tolerance: CGFloat = 1) -> Bool {
        guard current.count == baselineToolbarFrames.count else { return false }
        return baselineToolbarFrames.allSatisfy { label, baseline in
            guard let candidate = current[label] else { return false }
            return abs(candidate.minX - baseline.minX) <= tolerance
                && abs(candidate.minY - baseline.minY) <= tolerance
                && abs(candidate.width - baseline.width) <= tolerance
                && abs(candidate.height - baseline.height) <= tolerance
        }
    }

    trace("native window toolbar contract verified")
    traceRuntimeDiagnostics("native window toolbar contract")

    func inspectorButton(_ label: String) throws -> AXUIElement {
        let toolbar = try refreshNativeToolbar()
        guard let group = inspectorModeGroup(in: toolbar) else {
            throw JourneyError.missing("Inspector mode container was not accessible.")
        }
        guard let result = inspectorModeButtons(in: group).first(where: { candidate in
            accessibilityLabels(of: candidate).contains {
                    matchesAXLabel($0, expected: label)
                }
        }) else {
            throw JourneyError.missing("Inspector mode omitted \(label).")
        }
        return result
    }

    var toolbarModeSwitchSampleCount = 0
    func verifyToolbarStabilityDuringInspectorTransition(untilSelected label: String) throws {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let minimumEnd = startedAt + 0.30
        let deadline = startedAt + 4.0
        var transitionSampleCount = 0

        while true {
            let toolbar = try refreshNativeToolbar()
            let toolbarElements = elements(in: toolbar, limit: 300)
            guard CFEqual(toolbar, baselineToolbar) else {
                throw JourneyError.missing(
                    "Inspector mode switching replaced the native toolbar."
                )
            }
            guard toolbarElements.count == baselineToolbarElementCount else {
                let baselineDescriptors = baselineToolbarElements.map {
                    let role = stringAttribute(kAXRoleAttribute as CFString, from: $0)
                    return ([role] + accessibilityLabels(of: $0))
                        .filter { !$0.isEmpty }
                        .joined(separator: "|")
                }
                let currentDescriptors = toolbarElements.map {
                    let role = stringAttribute(kAXRoleAttribute as CFString, from: $0)
                    return ([role] + accessibilityLabels(of: $0))
                        .filter { !$0.isEmpty }
                        .joined(separator: "|")
                }
                let removed = baselineDescriptors.filter {
                    !currentDescriptors.contains($0)
                }
                let added = currentDescriptors.filter {
                    !baselineDescriptors.contains($0)
                }
                throw JourneyError.missing(
                    "Inspector mode switching changed the native toolbar AX tree "
                        + "from \(baselineToolbarElementCount) to \(toolbarElements.count) elements; "
                        + "removed=\(removed); added=\(added)."
                )
            }
            let frames = try toolbarFrames(
                for: readerPlaneLabels,
                in: toolbarElements
            )
            guard framesMatchBaseline(frames) else {
                throw JourneyError.missing(
                    "Reader toolbar controls moved during an Inspector mode transition."
                )
            }

            guard let currentModeGroup = inspectorModeGroup(in: toolbar),
                  CFEqual(currentModeGroup, toolbarModeGroup),
                  let currentModeGroupFrame = elementFrame(currentModeGroup),
                  frameMatches(currentModeGroupFrame, modeGroupFrame) else {
                throw JourneyError.missing(
                    "Inspector mode switching replaced or moved the native tab group."
                )
            }
            let modeButtons = inspectorModeButtons(in: currentModeGroup)
            let selectedModeButtons = modeButtons.filter(isSelected)
            guard modeButtons.count == 3, selectedModeButtons.count == 1 else {
                throw JourneyError.missing(
                    "Inspector mode switching did not preserve exactly one selected native tab."
                )
            }

            transitionSampleCount += 1
            toolbarModeSwitchSampleCount += 1
            let now = CFAbsoluteTimeGetCurrent()
            let selectionSettled = accessibilityLabels(of: selectedModeButtons[0]).contains {
                matchesAXLabel($0, expected: label)
            }
            if selectionSettled, now >= minimumEnd, transitionSampleCount >= 5 {
                return
            }
            guard now < deadline else {
                throw JourneyError.missing(
                    "Inspector mode did not settle on \(label) while toolbar stability was sampled."
                )
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    func selectInspectorMode(_ label: String) throws {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let control = try inspectorButton(label)
        try press(control, label: label)
        try verifyToolbarStabilityDuringInspectorTransition(untilSelected: label)
        traceRuntimeDiagnostics("selected \(label)")
        trace("\(label) selected in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startedAt))s")
        settleAccessibility(for: 0.2)
    }

    func currentInspectorLabels() -> [String] {
        guard let inspector = inspectorPane(in: contentWindow) else { return [] }
        var seen = Set<String>()
        return labels(in: inspector)
            .filter { seen.insert($0).inserted }
    }

    var inspectorStates: [String: [String]] = [:]
    let initialLabels = currentInspectorLabels()
    guard initialLabels.contains("Metadata"), initialLabels.contains("Contents") else {
        throw JourneyError.missing("Info mode omitted Metadata or Contents.")
    }
    inspectorStates["Info"] = ["Selected", "Metadata", "Contents"]
    trace("Info verified")

    try selectInspectorMode("Notes")
    guard wait(condition: { currentInspectorLabels().contains("No Highlights Yet") }) else {
        throw JourneyError.missing("Notes mode did not expose its empty-highlight state.")
    }
    guard isSelected(try inspectorButton("Notes")) else {
        throw JourneyError.missing("Notes mode did not expose its selected accessibility value.")
    }
    inspectorStates["Notes"] = ["Selected", "No Highlights Yet"]
    trace("Notes verified")

    try selectInspectorMode("References")
    var referenceState = ""
    guard wait(condition: {
        let labels = currentInspectorLabels()
        if labels.contains("No References Found") {
            referenceState = "No References Found"
            return true
        }
        if labels.contains(where: { matchesAXLabel($0, expected: "Export") }) {
            referenceState = "Populated reference list"
            return true
        }
        return false
    }) else {
        throw JourneyError.missing("References mode exposed neither its empty state nor populated export controls.")
    }
    guard isSelected(try inspectorButton("References")) else {
        throw JourneyError.missing("References mode did not expose its selected accessibility value.")
    }
    inspectorStates["References"] = ["Selected", referenceState]
    trace("References verified")

    try selectInspectorMode("Info")
    guard wait(condition: { currentInspectorLabels().contains("Metadata") }) else {
        throw JourneyError.missing("Info mode did not restore Metadata.")
    }

    // Rapidly switching Inspector modes previously exposed an intermittent
    // failure. Resolve the stable native toolbar tab group after each content
    // change so the journey never relies on a stale accessibility element.
    for cycle in 1...12 {
        try selectInspectorMode("Notes")
        trace("stress cycle \(cycle): Notes")
        try selectInspectorMode("References")
        trace("stress cycle \(cycle): References")
        try selectInspectorMode("Info")
        trace("stress cycle \(cycle): Info")
    }
    settleAccessibility(for: 0.4)
    guard isSelected(try inspectorButton("Info")), currentInspectorLabels().contains("Metadata") else {
        throw JourneyError.missing("Inspector mode stress cycle did not finish in a stable Info state.")
    }
    trace("inspector stress cycle verified")
    traceRuntimeDiagnostics("inspector stress cycle")
    let toolbarModeSwitchStability =
        "\(toolbarModeSwitchSampleCount) live samples preserved toolbar identity, item count, and Reader control frames"

    // Exercise the standard Inspector responder-chain action against the fourth
    // semantic AppKit split item, refreshing both toolbar and pane AX state.
    for cycle in 1...6 {
        let hideInspector = try inspectorToggleButton("Hide Inspector")
        try press(hideInspector, label: "Hide Inspector")
        guard wait(timeout: 4, condition: {
            guard let toolbar = try? refreshNativeToolbar(),
                  let workspace = workspaceSplitGroup(in: contentWindow) else { return false }
            return inspectorModeGroup(in: toolbar) == nil
                && visibleWorkspacePaneGroups(in: workspace).count == 3
                && (try? inspectorToggleButton("Show Inspector")) != nil
        }) else {
            throw JourneyError.missing("Inspector visibility cycle \(cycle) did not hide the native inspector.")
        }
        try verifyInspectorToggleAlignment("Show Inspector")

        let showInspector = try inspectorToggleButton("Show Inspector")
        try press(showInspector, label: "Show Inspector")
        guard wait(timeout: 4, condition: {
            guard let toolbar = try? refreshNativeToolbar(),
                  let workspace = workspaceSplitGroup(in: contentWindow) else { return false }
            return inspectorModeGroup(in: toolbar).map {
                isEnabled($0)
                    && elementFrame($0).map { frameMatches($0, modeGroupFrame) } == true
            } == true
                && visibleWorkspacePaneGroups(in: workspace).count == 4
                && (try? inspectorToggleButton("Hide Inspector")) != nil
                && readerWebAreaIdentityIsStable()
        }) else {
            let currentToolbar = try? refreshNativeToolbar()
            let currentModeGroup = currentToolbar.flatMap(inspectorModeGroup)
            let currentWorkspace = workspaceSplitGroup(in: contentWindow)
            let hasHideInspector = (try? inspectorToggleButton("Hide Inspector")) != nil
            let hasShowInspector = (try? inspectorToggleButton("Show Inspector")) != nil
            throw JourneyError.missing(
                "Inspector visibility cycle \(cycle) did not restore the native inspector: "
                    + "mode group present=\(currentModeGroup != nil), "
                    + "same group=\(currentModeGroup.map { CFEqual($0, toolbarModeGroup) } ?? false), "
                    + "enabled=\(currentModeGroup.map(isEnabled) ?? false), "
                    + "frame=\(String(describing: currentModeGroup.flatMap(elementFrame))), "
                    + "expected frame=\(modeGroupFrame), "
                    + "pane count=\(currentWorkspace.map { visibleWorkspacePaneGroups(in: $0).count } ?? -1), "
                    + "Hide Inspector present=\(hasHideInspector), "
                    + "Show Inspector present=\(hasShowInspector), "
                    + "Reader identity stable=\(readerWebAreaIdentityIsStable())."
            )
        }
        try verifyInspectorToggleAlignment("Hide Inspector")
        settleAccessibility(for: 0.15)
    }

    let interruptedHide = try inspectorToggleButton("Hide Inspector")
    try press(interruptedHide, label: "Hide Inspector")
    guard wait(timeout: 1, condition: {
        guard let workspace = workspaceSplitGroup(in: contentWindow) else { return false }
        return (try? inspectorToggleButton("Show Inspector")) != nil
            && visibleWorkspacePaneGroups(in: workspace).count == 3
    }) else {
        throw JourneyError.missing("Interrupted Inspector cycle never entered its native hidden state.")
    }
    try press(try inspectorToggleButton("Show Inspector"), label: "Show Inspector")
    guard wait(timeout: 4, condition: {
        guard let toolbar = try? refreshNativeToolbar(),
              let group = inspectorModeGroup(in: toolbar),
              let workspace = workspaceSplitGroup(in: contentWindow) else { return false }
        return isEnabled(group)
            && elementFrame(group).map { frameMatches($0, modeGroupFrame) } == true
            && visibleWorkspacePaneGroups(in: workspace).count == 4
            && (try? inspectorToggleButton("Hide Inspector")) != nil
            && readerWebAreaIdentityIsStable()
    }) else {
        throw JourneyError.missing("Interrupted Inspector cycle did not reconcile to one visible native plane.")
    }
    try verifyInspectorToggleAlignment("Hide Inspector")
    trace("interrupted native inspector transition reconciled")
    trace("native inspector visibility stress cycle verified")
    traceRuntimeDiagnostics("inspector visibility stress cycle")

    let visibilityMatrix = [
        PaneVisibilityState(lists: true, directory: true, inspector: true),
        PaneVisibilityState(lists: false, directory: true, inspector: true),
        PaneVisibilityState(lists: false, directory: false, inspector: true),
        PaneVisibilityState(lists: false, directory: false, inspector: false),
        PaneVisibilityState(lists: true, directory: false, inspector: false),
        PaneVisibilityState(lists: true, directory: false, inspector: true),
        PaneVisibilityState(lists: true, directory: true, inspector: false),
        PaneVisibilityState(lists: true, directory: true, inspector: true)
    ]
    for (index, state) in visibilityMatrix.enumerated() {
        try movePanes(to: state, context: "Visibility matrix state \(index + 1)")
    }

    for cycle in 1...20 {
        let hiddenState = cycle.isMultiple(of: 2)
            ? PaneVisibilityState(lists: true, directory: false, inspector: true)
            : PaneVisibilityState(lists: false, directory: true, inspector: true)
        try movePanes(to: hiddenState, context: "Independent navigation pane cycle \(cycle) hide")
        try movePanes(
            to: PaneVisibilityState(lists: true, directory: true, inspector: true),
            context: "Independent navigation pane cycle \(cycle) restore"
        )
    }
    guard readerWebAreaIdentityIsStable() else {
        throw JourneyError.missing("The Reader Web area changed identity during auxiliary-pane transitions.")
    }
    trace("all eight pane visibility states and 20 independent navigation-pane cycles verified")
    traceRuntimeDiagnostics("auxiliary pane visibility matrix")

    let findButton = try toolbarButton("Find in Page")
    try press(findButton, label: "Find in Page")
    settleAccessibility(for: 0.4)
    guard wait(condition: {
        return matchingElements(
            in: contentWindow,
            role: kAXTextFieldRole as String,
            label: "Find in page"
        ).count == 1 &&
            button(in: contentWindow, label: "Done") != nil
    }) else {
        if traceEnabled {
            let summary = elements(in: contentWindow, limit: 2_000).compactMap { element -> String? in
                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                guard role == kAXTextFieldRole as String || role == kAXButtonRole as String else {
                    return nil
                }
                return "\(role)|\(accessibilityLabels(of: element).joined(separator: ","))"
            }
            trace("find AX: \(summary)")
        }
        throw JourneyError.missing("Reader did not expose exactly one Find field and its Done action.")
    }
    let requiredFindActions = ["Previous", "Next", "Done"]
    let missingFindActions = requiredFindActions.filter { button(in: contentWindow, label: $0) == nil }
    guard missingFindActions.isEmpty else {
        throw JourneyError.missing("Find bar omitted actions: \(missingFindActions.joined(separator: ", "))")
    }
    let findBar = ["Exactly one Find in page field"] + requiredFindActions
    guard let doneButton = button(in: contentWindow, label: "Done") else {
        throw JourneyError.missing("Find bar omitted Done.")
    }
    try press(doneButton, label: "Done")
    settleAccessibility(for: 0.35)
    guard wait(condition: {
        element(in: contentWindow, role: kAXTextFieldRole as String, label: "Find in page") == nil
    }) else {
        throw JourneyError.missing("Find bar did not dismiss.")
    }
    trace("single Find UI verified")
    traceRuntimeDiagnostics("Find UI")

    try movePanes(
        to: PaneVisibilityState(lists: false, directory: false, inspector: false),
        context: "Prepare narrow window"
    )
    traceRuntimeDiagnostics("auxiliary panes hidden before narrow resize")

    let narrowWidth: CGFloat = 900
    try setWindowSize(CGSize(width: narrowWidth, height: 780), for: contentWindow)
    guard wait(condition: {
        windowSize(contentWindow).map { abs($0.width - narrowWidth) < 2 } == true
    }) else {
        throw JourneyError.missing("The window did not reach the narrow pane-restore test width.")
    }

    guard nativeWindowToolbar(in: contentWindow) != nil,
          readerPane(in: contentWindow, articleTitle: articleTitle) != nil else {
        throw JourneyError.missing("The native toolbar or Reader detail disappeared at 900 points.")
    }

    try movePanes(
        to: PaneVisibilityState(lists: false, directory: true, inspector: false),
        context: "Narrow List Contents restore"
    )
    try movePanes(
        to: PaneVisibilityState(lists: false, directory: true, inspector: true),
        context: "Narrow Inspector restore"
    )
    guard wait(condition: {
        guard let toolbar = try? refreshNativeToolbar() else { return false }
        return inspectorModeGroup(in: toolbar).map(isEnabled) == true
            && (try? toolbarButton("Hide List Contents")) != nil
            && (try? toolbarButton("Show Lists")) != nil
            && containsLabel("Tab History", in: contentWindow)
    }) else {
        throw JourneyError.missing("The narrow window did not restore List Contents and Inspector with Lists hidden.")
    }
    guard let narrowInspector = inspectorPane(in: contentWindow),
          let narrowInspectorFrame = elementFrame(narrowInspector),
          let narrowToolbar = try? refreshNativeToolbar(),
          let narrowModeGroup = inspectorModeGroup(in: narrowToolbar),
          let narrowModeGroupFrame = elementFrame(narrowModeGroup),
          narrowModeGroupFrame.minX >= narrowInspectorFrame.minX - paneAlignmentTolerance,
          narrowModeGroupFrame.maxX <= narrowInspectorFrame.maxX + paneAlignmentTolerance else {
        throw JourneyError.missing(
            "The native Inspector tab group overflowed its pane at the supported narrow width."
        )
    }
    for _ in 0..<8 {
        guard let restoredWindowSize = windowSize(contentWindow),
              abs(restoredWindowSize.width - narrowWidth) < 2 else {
            throw JourneyError.missing("Restoring panes resized the whole window instead of redistributing the native split.")
        }
        let restoredReader = readerPane(in: contentWindow, articleTitle: articleTitle)
        let restoredReaderSize = restoredReader.flatMap(elementSize)
        let restoredReaderContainsArticle = restoredReader.map {
            containsLabel(articleTitle, in: $0)
        } ?? false
        guard restoredReader != nil,
              let restoredReaderSize,
              restoredReaderSize.width >= 300,
              restoredReaderContainsArticle,
              readerWebAreaIdentityIsStable() else {
            let workspacePaneSizes = nativeSplitPaneSizes(in: contentWindow)
            let readerGeometry = restoredReaderSize.map {
                "\(Int($0.width))x\(Int($0.height))"
            } ?? "unavailable"
            trace(
                "narrow restore geometry: window=\(Int(restoredWindowSize.width))x\(Int(restoredWindowSize.height)), "
                    + "reader=\(readerGeometry), "
                    + "article=\(restoredReaderContainsArticle), workspace panes=[\(workspacePaneSizes)]"
            )
            throw JourneyError.missing("Restoring both panes left the reader collapsed or lost its article content.")
        }
        Thread.sleep(forTimeInterval: 0.12)
    }
    traceRuntimeDiagnostics("inspector restore")
    trace("narrow List Contents and Inspector restore verified with Lists intentionally hidden")

    let result = JourneyResult(
        pid: pid,
        articleTitle: articleTitle,
        readerControls: reportedReaderControls,
        readStateControlCycle: readStateControlCycle,
        inspectorStates: inspectorStates,
        findBar: findBar,
        workspaceStructure: workspaceStructure,
        toolbarPlaneContainment: toolbarPlaneContainment,
        toolbarModeSwitchStability: toolbarModeSwitchStability
            + "; tab-group identity/frame and exactly-one-selected semantics stayed stable",
        toolbarModeSwitchSampleCount: toolbarModeSwitchSampleCount,
        inspectorAccessoryAlignment: inspectorAccessoryAlignment,
        auxiliaryPaneMatrix: "all eight visibility states plus 20 independent Lists/List Contents hide-restore cycles; Reader Web area identity preserved",
        inspectorToggleCycle: "native inspector hidden/restored through six rapid cycles plus one interrupted transition without ghost toolbar geometry",
        narrowPaneRestoreCycle: "900-point window preserved with Lists hidden while List Contents and Inspector restored around a usable Reader; native tabs remained within the Inspector"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_reader_inspector_journey: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
