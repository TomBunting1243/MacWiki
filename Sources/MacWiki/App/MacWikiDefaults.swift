import Foundation

@MainActor
enum MacWikiDefaults {
    static let qaSuiteEnvironmentKey = "MACWIKI_QA_DEFAULTS_SUITE"
    static let qaSuitePrefix = "com.tombunting.MacWiki.qa."

    static let current = resolved(environment: ProcessInfo.processInfo.environment)

    static func resolved(environment: [String: String]) -> UserDefaults {
        guard let suiteName = environment[qaSuiteEnvironmentKey],
              suiteName.hasPrefix(qaSuitePrefix),
              suiteName.count > qaSuitePrefix.count,
              let suite = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return suite
    }
}
