import Foundation

final class WebViewInspectorPublisher {
    private(set) var lastReportedVisibleSectionId: String?
    private(set) var hasTableOfContents = false
    private var lastPublishedTOCFingerprint: Int?
    private var lastPublishedReferencesFingerprint: Int?
    private(set) var hasPublishedNonEmptyTOCSinceLoad = false
    private(set) var hasPublishedNonEmptyReferencesSinceLoad = false
    private var activeTOCPublishID: UUID?
    private var activeReferencesPublishID: UUID?
    private var visibleSectionMutationSequence: UInt64 = 0

    func resetForContentReload() {
        lastReportedVisibleSectionId = nil
        hasTableOfContents = false
        lastPublishedTOCFingerprint = nil
        lastPublishedReferencesFingerprint = nil
        hasPublishedNonEmptyTOCSinceLoad = false
        hasPublishedNonEmptyReferencesSinceLoad = false
        activeTOCPublishID = nil
        activeReferencesPublishID = nil
        visibleSectionMutationSequence &+= 1
    }

    func beginTableOfContentsPublish() -> UUID? {
        guard activeTOCPublishID == nil else { return nil }
        let publicationID = UUID()
        activeTOCPublishID = publicationID
        return publicationID
    }

    func endTableOfContentsPublish(_ publicationID: UUID) {
        guard activeTOCPublishID == publicationID else { return }
        activeTOCPublishID = nil
    }

    func beginReferencesPublish() -> UUID? {
        guard activeReferencesPublishID == nil else { return nil }
        let publicationID = UUID()
        activeReferencesPublishID = publicationID
        return publicationID
    }

    func endReferencesPublish(_ publicationID: UUID) {
        guard activeReferencesPublishID == publicationID else { return }
        activeReferencesPublishID = nil
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
        shouldPublishVisibleSection(
            sectionId,
            force: force,
            ifUnchangedSince: nil
        )
    }

    func beginVisibleSectionQuery() -> UInt64 {
        visibleSectionMutationSequence
    }

    func shouldPublishVisibleSection(
        _ sectionId: String?,
        force: Bool,
        ifUnchangedSince querySequence: UInt64?
    ) -> Bool {
        if let querySequence,
           querySequence != visibleSectionMutationSequence {
            return false
        }
        visibleSectionMutationSequence &+= 1
        if force || sectionId != lastReportedVisibleSectionId {
            lastReportedVisibleSectionId = sectionId
            return true
        }
        return false
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
