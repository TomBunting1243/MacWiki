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

    @Test func appStorageScannerExtractsReferencesFromInlineSource() {
        let source = #"""
        @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var glass = true
        @AppStorage( "literal.setting" , store: defaults) private var literal = false
        @AppStorage(
            ReaderAppearanceStorageKey.fontSize
        ) private var fontSize = 17.0
        """#

        #expect(SettingsAppStorageReferenceScanner.references(inSource: source) == [
            "AppStorageKey.Chrome.liquidGlassChrome",
            #""literal.setting""#,
            "ReaderAppearanceStorageKey.fontSize"
        ])
    }

    @Test func appStorageScannerWalksOnlyVisibleSwiftFileFixtures() throws {
        let fileManager = FileManager.default
        let fixtureRoot = fileManager.temporaryDirectory
            .appending(path: "MacWiki-SettingsScanner-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: fixtureRoot) }

        let nestedRoot = fixtureRoot.appending(path: "Nested", directoryHint: .isDirectory)
        let hiddenRoot = fixtureRoot.appending(path: ".Hidden", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: hiddenRoot, withIntermediateDirectories: true)
        try "@AppStorage(AppStorageKey.Reader.tableOfContentsPlacement) var placement"
            .write(to: fixtureRoot.appending(path: "Settings.swift"), atomically: true, encoding: .utf8)
        try "@AppStorage(ReaderAppearanceStorageKey.fontPreset) var font"
            .write(to: nestedRoot.appending(path: "Reader.swift"), atomically: true, encoding: .utf8)
        try "@AppStorage(Ignored.nonSwift) var ignored"
            .write(to: fixtureRoot.appending(path: "Notes.txt"), atomically: true, encoding: .utf8)
        try "@AppStorage(Ignored.hidden) var ignored"
            .write(to: hiddenRoot.appending(path: "Hidden.swift"), atomically: true, encoding: .utf8)

        let references = try SettingsAppStorageReferenceScanner.references(inSourceRoot: fixtureRoot)

        #expect(references == [
            "AppStorageKey.Reader.tableOfContentsPlacement",
            "ReaderAppearanceStorageKey.fontPreset"
        ])
    }

    @Test func markdownRendererContainsMaintenanceContract() {
        let markdown = SettingsCatalogMarkdownRenderer.render()

        #expect(markdown.contains("# MacWiki Settings Index"))
        #expect(markdown.contains("scripts/update_settings_index.sh"))
        #expect(markdown.contains("swift run SettingsIndexTool --validate-sources Sources/MacWiki"))
        #expect(markdown.contains("| Setting | Storage key | Default | Control | Values | Visible | Notes |"))
    }

    @Test @MainActor func everySettingsSectionUsesAnAvailableSystemSymbol() {
        let unavailable = SettingsCatalog.sections.compactMap { section in
            NSImage(systemSymbolName: section.systemImage, accessibilityDescription: nil) == nil
                ? "\(section.id.rawValue): \(section.systemImage)"
                : nil
        }

        #expect(unavailable.isEmpty, "Unavailable settings symbols: \(unavailable)")
    }

    private func duplicates(in values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 })
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()
    }
}
