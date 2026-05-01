# MacWiki Model Handover

Audit date: 2026-03-24
Scope: current working tree on `main`, not a clean commit

## Snapshot

- The repo is **dirty** on `main`.
- The current working tree contains a large in-flight titlebar/toolbar/shell refactor.
- `git diff --stat` shows 24 modified tracked files, 3 deleted tracked files, and at least one new source file (`Sources/MacWiki/Views/Sidebar/NativeListsSourceList.swift`) not yet committed.
- Obsidian CLI was attempted first per project rules, but the local Obsidian app has CLI support disabled in this environment.

## What The App Actually Is

MacWiki is a native macOS Wikipedia client with a four-column layout:

1. Lists sidebar
2. Directory / content navigation
3. Reader
4. Inspector

The real runtime architecture in the audited tree is:

- `MacWikiApp` bootstraps SwiftData, shared URL cache, and top-level window behavior.
- `ContentView` is the SwiftUI orchestration layer for the window.
- `AppKitMainSplitView` is the AppKit shell that owns the `NSSplitViewController` and native toolbar wiring.
- `AppState` is the global state nucleus.
- `WikipediaService` is the dominant service actor.
- SwiftData is queried directly from many views.
- `WebView.swift` plus `WebView.js` carry a large share of reader interaction logic.

Important correction: older docs that describe separate `CacheService`, `PersistenceService`, `SyncService`, or `ReadwiseService` do **not** match the current code.

## Current Working-Tree Theme

Most recent code churn is concentrated around native window chrome ownership:

- `MainWindowCommandBar.swift` has been deleted.
- toolbar responsibility has moved into `MainWindowToolbar.swift` and `AppKitMainSplitView.swift`.
- `MacWikiApp.swift`, `ContentView.swift`, the column root views, `ReaderView.swift`, and `ColumnTopBar.swift` are all involved in the same shell/chrome story.
- The leftmost sidebar has now landed as a floating pane treatment with its own compact glass toggle control.
- The shell now models the lists column and directory column as separate visibility concerns rather than one monolithic sidebar.

Treat the current tree as a partially stabilized migration, not a settled final form.

## Verification I Ran

### Build / tests

- `swift test` ran and built successfully before testing.
- Result: the old XCTest `InfoboxParsingTests` suite passed `6/6`.
- Result: the Swift Testing suites ran `106` tests across `20` suites and surfaced **1 failing issue**:
  - `DebouncedActionSchedulerTests.scheduleCoalescesRepeatedActions()`

### Isolated rerun caveat

- `swift test --filter DebouncedActionSchedulerTests` did **not** give a clean isolated answer.
- Instead, it failed with a macOS bundle loading / system policy code-signature denial for `MacWikiPackageTests.xctest`.
- So the trustworthy signal is: the full suite currently reports one scheduler-related failure, but isolated reproduction in this environment is noisy.

## Highest-Signal Findings

1. The docs were overstating architecture maturity.
   - `02 Specifications/Architecture.md` described services and ownership boundaries that do not exist in source.
   - `02 Specifications/Features/Readwise Integration.md` implied remote sync behavior that is not implemented.

2. `AppState` is the center of gravity.
   - It owns tabs, active article, column visibility, focus mode, find/search requests, TOC/reference state, recents, Wiki-Hop, and a per-session article HTML cache.
   - If a behavior feels cross-column or cross-toolbar, start there.

3. The shell is intentionally split between SwiftUI and AppKit.
   - `ContentView` decides high-level behavior.
   - `AppKitMainSplitView` owns native toolbar and split-view geometry.
   - `AppState` owns the state those layers reconcile against.
   - The current sidebar landing makes that split more explicit: the lists column is now a floating-pane presentation inside the shell, while the directory remains a separate column.

4. The biggest risk files are also the biggest mental-load files.
   - `Sources/MacWiki/Views/Sidebar/DirectoryView.swift`
   - `Sources/MacWiki/Views/Components/WebView.swift`
   - `Sources/MacWiki/Views/Home/DiscoverNewTabPageView.swift`
   - `Sources/MacWiki/Services/WikipediaService.swift`
   - `Sources/MacWiki/Views/Sidebar/ListsSidebar.swift`
   - `Sources/MacWiki/App/AppState.swift`
   - `Sources/MacWiki/Views/Inspector/InspectorPanel.swift`
   - `Sources/MacWiki/Views/Reader/ReaderView.swift`
   - `Sources/MacWiki/Views/Shared/AppKitMainSplitView.swift`

5. Readwise is still future work.
   - `Highlight` contains `readwiseId` and `syncStatus`.
   - There is no runtime Readwise service, auth flow, or sync queue in the current source tree.

## Files To Read First

Read these in order if you are a new model picking up the app:

1. `Sources/MacWiki/App/MacWikiApp.swift`
2. `Sources/MacWiki/App/AppState.swift`
3. `Sources/MacWiki/Views/ContentView.swift`
4. `Sources/MacWiki/Views/Shared/AppKitMainSplitView.swift`
5. `Sources/MacWiki/Views/Shared/MainWindowToolbar.swift`
6. `Sources/MacWiki/Views/Columns/ListsColumnView.swift`
7. `Sources/MacWiki/Views/Columns/DirectoryColumnView.swift`
8. `Sources/MacWiki/Views/Columns/ReaderColumnView.swift`
9. `Sources/MacWiki/Views/Columns/InspectorColumnView.swift`
10. `Sources/MacWiki/Views/Reader/ReaderView.swift`
11. `Sources/MacWiki/Views/Components/WebView.swift`
12. `Sources/MacWiki/Services/WikipediaService.swift`

Then read these tests:

- `Tests/MacWikiTests/FocusModeStateTests.swift`
- `Tests/MacWikiTests/InspectorToggleStateTests.swift`
- `Tests/MacWikiTests/TabOpeningTests.swift`
- `Tests/MacWikiTests/ReaderStateTests.swift`
- `Tests/MacWikiTests/BugRegressionTests.swift`
- `Tests/MacWikiTests/DebouncedActionSchedulerTests.swift`

## Docs Updated During This Audit

- `MODEL_HANDOVER_2026-03-24.md`
- `/Users/tombunting/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jack/Projects/MacWiki/02 Specifications/Architecture.md`
- `/Users/tombunting/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jack/Projects/MacWiki/02 Specifications/Features/Readwise Integration.md`
- `/Users/tombunting/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jack/Projects/MacWiki/03 Development Log/Review - 2026-03-24.md`
- `/Users/tombunting/Library/Mobile Documents/iCloud~md~obsidian/Documents/Jack/Projects/MacWiki/MacWiki.md`

## Recommended Next Steps

1. Decide whether the current toolbar/titlebar migration should be finished from the current dirty tree or re-based onto a cleaner checkpoint.
2. Reproduce and fix or de-flake `DebouncedActionSchedulerTests.scheduleCoalescesRepeatedActions()`.
3. Verify the populated-window case for the recent titlebar ownership work, not just the empty-state window.
4. Audit whether `NativeListsSourceList.swift` is now the intended path or an abandoned branch of sidebar work under the new floating-pane sidebar direction.
5. Keep docs synced to the real code; this repo had meaningful architecture drift between notes and implementation.
