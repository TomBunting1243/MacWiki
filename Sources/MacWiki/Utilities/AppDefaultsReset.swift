import Foundation

enum AppDefaultsReset {
    static func candidateDomainNames(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        bundleName: String? = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String,
        processName: String = ProcessInfo.processInfo.processName,
        executablePath: String? = CommandLine.arguments.first
    ) -> [String] {
        var names: [String] = []

        appendUnique(bundleIdentifier, to: &names)
        appendUnique(bundleName, to: &names)
        appendUnique(processName, to: &names)

        if let executablePath {
            appendUnique(URL(fileURLWithPath: executablePath).lastPathComponent, to: &names)
        }

        // Running the bare SwiftPM executable commonly persists defaults to this domain.
        appendUnique("MacWiki", to: &names)
        return names
    }

    @discardableResult
    static func clearCandidateDomains(
        in defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        bundleName: String? = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String,
        processName: String = ProcessInfo.processInfo.processName,
        executablePath: String? = CommandLine.arguments.first
    ) -> [String] {
        let names = candidateDomainNames(
            bundleIdentifier: bundleIdentifier,
            bundleName: bundleName,
            processName: processName,
            executablePath: executablePath
        )
        clearDomains(names, in: defaults)
        return names
    }

    static func clearDomains(_ names: [String], in defaults: UserDefaults = .standard) {
        for name in names {
            defaults.removePersistentDomain(forName: name)
        }
    }

    private static func appendUnique(_ rawName: String?, to names: inout [String]) {
        guard let rawName else { return }
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !names.contains(trimmed) else { return }
        names.append(trimmed)
    }
}
