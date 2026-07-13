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

    @Test func offlineInjectionRequiresAnExactlyTrustedQASuite() {
        let networkOnly = [MacWikiQAEnvironment.networkModeKey: "offline"]
        #expect(MacWikiQAEnvironment.injectedNetworkError(in: networkOnly) == nil)

        let malformedSuite = [
            MacWikiQAEnvironment.defaultsSuiteKey: "com.tombunting.MacWiki.qa.invalid/suffix",
            MacWikiQAEnvironment.networkModeKey: "offline"
        ]
        #expect(MacWikiQAEnvironment.injectedNetworkError(in: malformedSuite) == nil)

        let trustedSuite = [
            MacWikiQAEnvironment.defaultsSuiteKey: "com.tombunting.MacWiki.qa.reader-offline",
            MacWikiQAEnvironment.networkModeKey: "offline"
        ]
        #expect(MacWikiQAEnvironment.injectedNetworkError(in: trustedSuite)?.code == .notConnectedToInternet)
    }

    @Test func unsupportedQANetworkModesDoNotAlterTransport() {
        let environment = [
            MacWikiQAEnvironment.defaultsSuiteKey: "com.tombunting.MacWiki.qa.reader-offline",
            MacWikiQAEnvironment.networkModeKey: "timeout"
        ]

        #expect(MacWikiQAEnvironment.injectedNetworkError(in: environment) == nil)
    }
}
