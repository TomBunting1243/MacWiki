# MacWiki Engineering Notes

This is the portable working record for the internal-beta program. It captures standing engineering rules and the latest verified checkpoint; it is not a substitute for current source, runtime evidence, or the release ledger in `INTERNAL_BETA_QUALITY_PROGRAM.md`.

When this note disagrees with the app, a current test, a clean package manifest, or direct QA evidence, reality wins and this note must be corrected.

## Current checkpoint

- Integration branch: `codex/internal-beta-xcode27-integration`
- Current implementation checkpoint before this note: `b8b59ca` (`refactor: centralize sidebar selection state`)
- Clean packaged base: Candidate 141 at `b8b59caa092781874219d67a0f41ab2fed177597`
- Exact package: `dist/MacWiki-1.0-internal.141-build141-20260729-142857.app`
- Release decision: **NOT READY**

Candidate 141 is the only package that contains the current integration changes. It has complete deterministic preflight evidence but no fresh whole-app rendered acceptance yet.

## Standing engineering rules

### Prefer platform architecture

- Use current native SwiftUI or AppKit APIs when they express the behavior correctly.
- Keep the workspace as one semantic four-pane AppKit split controlled from SwiftUI state. Avoid overlay-based imitation panes and duplicated toolbar planes.
- Treat the main workspace and standalone article window as distinct native window roles. Do not force one toolbar policy onto both.
- Custom styling must support the native interaction, resizing, accessibility, and window hierarchy rather than imitate them.

### Persistence is transactional

- Views must not call `ModelContext.save()` directly or swallow save errors.
- Use `ModelContext.saveReportingFailure(operation:)` for a simple mutation. It saves, rolls back on failure, logs the operation, and publishes an app-level issue.
- Use a dedicated service for multi-step boundaries. `HighlightPersistence` and `LibraryResetService` are the current examples.
- Never publish success, advance progress, or update a success-only projection until persistence succeeds.

### Tests prove behavior

- Reading production `.swift` files as strings is not behavioral coverage. It is implementation-shape linting and must not be presented as proof that a feature works.
- Prefer direct model, coordinator, AppKit, SwiftUI-hosting, WebKit, persistence, and rendered interaction tests.
- Release and QA shell safety contracts are a narrow exception because package provenance, exact-process targeting, and heredoc execution boundaries are not importable app behavior.
- CSS and JavaScript source checks should be migrated to complete-resource or rendered WebKit fixtures when practical.
- Keep visual, animation, VoiceOver, hover, focus, and geometry claims in packaged Computer Use or accessibility evidence when a unit test cannot honestly observe them.

### QA is exact and isolated

- Every launch harness must source `scripts/lib/qa_process_safety.sh`.
- Prepare an isolated home with `qa_prepare_isolated_home`, launch with `qa_launch_candidate`, and terminate only the retained exact PID/process tree.
- The helper validates the candidate manifest, executable and app-tree hashes, signature decision, Xcode/SDK provenance, and minimum OS before launch.
- Same-name processes may be discovered only to refuse an ambiguous run. Never terminate by bundle name.
- Historical incident QA-003 remains part of the record: current architecture is isolated, but the program cannot truthfully claim that live MacWiki state was never opened during the entire Goal.

### Glass follows one accessibility policy

- `MacWikiGlassRuntime.SurfacePolicy` is the app-wide decision boundary for native glass, opaque fallback, and depth.
- Native glass requires the user preference, no forced fallback, no Reduce Transparency, and no Increase Contrast override.
- Reduce Transparency and Increase Contrast use solid, shadow-free fallbacks where required.
- Keep `GlassEffectContainer` structurally stable; leaf surfaces enable or disable effects through the policy.
- Discover may adapt the shared policy through `DiscoverSurfacePolicy`, but it must not invent a conflicting accessibility rule.

### Network gates are deterministic

