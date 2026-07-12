import Foundation
import Testing

@testable import MacWiki

@MainActor
struct MacWikiDefaultsTests {
    @Test func qaSuiteIsIsolatedFromStandardDefaults() throws {
        let suiteName = MacWikiDefaults.qaSuitePrefix + UUID().uuidString
        let key = "qa-isolation-\(UUID().uuidString)"
        let defaults = MacWikiDefaults.resolved(environment: [
            MacWikiDefaults.qaSuiteEnvironmentKey: suiteName
        ])
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set("isolated", forKey: key)

        #expect(defaults.string(forKey: key) == "isolated")
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    @Test func arbitrarySuiteNamesCannotRedirectProductionDefaults() {
        let defaults = MacWikiDefaults.resolved(environment: [
            MacWikiDefaults.qaSuiteEnvironmentKey: "untrusted.defaults.domain"
        ])

        #expect(defaults === UserDefaults.standard)
    }
}
