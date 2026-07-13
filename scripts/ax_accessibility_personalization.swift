#!/usr/bin/env swift

import ApplicationServices
import Foundation

private enum ProbeError: LocalizedError {
    case usage
    case accessibilityUnavailable
    case missingProbe
    case unexpectedValue(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: ax_accessibility_personalization.swift <pid> <profile>"
        case .accessibilityUnavailable:
            "Accessibility access is unavailable."
        case .missingProbe:
            "The trusted QA accessibility-personalization probe was not found."
        case .unexpectedValue(let value):
            "The probe did not expose every enabled value for the requested profile: \(value)"
        }
    }
}

private struct ProbeResult: Codable {
    let pid: Int32
    let profile: String
    let role: String
    let identifier: String
    let title: String
    let description: String
    let value: String
    let help: String
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

private func elements(in application: AXUIElement, limit: Int = 8_000) -> [AXUIElement] {
    var result: [AXUIElement] = []
    var pending = [application]
    var index = 0

    while index < pending.count, result.count < limit {
        let element = pending[index]
        index += 1
        result.append(element)
        let children = attributeValue(kAXChildrenAttribute as CFString, from: element) as? [AXUIElement] ?? []
        pending.append(contentsOf: children)
    }
    return result
}

private func expectedEnabledValues(for profile: String) throws -> [String] {
    let mapping = [
        "reduce-motion": "Reduce Motion: On",
        "reduce-transparency": "Reduce Transparency: On",
        "increase-contrast": "Increase Contrast: On",
        "differentiate-without-color": "Differentiate Without Color: On"
    ]
    if profile == "all" { return Array(mapping.values) }

    let tokens = profile.split(separator: ",").map(String.init)
    let expected = tokens.compactMap { mapping[$0] }
    guard expected.count == tokens.count, !expected.isEmpty else { throw ProbeError.usage }
    return expected
}

do {
    guard CommandLine.arguments.count == 3,
          let rawPID = Int32(CommandLine.arguments[1]) else {
        throw ProbeError.usage
    }
    guard AXIsProcessTrusted() else { throw ProbeError.accessibilityUnavailable }

    let profile = CommandLine.arguments[2]
    let application = AXUIElementCreateApplication(pid_t(rawPID))
    let deadline = Date().addingTimeInterval(30)
    var probe: AXUIElement?

    repeat {
        probe = elements(in: application).first {
            stringAttribute(kAXIdentifierAttribute as CFString, from: $0) == "qa.accessibility-personalization"
        }
        if probe == nil { Thread.sleep(forTimeInterval: 0.12) }
    } while probe == nil && Date() < deadline

    guard let probe else { throw ProbeError.missingProbe }
    let title = stringAttribute(kAXTitleAttribute as CFString, from: probe)
    let description = stringAttribute(kAXDescriptionAttribute as CFString, from: probe)
    let value = stringAttribute(kAXValueAttribute as CFString, from: probe)
    let help = stringAttribute(kAXHelpAttribute as CFString, from: probe)
    let semanticText = [title, description, value, help]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    let expected = try expectedEnabledValues(for: profile)
    guard expected.allSatisfy(semanticText.contains) else {
        throw ProbeError.unexpectedValue(semanticText)
    }

    let result = ProbeResult(
        pid: rawPID,
        profile: profile,
        role: stringAttribute(kAXRoleAttribute as CFString, from: probe),
        identifier: stringAttribute(kAXIdentifierAttribute as CFString, from: probe),
        title: title,
        description: description,
        value: value,
        help: help
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(result))
    FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
