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
        guard hasRole(candidate, kAXRadioGroupRole as String) else { return false }
        let candidateLabels = Set(elements(in: candidate, limit: 30).flatMap(accessibilityLabels))
        return candidateLabels.isSuperset(of: ["Info", "Notes", "References"])
    }
}

private func inspectorPane(in window: AXUIElement) -> AXUIElement? {
    guard let modeGroup = inspectorModeGroup(in: window) else { return nil }
    let contentMarkers = [
        "Metadata", "Contents", "No Highlights Yet", "No References Found", "Export"
    ]
    var candidate = parent(of: modeGroup)
    for _ in 0..<8 {
        guard let current = candidate else { break }
        if hasRole(current, kAXGroupRole as String) {
            let candidateLabels = labels(in: current)
            if candidateLabels.contains(where: { label in
                contentMarkers.contains { matchesAXLabel(label, expected: $0) }
            }) {
                return current
            }
        }
        candidate = parent(of: current)
    }
    return parent(of: modeGroup)
}

private func readerPane(in window: AXUIElement, articleTitle: String) -> AXUIElement? {
    guard let newTabButton = button(in: window, label: "New Tab") else { return nil }
    var candidate = parent(of: newTabButton)
    for _ in 0..<12 {
        guard let current = candidate else { break }
        let role = stringAttribute(kAXRoleAttribute as CFString, from: current)
        if (role == kAXGroupRole as String || role == kAXSplitGroupRole as String),
           containsLabel(articleTitle, in: current) {
            return current
        }
        candidate = parent(of: current)
    }
    return nil
}

