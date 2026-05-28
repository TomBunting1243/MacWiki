import Foundation

final class WebViewInspectorPublisher {
    private(set) var lastReportedVisibleSectionId: String?
    private(set) var hasTableOfContents = false
    var lastTOCPublishedForTitle: String = ""
    var lastReferencesPublishedForTitle: String = ""
    private var lastPublishedTOCFingerprint: Int?
    private var lastPublishedReferencesFingerprint: Int?
    private(set) var hasPublishedNonEmptyTOCSinceLoad = false
    private(set) var hasPublishedNonEmptyReferencesSinceLoad = false
    private var isTOCPublishInFlight = false
    private var isReferencesPublishInFlight = false

    func resetForContentReload() {
        lastReportedVisibleSectionId = nil
        hasTableOfContents = false
        lastTOCPublishedForTitle = ""
        lastReferencesPublishedForTitle = ""
        lastPublishedTOCFingerprint = nil
        lastPublishedReferencesFingerprint = nil
        hasPublishedNonEmptyTOCSinceLoad = false
        hasPublishedNonEmptyReferencesSinceLoad = false
        isTOCPublishInFlight = false
        isReferencesPublishInFlight = false
    }

    func beginTableOfContentsPublish() -> Bool {
        guard !isTOCPublishInFlight else { return false }
        isTOCPublishInFlight = true
        return true
    }

    func endTableOfContentsPublish() {
        isTOCPublishInFlight = false
    }

    func beginReferencesPublish() -> Bool {
        guard !isReferencesPublishInFlight else { return false }
        isReferencesPublishInFlight = true
        return true
    }

    func endReferencesPublish() {
        isReferencesPublishInFlight = false
    }

    func recordTableOfContents(_ items: [ArticleTableOfContentsItem]) -> Bool {
        hasTableOfContents = !items.isEmpty
        if !items.isEmpty {
            hasPublishedNonEmptyTOCSinceLoad = true
        }
        let fingerprint = Self.tableOfContentsFingerprint(items)
        guard lastPublishedTOCFingerprint != fingerprint else { return false }
        lastPublishedTOCFingerprint = fingerprint
        return true
    }

    func recordReferences(_ sections: [ArticleReferenceSection]) -> Bool {
        if !sections.isEmpty {
            hasPublishedNonEmptyReferencesSinceLoad = true
        }
        let fingerprint = Self.referencesFingerprint(sections)
        guard lastPublishedReferencesFingerprint != fingerprint else { return false }
        lastPublishedReferencesFingerprint = fingerprint
        return true
    }

    func shouldPublishVisibleSection(_ sectionId: String?, force: Bool) -> Bool {
        if force || sectionId != lastReportedVisibleSectionId {
            lastReportedVisibleSectionId = sectionId
            return true
        }
        return false
    }

    func clearPublishedTableOfContentsFingerprint() {
        lastPublishedTOCFingerprint = nil
    }

    func clearPublishedReferencesFingerprint() {
        lastPublishedReferencesFingerprint = nil
    }

    private static func tableOfContentsFingerprint(_ items: [ArticleTableOfContentsItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.title)
            hasher.combine(item.level)
        }
        return hasher.finalize()
    }

    private static func referencesFingerprint(_ sections: [ArticleReferenceSection]) -> Int {
        var hasher = Hasher()
        hasher.combine(sections.count)
        for section in sections {
            hasher.combine(section.id)
            hasher.combine(section.title)
            hasher.combine(section.items.count)
            for item in section.items {
                hasher.combine(item.id)
                hasher.combine(item.label)
                hasher.combine(item.group)
                hasher.combine(item.links.count)
                for link in item.links {
                    hasher.combine(link)
                }
            }
        }
        return hasher.finalize()
    }
}
