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
    let inspectorStates: [String: [String]]
    let findBar: [String]
    let inspectorToggleCycle: String
    let narrowPaneRestoreCycle: String
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

private func isMenuControl(_ element: AXUIElement) -> Bool {
    let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
    return role == kAXMenuButtonRole as String || role == kAXPopUpButtonRole as String
}

private func workspaceSplitGroup(in window: AXUIElement) -> AXUIElement? {
    guard let shellRoot = directChildren(of: window).first(where: { hasRole($0, kAXGroupRole as String) }),
          let outerSplit = directChildren(of: shellRoot).first(where: { hasRole($0, kAXSplitGroupRole as String) }) else {
        return nil
    }

    let rootPaneGroups = directChildren(of: outerSplit).filter {
        hasRole($0, kAXGroupRole as String)
    }
    let rootOwnsInspector = rootPaneGroups.contains { group in
        directChildren(of: group).contains { hasRole($0, kAXRadioGroupRole as String) }
    }
    if rootOwnsInspector || rootPaneGroups.count >= 3 {
        return outerSplit
    }

    guard let detailGroup = rootPaneGroups.last else { return nil }
    return directChildren(of: detailGroup).first { hasRole($0, kAXSplitGroupRole as String) }
}

private func inspectorPane(in window: AXUIElement) -> AXUIElement? {
    guard let workspace = workspaceSplitGroup(in: window) else { return nil }
    return directChildren(of: workspace)
        .filter { hasRole($0, kAXGroupRole as String) }
        .first { group in
            directChildren(of: group).contains { hasRole($0, kAXRadioGroupRole as String) }
        }
}

private func inspectorModeGroup(in window: AXUIElement) -> AXUIElement? {
    guard let inspector = inspectorPane(in: window) else { return nil }
    return directChildren(of: inspector).first { hasRole($0, kAXRadioGroupRole as String) }
}

private func readerPane(in window: AXUIElement) -> AXUIElement? {
    guard let workspace = workspaceSplitGroup(in: window) else { return nil }
    return directChildren(of: workspace)
        .filter { hasRole($0, kAXGroupRole as String) }
        .first { group in
            let descendants = elements(in: group, limit: 500)
            return descendants.contains { hasRole($0, kAXScrollAreaRole as String) }
                && descendants.contains { child in
                    hasRole(child, kAXButtonRole as String)
                        && accessibilityLabels(of: child).contains("New Tab")
                }
        }
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
            stringAttribute(kAXPlaceholderValueAttribute as CFString, from: element)
        ].contains { matchesAXLabel($0, expected: label) }
    }
}

private func labeledElement(in root: AXUIElement, label: String) -> AXUIElement? {
    elements(in: root).first { element in
        [
            stringAttribute(kAXTitleAttribute as CFString, from: element),
            stringAttribute(kAXDescriptionAttribute as CFString, from: element)
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
            stringAttribute(kAXPlaceholderValueAttribute as CFString, from: element)
        ].contains { matchesAXLabel($0, expected: label) }
    }
}

private func button(in application: AXUIElement, label: String) -> AXUIElement? {
    element(in: application, role: kAXButtonRole as String, label: label)
}

