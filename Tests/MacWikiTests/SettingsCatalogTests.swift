import AppKit
import Foundation
import Testing

import MacWikiSettingsCatalog

struct SettingsCatalogTests {
    @Test func catalogHasStableUniqueIdentifiers() {
        let optionIDs = SettingsCatalog.allOptions.map(\.id)
        let duplicateIDs = duplicates(in: optionIDs)
        #expect(duplicateIDs.isEmpty, "Duplicate settings catalog ids: \(duplicateIDs)")

        let storageKeys = SettingsCatalog.allOptions.compactMap(\.storageKey)
        let duplicateStorageKeys = duplicates(in: storageKeys)
        #expect(duplicateStorageKeys.isEmpty, "Duplicate storage keys in settings catalog: \(duplicateStorageKeys)")
    }

    @Test func appStorageReferencesAreCataloged() throws {
        let sourceRoot = repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MacWiki")
        let observedReferences = try SettingsAppStorageReferenceScanner.references(inSourceRoot: sourceRoot)
        let missingReferences = observedReferences
            .subtracting(SettingsCatalog.catalogedAppStorageReferences)
            .sorted()

        #expect(missingReferences.isEmpty, "Uncataloged @AppStorage references: \(missingReferences)")
    }

    @Test func markdownRendererContainsMaintenanceContract() {
        let markdown = SettingsCatalogMarkdownRenderer.render()

        #expect(markdown.contains("# MacWiki Settings Index"))
        #expect(markdown.contains("scripts/update_settings_index.sh"))
        #expect(markdown.contains("| Setting | Storage key | Default | Control | Values | Visible | Notes |"))
    }

    @Test func everySettingsSectionUsesAnAvailableSystemSymbol() {
        let unavailable = SettingsCatalog.sections.compactMap { section in
            NSImage(systemSymbolName: section.systemImage, accessibilityDescription: nil) == nil
                ? "\(section.id.rawValue): \(section.systemImage)"
                : nil
        }

        #expect(unavailable.isEmpty, "Unavailable settings symbols: \(unavailable)")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func duplicates(in values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }
}
