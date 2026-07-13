import Foundation
import SwiftData
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

    @Test func highlightFixtureRequiresTrustedSuiteAndNonemptyValues() {
        let suiteName = MacWikiDefaults.qaSuitePrefix + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create isolated defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("  Ada Lovelace  ", forKey: MacWikiQAFixtureSeeder.highlightArticleTitleKey)
        defaults.set("  Analytical Engine  ", forKey: MacWikiQAFixtureSeeder.highlightTextKey)

        #expect(
            MacWikiQAFixtureSeeder.requestedHighlightFixture(
                defaults: defaults,
                environment: [:]
            ) == nil
        )
        #expect(
            MacWikiQAFixtureSeeder.requestedHighlightFixture(
                defaults: defaults,
                environment: [MacWikiDefaults.qaSuiteEnvironmentKey: suiteName]
            ) == MacWikiQAHighlightFixtureRequest(
                articleTitle: "Ada Lovelace",
                text: "Analytical Engine"
            )
        )

        defaults.set("   ", forKey: MacWikiQAFixtureSeeder.highlightTextKey)
        #expect(
            MacWikiQAFixtureSeeder.requestedHighlightFixture(
                defaults: defaults,
                environment: [MacWikiDefaults.qaSuiteEnvironmentKey: suiteName]
            ) == nil
        )
    }

    @Test func trustedHighlightFixtureSeedsExactlyOnce() throws {
        let suiteName = MacWikiDefaults.qaSuitePrefix + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("Ada Lovelace", forKey: MacWikiQAFixtureSeeder.highlightArticleTitleKey)
        defaults.set("Analytical Engine", forKey: MacWikiQAFixtureSeeder.highlightTextKey)

        let schema = Schema([Tag.self, Highlight.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let environment = [MacWikiDefaults.qaSuiteEnvironmentKey: suiteName]

        MacWikiQAFixtureSeeder.seedRequestedFixtures(
            in: container,
            defaults: defaults,
            environment: environment
        )
        MacWikiQAFixtureSeeder.seedRequestedFixtures(
            in: container,
            defaults: defaults,
            environment: environment
        )

        let highlights = try container.mainContext.fetch(FetchDescriptor<Highlight>())
        #expect(highlights.count == 1)
        #expect(highlights.first?.articleTitle == "Ada Lovelace")
        #expect(highlights.first?.text == "Analytical Engine")
        #expect(highlights.first?.sectionTitle == "QA Fixture")
    }
}