private func menuItem(in application: AXUIElement, label: String) -> AXUIElement? {
    if let focusedValue = attributeValue(
        kAXFocusedUIElementAttribute as CFString,
        from: application
    ), CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
        let focusedElement = focusedValue as! AXUIElement
        var candidate: AXUIElement? = focusedElement
        for _ in 0..<8 {
            guard let current = candidate else { break }
            let role = stringAttribute(kAXRoleAttribute as CFString, from: current)
            if role == kAXMenuItemRole as String,
               accessibilityLabels(of: current).contains(where: { matchesAXLabel($0, expected: label) }) {
                return current
            }
            if (role == "AXMenu" || role == kAXMenuBarRole as String),
               let result = element(in: current, role: kAXMenuItemRole as String, label: label) {
                return result
            }
            guard let parentValue = attributeValue(kAXParentAttribute as CFString, from: current),
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            let parent = parentValue as! AXUIElement
            candidate = parent
        }
    }

    // Menus are exposed as immediate application children (or beneath the menu
    // bar). Restrict the fallback to those roots so opening the Reader More menu does
    // not recursively query every SwiftUI hosting view in every application window.
    let applicationChildren = attributeValue(
        kAXChildrenAttribute as CFString,
        from: application
    ) as? [AXUIElement] ?? []
    let menuRoots = applicationChildren.filter { child in
        let role = stringAttribute(kAXRoleAttribute as CFString, from: child)
        return role == "AXMenu" || role == kAXMenuBarRole as String
    }
    return menuRoots.lazy.compactMap {
        element(in: $0, role: kAXMenuItemRole as String, label: label)
    }.first
}

private func postEscape(to pid: pid_t) throws {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) else {
        throw JourneyError.missing("Unable to create a targeted Escape key event.")
    }
    keyDown.postToPid(pid)
    keyUp.postToPid(pid)
}

private func inspectorModeControl(in application: AXUIElement, label: String) -> AXUIElement? {
    button(in: application, label: label) ??
        element(in: application, role: kAXRadioButtonRole as String, label: label)
}

private func isSelected(_ element: AXUIElement) -> Bool {
    ["1", "Selected"].contains(stringAttribute(kAXValueAttribute as CFString, from: element))
}

