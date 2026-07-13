import Foundation
import Testing

@testable import MacWiki

@MainActor
struct MacWikiDefaultsTests {
    @Test func trustedQANameRoutesToDedicatedSuite() {
        let suiteName = MacWikiDefaults.qaSuitePrefix + UUID().uuidString
        let defaults = MacWikiDefaults.resolved(environment: [
            MacWikiDefaults.qaSuiteEnvironmentKey: suiteName
        ])

        #expect(defaults !== UserDefaults.standard)
        #expect(defaults.persistentDomain(forName: suiteName) == nil)
    }

    @Test func arbitrarySuiteNamesCannotRedirectProductionDefaults() {
        let defaults = MacWikiDefaults.resolved(environment: [
            MacWikiDefaults.qaSuiteEnvironmentKey: "untrusted.defaults.domain"
        ])

        #expect(defaults === UserDefaults.standard)
    }
}
