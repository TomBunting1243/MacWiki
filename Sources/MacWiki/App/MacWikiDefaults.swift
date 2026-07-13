import Foundation

enum MacWikiQAEnvironment {
    static let defaultsSuiteKey = "MACWIKI_QA_DEFAULTS_SUITE"
    static let defaultsSuitePrefix = "com.tombunting.MacWiki.qa."
    static let networkModeKey = "MACWIKI_QA_NETWORK_MODE"

    static func trustedSuiteName(in environment: [String: String]) -> String? {
        guard let suiteName = environment[defaultsSuiteKey],
              suiteName.hasPrefix(defaultsSuitePrefix) else {
            return nil
        }

        let suffix = suiteName.dropFirst(defaultsSuitePrefix.count)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard !suffix.isEmpty,
              suffix.unicodeScalars.allSatisfy(allowed.contains) else {
            return nil
        }
        return suiteName
    }

    static func injectedNetworkError(in environment: [String: String]) -> URLError? {
        guard trustedSuiteName(in: environment) != nil,
              environment[networkModeKey] == "offline" else {
            return nil
        }
        return URLError(.notConnectedToInternet)
    }
}

@MainActor
enum MacWikiDefaults {
    static let qaSuiteEnvironmentKey = MacWikiQAEnvironment.defaultsSuiteKey
    static let qaSuitePrefix = MacWikiQAEnvironment.defaultsSuitePrefix

    static let current = resolved(environment: ProcessInfo.processInfo.environment)

    static func resolved(environment: [String: String]) -> UserDefaults {
        guard let suiteName = MacWikiQAEnvironment.trustedSuiteName(in: environment),
              let suite = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return suite
    }
}
