import Foundation
import Testing

/// Marks a test as needing live access to the Wikipedia API.
///
/// Live coverage is useful for detecting upstream contract changes, but it is also subject to
/// connectivity, rate limits, and API availability. Applying this trait lets deterministic runs
/// exclude those tests:
///
///     MACWIKI_SKIP_NETWORK_TESTS=1 swift test
///
/// Prefer `WikipediaService`'s injected `requestLoader` and `retrySleeper` for behavior owned by
/// MacWiki rather than Wikipedia.
let requiresLiveWikipedia: ConditionTrait = .enabled(
    if: ProcessInfo.processInfo.environment["MACWIKI_SKIP_NETWORK_TESTS"] != "1",
    "Requires live Wikipedia access; set MACWIKI_SKIP_NETWORK_TESTS=1 to skip"
)
