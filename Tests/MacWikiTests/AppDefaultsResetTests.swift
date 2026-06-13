import Foundation
import Testing

@testable import MacWiki

struct AppDefaultsResetTests {
    @Test func candidateDomainNamesIncludeRuntimeFallbacks() {
        let domains = AppDefaultsReset.candidateDomainNames(
            bundleIdentifier: "com.tombunting.MacWiki",
            bundleName: "MacWiki",
            processName: "MacWiki",
            executablePath: "/tmp/MacWiki"
        )

        #expect(domains == ["com.tombunting.MacWiki", "MacWiki"])
    }

    @Test func candidateDomainNamesFallbackToMacWikiWhenMetadataMissing() {
        let domains = AppDefaultsReset.candidateDomainNames(
            bundleIdentifier: nil,
            bundleName: nil,
            processName: "",
            executablePath: nil
        )

        #expect(domains == ["MacWiki"])
    }

    @Test func clearDomainsRemovesOnlyRequestedDomains() {
        let suiteName = "qa.app-defaults-reset.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated defaults suite")
            return
        }

        // Persistent domains are global to the user account regardless of suite,
        // so never touch the real app domains here — use throwaway names.
        let appDomain = "qa.macwiki.app-domain.\(UUID().uuidString)"
        let processDomain = "qa.macwiki.process-domain.\(UUID().uuidString)"
        let unrelatedDomain = "qa.unrelated.\(UUID().uuidString)"

        defaults.setPersistentDomain(["tabBarLiquidGlass": true], forName: appDomain)
        defaults.setPersistentDomain(["searchPresentationMode": "Sidebar"], forName: processDomain)
        defaults.setPersistentDomain(["keepMe": 1], forName: unrelatedDomain)

        AppDefaultsReset.clearDomains([appDomain, processDomain], in: defaults)

        // After removal, persistentDomain(forName:) may legitimately report either
        // nil or an empty dictionary; both mean the domain is cleared.
        #expect(defaults.persistentDomain(forName: appDomain)?.isEmpty ?? true)
        #expect(defaults.persistentDomain(forName: processDomain)?.isEmpty ?? true)
        #expect(defaults.persistentDomain(forName: unrelatedDomain)?["keepMe"] as? Int == 1)

        defaults.removePersistentDomain(forName: unrelatedDomain)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