private func nativeSplitPaneSizes(in window: AXUIElement) -> String {
    let sizes = elements(in: window, limit: 1_500)
        .filter { hasRole($0, kAXSplitGroupRole as String) }
        .flatMap(directChildren)
        .filter { hasRole($0, kAXGroupRole as String) }
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
        guard let reader = readerPane(in: contentWindow, articleTitle: articleTitle) else { return false }
        return containsLabel(articleTitle, in: reader)
    }) else {
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
        guard let result = button(in: toolbar, label: label) else {
            throw JourneyError.missing("The native window toolbar omitted \(label).")
        }
        return result
    }

    var modeGroup = inspectorModeGroup(in: contentWindow)
    let listContentsControlReport: String
    let initialToolbar = try refreshNativeToolbar()
    if button(in: initialToolbar, label: "Hide List Contents") != nil {
        listContentsControlReport = "Hide List Contents"
    } else if button(in: initialToolbar, label: "Show List Contents") != nil {
        listContentsControlReport = "Show List Contents"
    } else {
        throw JourneyError.missing("The native window toolbar omitted its List Contents control.")
    }
    let listsControlReport: String
    if button(in: initialToolbar, label: "Hide Sidebar") != nil {
        listsControlReport = "Hide Sidebar"
    } else if button(in: initialToolbar, label: "Show Sidebar") != nil {
        listsControlReport = "Show Sidebar"
    } else {
        throw JourneyError.missing("The native window toolbar omitted its Lists control.")
    }
    if button(in: initialToolbar, label: "Hide Lists") != nil
        || button(in: initialToolbar, label: "Show Lists") != nil {
        throw JourneyError.missing("A duplicate custom Lists control competed with the native sidebar item.")
    }
    guard element(
        in: contentWindow,
        role: kAXStaticTextRole as String,
        label: "Tab History"
    ) != nil else {
        throw JourneyError.missing("The seeded List Contents pane was not initially visible.")
    }
    if modeGroup == nil {
        guard wait(condition: {
            guard let toolbar = try? refreshNativeToolbar(),
                  let showInspector = button(in: toolbar, label: "Show Inspector") else { return false }
            return isEnabled(showInspector)
        }), let toolbar = try? refreshNativeToolbar(),
            let showInspector = button(in: toolbar, label: "Show Inspector") else {
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
        throw JourneyError.missing("The native inspector did not become accessible.")
    }
    traceRuntimeDiagnostics("inspector readiness")
    trace("native window toolbar, NavigationSplitView Reader, and inspector ready")

    let expectedReaderControls = [
        "Back", "Forward", "Search Wikipedia", "Save Article",
        "Mark as Read", "Find in Page", "Reader Style",
        "Page Views", "Open in Browser", "Share", "Hide Inspector"
    ]
    let contractToolbar = try refreshNativeToolbar()
    let missingToolbarControls = expectedReaderControls.filter {
        button(in: contractToolbar, label: $0) == nil
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

    guard labeledElement(in: contentWindow, label: "More Reader Actions") == nil else {
        throw JourneyError.missing("The retired custom More Reader Actions control is still exposed.")
    }

    let reportedReaderControls = [listsControlReport, listContentsControlReport] + expectedReaderControls
    trace("native window toolbar contract verified")
    traceRuntimeDiagnostics("native window toolbar contract")

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

    // The inspector is a native scene modifier now. Exercise its actual toolbar
    // visibility path repeatedly, refreshing both the toolbar item and inspector
    // AX subtree after every structural transition.
    for cycle in 1...6 {
        let hideInspector = try toolbarButton("Hide Inspector")
        try press(hideInspector, label: "Hide Inspector")
        guard wait(timeout: 4, condition: {
            inspectorModeGroup(in: contentWindow) == nil
                && (try? toolbarButton("Show Inspector")) != nil
        }) else {
            throw JourneyError.missing("Inspector visibility cycle \(cycle) did not hide the native inspector.")
        }

        let showInspector = try toolbarButton("Show Inspector")
        try press(showInspector, label: "Show Inspector")
        guard wait(timeout: 4, condition: {
            inspectorModeGroup(in: contentWindow) != nil
                && (try? toolbarButton("Hide Inspector")) != nil
        }) else {
            throw JourneyError.missing("Inspector visibility cycle \(cycle) did not restore the native inspector.")
        }
        settleAccessibility(for: 0.15)
    }
    trace("native inspector visibility stress cycle verified")
    traceRuntimeDiagnostics("inspector visibility stress cycle")

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

    let hideInspector = try toolbarButton("Hide Inspector")
    try press(hideInspector, label: "Hide Inspector")
    settleAccessibility(for: 0.45)
    guard wait(condition: { inspectorModeGroup(in: contentWindow) == nil }) else {
        throw JourneyError.missing("Hide Inspector did not remove the native inspector.")
    }
    traceRuntimeDiagnostics("inspector hide")

    let hideListContents = try toolbarButton("Hide List Contents")
    try press(hideListContents, label: "Hide List Contents")
    settleAccessibility(for: 0.45)
    guard wait(condition: {
        (try? toolbarButton("Show List Contents")) != nil
            && element(
                in: contentWindow,
                role: kAXStaticTextRole as String,
                label: "Tab History"
            ) == nil
            && element(
                in: contentWindow,
                role: kAXStaticTextRole as String,
                label: "Explore"
            ) != nil
    }) else {
        throw JourneyError.missing(
            "Hide List Contents did not collapse only the directory pane while preserving Lists."
        )
    }

    let hideSidebar = try toolbarButton("Hide Sidebar")
    try press(hideSidebar, label: "Hide Sidebar")
    settleAccessibility(for: 0.45)
    guard wait(condition: {
        (try? toolbarButton("Show Sidebar")) != nil
            && (try? toolbarButton("Show List Contents")) != nil
            && element(
                in: contentWindow,
                role: kAXStaticTextRole as String,
                label: "Explore"
            ) == nil
            && element(
                in: contentWindow,
                role: kAXStaticTextRole as String,
                label: "Tab History"
            ) == nil
    }) else {
        throw JourneyError.missing("The native Sidebar control was not independent from List Contents.")
    }

    let showSidebar = try toolbarButton("Show Sidebar")
    try press(showSidebar, label: "Show Sidebar")
    settleAccessibility(for: 0.45)
    guard wait(condition: {
        (try? toolbarButton("Hide Sidebar")) != nil
            && (try? toolbarButton("Show List Contents")) != nil
            && element(
                in: contentWindow,
                role: kAXStaticTextRole as String,
                label: "Explore"
            ) != nil
            && element(
                in: contentWindow,
                role: kAXStaticTextRole as String,
                label: "Tab History"
            ) == nil
    }) else {
        throw JourneyError.missing("Restoring Lists also restored List Contents unexpectedly.")
    }

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

    let showListContents = try toolbarButton("Show List Contents")
    try press(showListContents, label: "Show List Contents")
    settleAccessibility(for: 0.3)
    let showInspector = try toolbarButton("Show Inspector")
    try press(showInspector, label: "Show Inspector")
    settleAccessibility(for: 0.5)
    guard wait(condition: {
        inspectorModeGroup(in: contentWindow) != nil
            && (try? toolbarButton("Hide List Contents")) != nil
            && element(
                in: contentWindow,
                role: kAXStaticTextRole as String,
                label: "Tab History"
            ) != nil
    }) else {
        throw JourneyError.missing("The narrow window did not restore both auxiliary panes.")
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
              restoredReaderContainsArticle else {
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
    trace("narrow inspector and list-contents restore verified without a window jump")

    let result = JourneyResult(
        pid: pid,
        articleTitle: articleTitle,
        readerControls: reportedReaderControls,
        inspectorStates: inspectorStates,
        findBar: findBar,
        inspectorToggleCycle: "native inspector hidden and restored through six rapid cycles",
        narrowPaneRestoreCycle: "900-point window preserved while native List Contents and Inspector restored around a usable Reader"
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    print()
} catch {
    fputs("ax_reader_inspector_journey: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