private func isEnabled(_ element: AXUIElement) -> Bool {
    stringAttribute(kAXEnabledAttribute as CFString, from: element) != "0"
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
        guard let reader = readerPane(in: contentWindow) else { return false }
        return containsLabel(articleTitle, in: reader)
    }) else {
        throw JourneyError.missing("The seeded article did not become accessible in the main window.")
    }
    traceRuntimeDiagnostics("initial window discovery")
    try ensureInspectorTestWidth(for: contentWindow)
    settleAccessibility(for: 0.75)
    traceRuntimeDiagnostics("window resize")

    func refreshReaderChrome() throws -> AXUIElement {
        guard let reader = readerPane(in: contentWindow) else {
            throw JourneyError.missing("The reader-scoped accessory disappeared during the journey.")
        }
        return reader
    }

    var modeGroup = inspectorModeGroup(in: contentWindow)
    let listContentsControlReport: String
    let initialReader = try refreshReaderChrome()
    if button(in: initialReader, label: "Hide List Contents") != nil {
        listContentsControlReport = "Hide List Contents"
    } else if button(in: initialReader, label: "Show List Contents") != nil {
        listContentsControlReport = "Show List Contents"
    } else {
        throw JourneyError.missing("The reader accessory omitted its List Contents control.")
    }
    let listsControlReport: String
    if button(in: initialReader, label: "Hide Lists") != nil {
        listsControlReport = "Hide Lists"
    } else if button(in: initialReader, label: "Show Lists") != nil {
        listsControlReport = "Show Lists"
    } else {
        throw JourneyError.missing("The reader accessory omitted its Lists control.")
    }
    if modeGroup == nil {
        guard wait(condition: {
            guard let reader = try? refreshReaderChrome(),
                  let showInspector = button(in: reader, label: "Show Inspector") else { return false }
            return isEnabled(showInspector)
        }), let reader = try? refreshReaderChrome(),
            let showInspector = button(in: reader, label: "Show Inspector") else {
            throw JourneyError.missing(
                "Show Inspector never became enabled at the wide test size \(String(describing: windowSize(contentWindow)))."
            )
        }
        try press(showInspector, label: "Show Inspector")
        settleAccessibility(for: 0.45)
    }
    guard wait(condition: {
        modeGroup = inspectorModeGroup(in: contentWindow)
        return modeGroup != nil
    }) else {
        throw JourneyError.missing("The split inspector did not become accessible.")
    }
    traceRuntimeDiagnostics("inspector readiness")
    trace("window, reader accessory, and inspector ready")

    let expectedReaderControls = [
        "Back", "Forward", "Search Wikipedia", "Save Article",
        "Mark as Read", "Find in Page", "Reader Style",
        "Page Views", "Open in Browser", "Share", "Hide Inspector"
    ]
    let readerElements = elements(in: try refreshReaderChrome(), limit: 500)
    func readerButton(_ label: String, among candidates: [AXUIElement]) -> AXUIElement? {
        candidates.first { candidate in
            guard stringAttribute(kAXRoleAttribute as CFString, from: candidate) == kAXButtonRole as String else {
                return false
            }
            return accessibilityLabels(of: candidate).contains {
                matchesAXLabel($0, expected: label)
            }
        }
    }
    let visibleReaderControls = expectedReaderControls.filter {
        readerButton($0, among: readerElements) != nil
    }
    var menuReaderControls: [String] = []
    let missingVisibleControls = expectedReaderControls.filter { !visibleReaderControls.contains($0) }
    if !missingVisibleControls.isEmpty,
       let currentReader = try? refreshReaderChrome() {
        let moreButtons = elements(in: currentReader, limit: 500).filter {
            isMenuControl($0)
                && accessibilityLabels(of: $0).contains { matchesAXLabel($0, expected: "More Reader Actions") }
        }
        for moreButton in moreButtons {
            try press(moreButton, label: "More Reader Actions")
            settleAccessibility(for: 0.2)
            _ = wait(timeout: 2, condition: {
                missingVisibleControls.contains { menuItem(in: application, label: $0) != nil }
            })
            menuReaderControls.append(contentsOf: missingVisibleControls.filter {
                menuItem(in: application, label: $0) != nil
            })
            try postEscape(to: pid)
            if Set(menuReaderControls).isSuperset(of: missingVisibleControls) { break }
        }
    }
    let availableReaderControls = Array(Set(visibleReaderControls + menuReaderControls))
    guard availableReaderControls.count == expectedReaderControls.count else {
        let missing = expectedReaderControls.filter { !availableReaderControls.contains($0) }
        if traceEnabled,
           let currentReader = try? refreshReaderChrome() {
            let summary = elements(in: currentReader, limit: 500).map { element in
                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                let title = stringAttribute(kAXTitleAttribute as CFString, from: element)
                let description = stringAttribute(kAXDescriptionAttribute as CFString, from: element)
                return "\(role)|\(title)|\(description)"
            }
            trace("reader accessory AX: \(summary)")
        }
        throw JourneyError.missing("Reader accessory omitted accessible controls: \(missing.joined(separator: ", "))")
    }

    let reportedReaderControls = [listsControlReport, listContentsControlReport] + expectedReaderControls.map { label in
        menuReaderControls.contains(label) ? "\(label) (More menu)" : label
    }
    trace("reader accessory contract verified")
    traceRuntimeDiagnostics("reader accessory contract")

    func readerAction(_ label: String) throws -> AXUIElement {
        let currentReader = try refreshReaderChrome()
        let readerDescendants = elements(in: currentReader, limit: 500)
        if let visibleButton = readerButton(label, among: readerDescendants) {
            return visibleButton
        }
        for moreButton in readerDescendants.filter({
            isMenuControl($0)
                && accessibilityLabels(of: $0).contains { matchesAXLabel($0, expected: "More Reader Actions") }
        }) {
            try press(moreButton, label: "More Reader Actions")
            settleAccessibility(for: 0.2)
            if wait(timeout: 2, condition: { menuItem(in: application, label: label) != nil }),
               let item = menuItem(in: application, label: label) {
                return item
            }
            try postEscape(to: pid)
        }
        throw JourneyError.missing("Reader controls and More menu omitted \(label).")
    }

    func inspectorButton(_ label: String) throws -> AXUIElement {
        guard let group = inspectorModeGroup(in: contentWindow) else {
            throw JourneyError.missing("Inspector mode container was not accessible.")
        }
        guard let result = elements(in: group, limit: 20).first(where: { candidate in
            hasRole(candidate, kAXRadioButtonRole as String)
                && accessibilityLabels(of: candidate).contains {
                    matchesAXLabel($0, expected: label)
                }
        }) else {
            throw JourneyError.missing("Inspector mode omitted \(label).")
        }
        return result
    }

    func selectInspectorMode(_ label: String) throws {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let control = try inspectorButton(label)
        try press(control, label: label)
        guard wait(timeout: 4, condition: {
            guard let refreshed = try? inspectorButton(label) else { return false }
            return isSelected(refreshed)
        }) else {
            let values = ["Info", "Notes", "References"].compactMap { mode -> String? in
                guard let control = try? inspectorButton(mode) else { return nil }
                return "\(mode)=\(stringAttribute(kAXValueAttribute as CFString, from: control))"
            }
            trace("mode values after failed \(label) selection: \(values)")
            throw JourneyError.missing("Inspector mode did not settle on \(label).")
        }
        trace("\(label) selected in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startedAt))s")
        settleAccessibility(for: 0.2)
    }

    func currentInspectorLabels() -> [String] {
        guard let inspector = inspectorPane(in: contentWindow) else { return [] }
        var seen = Set<String>()
        return directChildren(of: inspector)
            .filter { !hasRole($0, kAXRadioGroupRole as String) }
            .flatMap(labels)
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

    // Rapidly switching the native segmented picker previously exposed an
    // intermittent inspector failure. Refresh the segmented control after each
    // structural mode change; SwiftUI is allowed to replace the underlying AX
    // element while preserving the visible native control.
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

    let findButton = try readerAction("Find in Page")
    try press(findButton, label: "Find in Page")
    settleAccessibility(for: 0.4)
    guard wait(condition: {
        guard let reader = readerPane(in: contentWindow) else { return false }
        return matchingElements(
            in: reader,
            role: kAXTextFieldRole as String,
            label: "Find in page"
        ).count == 1 &&
            button(in: reader, label: "Done") != nil
    }) else {
        if traceEnabled, let reader = readerPane(in: contentWindow) {
            let summary = elements(in: reader, limit: 700).map { element in
                let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
                return "\(role)|\(accessibilityLabels(of: element).joined(separator: ","))"
            }
            trace("find AX: \(summary)")
        }
        throw JourneyError.missing("Reader did not expose exactly one Find field and its Done action.")
    }
    let requiredFindActions = ["Previous", "Next", "Done"]
    guard let readerWithFindBar = readerPane(in: contentWindow) else {
        throw JourneyError.missing("The reader disappeared while Find was presented.")
    }
    let missingFindActions = requiredFindActions.filter { button(in: readerWithFindBar, label: $0) == nil }
    guard missingFindActions.isEmpty else {
        throw JourneyError.missing("Find bar omitted actions: \(missingFindActions.joined(separator: ", "))")
    }
    let findBar = ["Exactly one Find in page field"] + requiredFindActions
    guard let doneButton = button(in: readerWithFindBar, label: "Done") else {
        throw JourneyError.missing("Find bar omitted Done.")
    }
    try press(doneButton, label: "Done")
    settleAccessibility(for: 0.35)
    guard wait(condition: {
        guard let reader = readerPane(in: contentWindow) else { return false }
        return element(in: reader, role: kAXTextFieldRole as String, label: "Find in page") == nil
    }) else {
        throw JourneyError.missing("Find bar did not dismiss.")
    }
    trace("single Find UI verified")
    traceRuntimeDiagnostics("Find UI")

    let hideInspector = try readerAction("Hide Inspector")
    try press(hideInspector, label: "Hide Inspector")
    settleAccessibility(for: 0.45)
    guard wait(condition: { inspectorModeGroup(in: contentWindow) == nil }) else {
        throw JourneyError.missing("Hide Inspector did not remove the split inspector.")
    }
    traceRuntimeDiagnostics("inspector hide")

    let hideListContents = try readerAction("Hide List Contents")
    try press(hideListContents, label: "Hide List Contents")
    settleAccessibility(for: 0.45)
    guard wait(condition: {
        (try? readerAction("Show List Contents")) != nil
    }) else {
        throw JourneyError.missing("Hide List Contents did not collapse the directory pane.")
    }

    let narrowWidth: CGFloat = 900
    try setWindowSize(CGSize(width: narrowWidth, height: 780), for: contentWindow)
    guard wait(condition: {
        windowSize(contentWindow).map { abs($0.width - narrowWidth) < 2 } == true
    }) else {
        throw JourneyError.missing("The window did not reach the narrow pane-restore test width.")
    }

    guard let narrowReader = try? refreshReaderChrome(),
          let narrowMore = elements(in: narrowReader, limit: 500).first(where: {
              isMenuControl($0)
                  && accessibilityLabels(of: $0).contains {
                      matchesAXLabel($0, expected: "More Reader Actions")
                  }
          }) else {
        throw JourneyError.missing("The 900-point reader did not expose its native More Reader Actions control.")
    }
    try press(narrowMore, label: "More Reader Actions at 900 points")
    guard wait(timeout: 2, condition: {
        menuItem(in: application, label: "Reader Style") != nil
    }), let narrowReaderStyle = menuItem(in: application, label: "Reader Style") else {
        throw JourneyError.missing("The compact More menu omitted Reader Style.")
    }
    try press(narrowReaderStyle, label: "Reader Style from compact More menu")
    guard wait(timeout: 3, condition: {
        containsLabel("Text Styles", in: contentWindow)
    }) else {
        throw JourneyError.missing("The compact More menu did not present Reader Style controls.")
    }
    try postEscape(to: pid)
    settleAccessibility(for: 0.25)
    trace("compact More-menu command path verified")

    let showListContents = try readerAction("Show List Contents")
    try press(showListContents, label: "Show List Contents")
    settleAccessibility(for: 0.3)
    let showInspector = try readerAction("Show Inspector")
    try press(showInspector, label: "Show Inspector")
    settleAccessibility(for: 0.5)
    guard wait(condition: {
        inspectorModeGroup(in: contentWindow) != nil
            && (try? readerAction("Hide List Contents")) != nil
    }) else {
        throw JourneyError.missing("The narrow window did not restore both auxiliary panes.")
    }
    for _ in 0..<8 {
        guard let restoredWindowSize = windowSize(contentWindow),
              abs(restoredWindowSize.width - narrowWidth) < 2 else {
            throw JourneyError.missing("Restoring panes resized the whole window instead of redistributing the native split.")
        }
        let restoredReader = readerPane(in: contentWindow)
        let restoredReaderSize = restoredReader.flatMap(elementSize)
        let restoredReaderContainsArticle = restoredReader.map {
            containsLabel(articleTitle, in: $0)
        } ?? false
        guard restoredReader != nil,
              let restoredReaderSize,
              restoredReaderSize.width >= 300,
              restoredReaderContainsArticle else {
            let workspacePaneSizes = workspaceSplitGroup(in: contentWindow).map {
                directChildren(of: $0)
                    .filter { hasRole($0, kAXGroupRole as String) }
                    .compactMap(elementSize)
                    .map { "\(Int($0.width))x\(Int($0.height))" }
                    .joined(separator: ", ")
            } ?? "unavailable"
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
    trace("narrow inspector and list-contents restore verified without a window jump")

    let result = JourneyResult(
        pid: pid,
        articleTitle: articleTitle,
        readerControls: reportedReaderControls,
        inspectorStates: inspectorStates,
        findBar: findBar,
        inspectorToggleCycle: "reader accessory hidden → restored",
        narrowPaneRestoreCycle: "900-point window preserved; Lists sidebar yielded while List Contents and Inspector restored around a usable reader"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_reader_inspector_journey: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