- `WikipediaService` uses injected `RequestLoader` and `RetrySleeper` closures for behavior owned by MacWiki.
- Blocking CI and internal-beta preflight run with `MACWIKI_SKIP_NETWORK_TESTS=1`.
- Live Wikipedia tests use the `requiresLiveWikipedia` trait and remain advisory integration evidence. Upstream availability must not decide whether MacWiki's own deterministic behavior is sound.

### Packages are immutable evidence

- Package only a clean committed worktree. There is no dirty override.
- `--skip-build` requires the exact expected executable SHA-256.
- Signing requires an explicit identity, ad-hoc, or no-sign choice.
- The manifest and `BuildInfo.plist` must record the source commit, source and packaged executable hashes, app-tree hash, archive hash, signature decision, build toolchain, minimum OS, SDK, and timestamp.
- QA must revalidate those boundaries before launch.

## Integrated hardening after Candidate 140

- Persistence and WebKit/resource behavior are tested through real seams instead of production-source string scans; the former 2,294-line beta source-shape suite is gone.
- Network-owned behavior is deterministic while live Wikipedia checks remain explicitly advisory.
- Reader resource loading, scrolling, image timing, Discover status/load/popover handoff, Settings behavior, workspace interaction, and native chrome now have direct behavioral coverage.
- Glass and material surfaces share one Reduce Transparency/Increase Contrast policy, including drag previews, Wiki Hop, status surfaces, Reader highlights, Inspector states, and trend charts.
- Discover selection follows native focus; article rows retain independent accessibility controls; charts are keyboard operable; color-dependent states also expose shape, text, or pattern.
- Directory snapshot publication and cancellable lifecycle work have one coordinator, and folder hover expansion is bound to row lifetime.
- Lists sidebar selection canonicalization now has one window-local coordinator for native multiselection, external selection precedence, accessibility repeat activation, and deletion pruning.

## Verified evidence at this checkpoint

- Candidate 139 retains the latest complete packaged Reader/Inspector/shell journey; its visual observation was not preserved as a durable PNG set.
- Candidate 140 passed its clean nine-stage preflight and exact tab underlap/reorder/overflow journey; its Reader journey was interrupted and has no final passing report.
- Candidate 141 passed the complete clean nine-stage preflight from exact source `b8b59caa`: Debug and Release builds, 534 Swift Testing tests in 100 suites plus six XCTest tests, maintainability, shell syntax, redacted secret scan, provenance, ad-hoc signing, and packaging.
- Candidate 141 records Xcode 27.0, SDK 27.0, binary minimum macOS 26.0, executable SHA-256 `2bdb05b615c2e45fb94489249a215d2f7d702041ae8d5761bfb8be7b2c7386ec`, app-tree SHA-256 `c68ec9fd2fd077b2e87d1ac0c24c2e4bdd07d11aae35517e472e1ce2dcab6726`, and ZIP SHA-256 `8950c1caf8a9e361e8c1a62f7720fb53617f783aabb71cc970d59ae2668bd412`.
- Current maintainability gate passes with zero errors and ten advisories.
- Official Xcode 27 MCP evidence exists historically through Candidate 132. A fresh official-Xcode build and full test record is still required for the current integration when that tool is exposed.

## Work still required

- Run whole-app Computer Use and accessibility QA on exact Candidate 141, including every window and pane, loading semantics, hover/focus states, resizing, compact recovery, Reduce Motion, Reduce Transparency, Increase Contrast, and VoiceOver order/actions.
- Reconcile `INTERNAL_BETA_QUALITY_PROGRAM.md` through Candidates 136–141.
- Update Jack's casual-reader release log and Project Indy operational notes with current evidence and limitations.
- Reconcile stale architecture, Readwise, Inspector, and UI-language documentation against current product behavior.
- Address maintainability advisories incrementally where extraction improves ownership, invalidation, testability, or performance. Line count alone is not authorization for a risky rewrite.

The quality program owns release evidence and defect IDs. Do not create a parallel release ledger here.
