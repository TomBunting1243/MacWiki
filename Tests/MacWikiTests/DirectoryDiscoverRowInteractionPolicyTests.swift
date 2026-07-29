import Foundation
import Testing

@testable import MacWiki

struct DirectoryDiscoverRowInteractionPolicyTests {
    @Test func rowIdentityUsesTheSameNormalizedTitleAsLibraryState() {
        #expect(
            DirectoryDiscoverRowInteractionPolicy.rowKey(
                articleID: "42",
                title: "  Ada_Lovelace  "
            ) == "discover:42:ada lovelace"
        )
    }

    @Test func statisticsClickSuppressesOnlyTheMatchingPrimaryRowTap() {
        let rowKey = "discover:42:ada lovelace"

        #expect(
            DirectoryDiscoverRowInteractionPolicy.primaryTapDecision(
                rowKey: rowKey,
                pendingPageViewsRowKey: rowKey
            ) == .suppressPageViewsTap
        )
        #expect(
            DirectoryDiscoverRowInteractionPolicy.primaryTapDecision(
                rowKey: rowKey,
                pendingPageViewsRowKey: "discover:43:grace hopper"
            ) == .openArticle
        )
        #expect(
            DirectoryDiscoverRowInteractionPolicy.primaryTapDecision(
                rowKey: rowKey,
                pendingPageViewsRowKey: nil
            ) == .openArticle
        )
    }

    @Test func explicitDestinationOverridesTheCurrentCommandModifier() {
        #expect(DirectoryDiscoverRowInteractionPolicy.shouldOpenInNewTab(
            explicitPreference: true,
            isCommandPressed: false
        ))
        #expect(!DirectoryDiscoverRowInteractionPolicy.shouldOpenInNewTab(
            explicitPreference: false,
            isCommandPressed: true
        ))
        #expect(DirectoryDiscoverRowInteractionPolicy.shouldOpenInNewTab(
            explicitPreference: nil,
            isCommandPressed: true
        ))
        #expect(!DirectoryDiscoverRowInteractionPolicy.shouldOpenInNewTab(
            explicitPreference: nil,
            isCommandPressed: false
        ))
    }

    @Test func selectingTheActiveTagClearsItAndSelectingAnotherReplacesIt() {
        let first = UUID()
        let second = UUID()

        #expect(DirectoryDiscoverRowInteractionPolicy.toggledTagFilterID(
            currentTagID: first,
            selectedTagID: first
        ) == nil)
        #expect(DirectoryDiscoverRowInteractionPolicy.toggledTagFilterID(
            currentTagID: first,
            selectedTagID: second
        ) == second)
    }

    @Test func timeoutClearsOnlyTheRequestThatCreatedIt() {
        let requested = "discover:42:ada lovelace"
        let replacement = "discover:43:grace hopper"

        #expect(DirectoryDiscoverRowInteractionPolicy.pendingRowKeyAfterTimeout(
            currentPendingRowKey: requested,
            requestedRowKey: requested
        ) == nil)
        #expect(DirectoryDiscoverRowInteractionPolicy.pendingRowKeyAfterTimeout(
            currentPendingRowKey: replacement,
            requestedRowKey: requested
        ) == replacement)
    }
}
