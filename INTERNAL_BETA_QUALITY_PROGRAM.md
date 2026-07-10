# MacWiki Internal Beta Quality Program

**Status:** Active baseline; MacWiki is **not ready** for internal beta

**Authority:** Sole active internal-beta gate

**Created:** 2026-07-10T01:19:07Z

**Goal branch:** `codex/internal-beta-xcode27`

**Baseline commit:** `9896c047c1a6743300276cf6c81b8c2b8569956d`

This is a living evidence program, not a confidence checklist. A row is not a pass unless its evidence proves the exact claim for the exact candidate. `PUBLIC_BETA_QA_MATRIX.md` and `RELEASE_BETA_CHECKLIST.md` are historical inputs only; active references to them must be retired before sign-off.

## 1. Beta definition, scope, and exclusions

The target is a fresh, local, ad-hoc-signed MacWiki candidate built from a clean goal commit, inspected, built, run, tested, and diagnosed through Xcode 27's official `xcode` MCP server backed by `xcrun mcpbridge`. It must preserve the macOS 26 deployment floor, use macOS 27 technology only where it solves a demonstrated problem, and pass automated and real-app quality gates.

### Non-negotiable Xcode tool policy

- Use only the official Codex `xcode` MCP server backed by `xcrun mcpbridge` for project inspection, schemes, settings, build/run/test, diagnostics, debugger/console, entitlements, Info.plist, and Xcode-specific problems.
- Do not enable, configure, or invoke third-party `XcodeBuildMCP`. Its pre-existing disabled configuration is not authorization to use it.
- Command-line Xcode tools are permitted only for release packaging or a capability demonstrably absent from the official bridge. Record every fallback, reason, command, result, and scope limit.
- A missing official tool is a blocker, never permission to substitute another Xcode integration.

### In scope

- Implemented article discovery, search, reading, tab, library, highlight, inspector, settings, persistence, cache, window, keyboard, and offline/error-recovery behavior.
- Every reachable interface and meaningful loading, empty, disabled, error, offline, narrow, wide, inactive-window, and first-run state.
- Release-blocking defects, evidenced architecture risks, regression coverage, static analysis, security posture, and safe local packaging.

### Explicit non-goals

- Readwise sync, Safari extension work, graph work, AI features, App Intents, collaboration, or unrelated roadmap expansion.
- Pushes, tags, GitHub releases, public distribution, Developer ID signing, notarization, external accounts, credential rotation, macOS security-setting changes, or irreversible data migration.
- Claiming real macOS 26 execution unless it actually occurs on macOS 26.

### Status vocabulary

| Status | Meaning |
|---|---|
| PASS | Current evidence proves the exact gate for the exact candidate. |
| FAIL | Current evidence contradicts the gate. Release-blocking until fixed or truthfully dispositioned. |
| BLOCKED | A named external/tool condition prevents the required proof. Never treated as a pass. |
| PENDING | Required work or evidence has not happened yet. |
| PARTIAL | Some evidence exists but does not cover the full gate. |
| DEFERRED | Intentionally outside this internal beta. |
| RETIRED | Historical context only; forbidden as release evidence. |

## 2. Evidence contract

Every evidence record must identify:

1. UTC timestamp.
2. Candidate commit and dirty state.
3. App path, executable path, PID, and isolated test-state path when runtime is involved.
4. Tool or reproducible procedure, including exact inputs.
5. Result and artifact/source path.
6. Operator and disposition.

Old checkboxes, old packages, previous runs, nearby debug builds, and assertions of confidence never prove a current result.

### Baseline evidence ledger

Baseline records below were consolidated at `2026-07-10T01:32:43Z` by the Codex Goal operator. They prove only their stated pre-candidate scope.

| ID | Captured UTC / operator | Evidence | Result | Scope limit |
|---|---|---|---|---|
| ENV-001 | 2026-07-10T01:32:43Z / Codex Goal | `git status --short --branch`; `git rev-parse HEAD` in `/Users/tombunting/.codex/worktrees/internal-beta-xcode27/MacWiki` | Clean branch at `9896c047c1a6743300276cf6c81b8c2b8569956d` before the program file was added | Baseline only; not a packaged candidate. |
| ENV-002 | 2026-07-10T01:32:43Z / Codex Goal | Xcode UI, Intelligence settings | `Allow external agents to use Xcode tools` is on; signed OpenAI Codex binary was approved | UI preflight only; not an MCP project action. |
| ENV-003 | 2026-07-10T01:32:43Z / Codex Goal | `xcodebuild -version` fallback | Xcode 27.0, build 27A5218g | CLI fallback because official tools were not attached; not build evidence. |
| ENV-004 | 2026-07-10T01:32:43Z / Codex Goal | `sw_vers`; `xcrun --sdk macosx --show-sdk-version`; `swift --version`; `uname -m` | Host macOS 27.0 build 26A5378j, macOS SDK 27.0, Apple Swift 6.4, arm64 | Host inventory only; no macOS 26 runtime coverage. |
| ENV-005 | 2026-07-10T01:32:43Z / Codex Goal | `xcrun --find mcpbridge`; SHA-256 | `/Applications/Xcode-beta.app/Contents/Developer/usr/bin/mcpbridge`; `399e636c47ef4a8911f651b79359f46110da1ebc90531e5f230d04cc2197f6bc` | Binary identity; bridge exposes no standalone version string in help. |
| ENV-006 | 2026-07-10T01:32:43Z / Codex Goal | `xcrun mcpbridge run-agent skills export --output-dir /tmp/macwiki-xcode27-skills-export` | Seven Apple skills exported; installed copies match export | Refresh baseline; repeat before macOS 27 modernization and after Xcode updates. |
| ENV-007 | 2026-07-10T01:32:43Z / Codex Goal | Official `xcode` MCP connection probe | MCP startup timed out awaiting `tools/list` after 30 seconds, twice, including with the clean Xcode window focused | **BLOCKED:** no official project inspection/build/test/diagnostic result exists. |
| ENV-008 | 2026-07-10T01:32:43Z / Codex Goal | `/Applications/ChatGPT.app/Contents/Resources/codex mcp list` | Official `xcode` server is enabled as `xcrun mcpbridge`; pre-existing `XcodeBuildMCP` is disabled | Configuration passes Apple's documented check; task attachment still fails. |
| ENV-009 | 2026-07-10T01:32:43Z / Codex Goal | Xcode Computer Use accessibility tree | Open workspace URL and description both identify `/Users/tombunting/.codex/worktrees/internal-beta-xcode27/MacWiki` | Visual/AX confirmation; official MCP workspace identity remains blocked. |
| ENV-010 | 2026-07-10T01:32:43Z / Codex Goal | `sysctl -n hw.model hw.memsize`; selected `system_profiler SPDisplaysDataType` fields | Mac16,1; Apple M4; 16 GiB RAM; 3024×1964 Retina main display | Current host only; keyboard/trackpad QA and alternate hardware remain pending. |
| DOC-001 | 2026-07-10T01:32:43Z / Codex Goal + read-only Jack/Indy audit agents | `obsidian vaults verbose`; Jack/Indy file inventories and CLI reads of active contracts/specs/ADRs/ops/sessions/reviews | Registered vaults are `Jack` and `Indy`; `Project Indy` returns `Vault not found.`; Jack inventory contains 108 project files | Folder-level corpus inventory and active-note classification; per-file evidence manifest remains pending. |

## 3. Environment inventory

| Item | Current value | Status |
|---|---|---|
| Goal worktree | `/Users/tombunting/.codex/worktrees/internal-beta-xcode27/MacWiki` | PASS baseline — ENV-001/ENV-009 |
| Goal branch / commit | `codex/internal-beta-xcode27` / `9896c047...` | PASS baseline — ENV-001 |
| Original worktree | `/Users/tombunting/Developer/MacWiki`; pre-existing release-doc edits preserved and excluded | PASS boundary — ENV-001 |
| Xcode / SDK / Swift | Xcode 27.0 (27A5218g), macOS SDK 27.0, Swift 6.4 | PASS inventory — ENV-003/ENV-004 |
| Official MCP configuration | `[mcp_servers.xcode] command = "xcrun"; args = ["mcpbridge"]` | PASS configuration — ENV-008 |
| Official MCP availability | No `xcode` tools exposed; server stalls at `tools/list` | BLOCKED — ENV-007 |
| Third-party Xcode MCP | `XcodeBuildMCP` is disabled; enabling, configuring, and invoking it are forbidden | PASS policy baseline — ENV-008 |
| Host hardware / OS | Mac16,1, Apple M4, 16 GiB, 3024×1964 Retina; macOS 27.0 beta, arm64 | PARTIAL coverage — ENV-004/ENV-010 |
| macOS 26 runtime | No current execution evidence | PENDING limitation |
| Xcode-exported skills | `swiftui-whats-new-27`, `swiftui-specialist`, `modernize-tests`, `device-interaction`, `audit-xcode-security-settings`, `adopt-c-bounds-safety`, `uikit-app-modernization` | PASS refresh — ENV-006 |
| Real-app QA mechanism | Computer Use for macOS; Apple `device-interaction` skill is iOS/simulator-oriented and not the Mac runtime harness | PARTIAL |

## 4. Documentation source-of-truth map

### Precedence

1. Current explicit Goal and user direction.
2. Current source, official Xcode results, current runtime behavior, and current tests.
3. `User Preferences.md`, accepted non-superseded ADRs, and current feature acceptance criteria.
4. Product Vision and Design Guide after conflict reconciliation.
5. Current Indy operational evidence as scenario/defect history, never as fresh candidate proof.
6. Roadmap checkmarks, development logs, old reviews, and old packages as historical context only.

### Classification

| Class | Documents | Use |
|---|---|---|
| Active product contract | Jack `01 Vision/User Preferences.md`; applicable feature specifications; `Design Guide.md` | Intended behavior, native feel, accessibility, performance, and scope after conflicts are resolved. |
| Product direction with stale claims | Jack `01 Vision/Product Vision.md`; `01 Vision/Roadmap.md` | Direction only; Readwise and completion claims require source/runtime proof. |
| Active technical decisions | Jack `04 Decisions/ADR-001...ADR-029` unless a later ADR supersedes an earlier one | Architecture and chrome ownership constraints; validate against current source. |
| Current architecture snapshot | Jack `02 Specifications/Architecture.md` | Audited ownership map dated 2026-03-24; deployment and working-tree claims require refresh. |
| Draft/unapproved copy | Jack `99 Reference/MacWiki Interface Copy Deck.md`, `MacWiki README Copy Deck.md`; `Approvals/Approvals.md` | No replacement copy is approved; do not treat blank fields as authorization. |
| Operational history | Indy `MacWiki Ops.md`, `Sessions/`, `Reviews/`, `Runbooks/`, `Development Log/` | Reproduction ideas, past defects, and old candidate history only. |
| Historical product logs | Jack `03 Development Log/` | Preserve; never use to prove current behavior. |
| Deferred research | Jack Readwise research/spec material | Readwise remains unimplemented/deferred unless current source and tests prove otherwise. |

### Audited corpus coverage

The Jack CLI inventory enumerated all 108 files under `Projects/MacWiki`: 107 Markdown notes plus `LICENSE`. Active contracts, specifications, ADRs, research/reference notes, approvals/copy decks, indexes, and historical/operational corpora received the classification below. A timestamped per-file evidence manifest remains required before the documentation-audit gate can pass.

| Corpus | Inventory | Classification / decision |
|---|---|---|
| Jack `01 Vision/` | Product Vision, User Preferences, Roadmap, section index | Product intent. User Preferences is the strongest self-declared behavior/design source; Roadmap completion marks are untrusted. |
| Jack `02 Specifications/` | Architecture, index, 17 feature notes | Acceptance/source map after conflict resolution. Architecture explicitly describes the 2026-03-24 tree and must be refreshed from source. |
| Jack `03 Development Log/` | 43 historical notes through 2026-04-29 | Historical only; its index says active operations moved to Indy. |
| Jack `04 Decisions/` | Index plus ADR-001 through ADR-029 | Technical decisions with incomplete supersession/status hygiene; use the decision map below. |
| Jack `05 Research/` | Readwise API, Wikipedia API, index | Historical research. API claims require current official verification before implementation use. |
| Jack `99 Reference/` | Settings Index, copy decks, prompt templates, index | Settings Index is a provisional generated inventory; copy decks are unapproved worksheets; prompt routing is stale. |
| Jack `Approvals/` | Approvals index only | No open or closed approvals exist. |
| Jack root | Design Guide, LICENSE, TRADEMARK | Design Guide is active but intentionally thin; legal files are current repo-copy references pending source comparison. |
| Indy `MacWiki Ops.md` | Active-labeled operations note last verified 2026-05-17, appended through 2026-06-01 | Scenario/defect history only; live paths and release instructions are stale. |
| Indy `Sessions/` | Six sessions from 2026-04-11 through 2026-05-31/June 1 appendices | Historical candidate and QA evidence only. |
| Indy `Reviews/` | Beta readiness and typography audits from 2026-04-23 | Historical findings and scenario leads; no current-candidate proof. |
| Indy `Runbooks/` | Agent Documentation Workflow plus index | Current-ish CLI pattern but names `Indy`, conflicting with repo adapter. |
| Indy `Prompt Templates/` | Prompt Templates index/note | Superseded; routes operational handoff to Jack history and omits Indy sessions. |
| Indy `Development Log/` | 37 dated logs plus two reviews | Legacy history mirror. |

### Feature specification disposition

| Disposition | Exact notes |
|---|---|
| Usable active acceptance input | `Article Display.md` (In Progress), `Article Search.md` (Completed), `Discover Hub.md` (Completed with labeled superseded scope), `Highlighting.md` (local implementation contract with historical sections), `Inspector Panel.md` (Completed v1 with deferred conflicts), `Reading Lists.md` (Complete header but open defect section), `Tab System.md` (Completed), `Readwise Integration.md` (planned/deferred despite contradictory checkmarks) |
| Ambiguous/stale status | `Breadcrumb Trail.md`, `Command Palette.md`, `Experiments Settings.md`, `Theme System.md`, `Wiki-Hop.md`, `Wiki-Hop Implementation Checklist.md`, `Wiki-Hop Run Guardrails.md`, `Agent Documentation Workflow.md` |
| Incomplete index | `Features.md` omits Breadcrumb Trail, Command Palette, Experiments Settings, and the two Wiki-Hop support notes |

No feature status or checked criterion becomes a pass until current source, runtime behavior, and tests agree.

### ADR decision and supersession map

Usable accepted decisions, subject to current-source confirmation: ADR-001 through ADR-008; retained portions of partially reverted ADR-009; ADR-010; and ADR-021 through ADR-028.

Known succession/conflict chains:

- Toolbar/shell: ADR-011 is superseded by ADR-012; ADR-012 is transitional to ADR-013; ADR-013 is refined by ADR-014; ADR-014 is superseded by ADR-015. ADR-016 through ADR-018 remain Accepted even though later ADR-021/022 and development history alter shell/surface ownership. Official source inspection must establish the live owner before edits.
- Context menus: ADR-019/020 remain Accepted, while the Highlighting spec and Architecture snapshot name native AppKit `NSMenu` / `WebViewContextMenuController` ownership. Treat 019/020 as superseded-in-practice pending a formal status correction.
- ADR-029 (Project Dolus maintainability boundary) remains Proposed even though the Architecture snapshot says Stages 1-8 landed. Treat its constraints as active engineering guidance, not an accepted historical fact.

### Conflict decisions

| ID | Conflict | Decision |
|---|---|---|
| CONFLICT-001 | Repo rules name vault `Project Indy`; CLI registers `Indy`. | Use explicit `vault="Indy"` after recording the failed canonical name. Correct active routing documentation at a commit-ready milestone. |
| CONFLICT-002 | Canonical Jack dashboard `Projects/MacWiki/MacWiki.md` is missing while section notes link to it. | Do not invent dashboard truth. Use specific product/spec/ADR notes and Indy Ops; restore or redirect the dashboard only from grounded evidence. |
| CONFLICT-003 | Product Vision promises bidirectional Readwise sync; User Preferences excludes it from v1; Readwise spec says planned/not implemented; Roadmap marks it complete. | **DEFERRED and unimplemented.** Do not add, activate, account-test, or claim it. |
| CONFLICT-004 | Roadmap marks not-started/deferred features and even unapproved ideas complete. | Roadmap checkmarks are historical/stale and never release evidence. Source/runtime/tests decide actual behavior. |
| CONFLICT-005 | Architecture declares macOS 15+ while the Goal requires macOS 26 and old logs report conflicting package/Info.plist floors. | Installed project settings and current source must establish the floor through official Xcode inspection. Until then compatibility is PENDING. |
| CONFLICT-006 | Indy candidate evidence targets older commits/Xcode versions and public-beta processes. | All old candidates are RETIRED for this Goal. Build a fresh ad-hoc-only candidate from a clean goal commit. |
| CONFLICT-007 | Reading Lists is marked Complete but retains open whitespace-only naming and duplicate-save normalization defects. | Reproduce against current source/runtime; close with regression evidence or carry as a defect. |
| CONFLICT-008 | Highlighting says document-range context extraction was fixed while Known Limitations still describes the old start-container behavior. | Current source and focused tests decide; update the active spec only at commit-ready. |
| CONFLICT-009 | Product docs, feature indexes, ADR statuses, and prompt templates contain incomplete or contradictory routing/status metadata. | Correct current bootstrap/index/status material without rewriting historical logs. |

### Retired candidate and QA evidence

Indy's latest documented package is `/Users/tombunting/Developer/MacWiki/dist/MacWiki-1.0-build1-20260601-110316.app`, commit `cf8915a77cdfafc70f043f818b4d7d13c5964c07`, branch `codex/beta-release-polish-qa`, built with Xcode 26.3. That commit is an ancestor of the current baseline and the artifact is **RETIRED** for this Goal. Indy contains no Xcode 27, current goal branch/commit, or current quality-program evidence.

Historical scenarios worth carrying forward, but not historical outcomes: multi-window shortcut focus; tab persistence; live resizing; native highlighting; sidebar search width states; Settings and VoiceOver acceptance; prior `NSTableView` reentrancy warnings; screenshot/AX attachment failures; hard-coded specialized typography; oversized SwiftUI surfaces; Discover Time Machine; cache/reset confirmations; cold launch and Dock reopen; Storage Recovery; reduced motion/transparency/contrast; toolbar overflow; and exact-candidate process targeting.

## 5. Provisional feature and user-journey inventory

This inventory is derived from active documentation and must be reconciled with official Xcode source inspection before it is complete.

| Journey | Required states and proof | Status |
|---|---|---|
| Launch and restoration | First launch, ordinary relaunch, restored tabs/windows, corrupt/missing state, no stale process | PENDING |
| Four-column research shell | Lists, Directory, Reader, Inspector; show/hide, resize, fullscreen, inactive window | PENDING |
| Search and command flow | Command-K, query debounce, results, keyboard selection, cancel/escape, errors | PENDING |
| Tabs and navigation | Open foreground/background, history, close/reopen, reorder, multiple windows, restoration | PENDING |
| Article reading | Cold/warm/hot open, skeleton, long/image-heavy article, internal/external links, scroll/restore | PENDING |
| Lists and organization | Areas/folders, lists, labels, tags, recents, saved/read state, drag/drop, context actions | PENDING |
| Highlights and notes | Selection, Command-H, native/custom paths, edit/delete, persistence, stale anchors | PENDING |
| Discover | Feed, search, Time Machine/date paths, loading/empty/error/offline/retry, save/open | PENDING |
| Inspector | Metadata, references, contents/TOC, highlights/notes, resize, keyboard toggle | PENDING |
| Settings and maintenance | Every pane, typography/theme, chrome, experiments, cache clears, reset confirmation | PENDING |
| About/legal | About panel, version/provenance, license/trademark links | PENDING |
| Readwise | No journey in this beta | DEFERRED |

## 6. Provisional interface families and required exhaustive Liquid Glass audit

The families below seed—not complete—the required inventory. Official source inspection and real-app discovery must assign a stable interface ID to every reachable screen, pane, toolbar, menu, context menu, sheet, popover, and state. Every ID then requires source mapping plus a rendered fresh-candidate audit. Source presence alone is not a visual pass.

| Surface family | States to audit | Native/Liquid Glass criteria | Status |
|---|---|---|---|
| App/window shell | First window, secondary window, titlebar, toolbar, fullscreen, inactive, narrow/wide | Native window hierarchy; correct draggable regions; coherent system materials; no duplicated glass or harsh borders | PENDING |
| Sidebar and split views | Expanded/collapsed, selection, hover, focus, resize limits, restoration | Native selection, spacing, density, vibrancy, tracked separators, keyboard/VoiceOver semantics | PENDING |
| Tab strip | Active/inactive, hover, pressed, close, overflow, reorder, long titles | Native affordances, stable identity, clear focus, interruption-safe animation, accessible state | PENDING |
| Directory and result rows | Loading, empty, selected, read/unread, missing image, long title, bulk/context actions | Semantic typography/color, predictable density, native menus, no truncation that hides meaning | PENDING |
| Reader/WebKit | Welcome, skeleton, loading, article, long article, error, offline, retry, find, selection | Legible content, no blank/previous-article flash, correct system chrome, contrast, smooth scroll/TOC, keyboard route | PENDING |
| Discover | Feed, Time Machine, date controls, loading, empty, error, offline, slow networking | Native hierarchy and controls, stable skeleton, meaningful recovery, wide/narrow composition | PENDING |
| Inspector | Contents, references, metadata, highlights/notes, collapsed/narrow | Native panel hierarchy, readable secondary content, resize behavior, focus/VoiceOver order | PENDING |
| Settings | Every pane, rows, sliders, pickers, reset/cache dialogs, disabled values | Native Settings patterns, correct labels/units, keyboard focus, escape/cancel, safe destructive confirmation | PENDING |
| Sheets/popovers/menus | Create/rename/move/delete, icon/color pickers, link/context menus, alerts | Correct anchoring, focus return, validation, menu equivalents, selected values, escape behavior | PENDING |
| Empty/error/offline/first-run | Each reachable empty, error, recovery, and clean-state path | Useful plain-language copy, no dead ends, accessible status, native retry/cancel actions | PENDING |

### Cross-cutting rendered criteria

- Native information hierarchy, typography, spacing, alignment, density, and semantic colors.
- System materials, vibrancy, translucency, shadows, inactive-window treatment, and intentional macOS 26 fallback.
- Selection, hover, focus, pressed, disabled, loading, empty, error, and offline states.
- Keyboard navigation, shortcuts, focus order/return, menu equivalents, escape/return behavior.
- VoiceOver labels, roles, values, actions, reading order, and live-state announcements.
- Increase Contrast, Reduce Transparency, Reduce Motion, light/dark, long content, large text where supported.
- Practical minimum/maximum widths, fullscreen, multiple windows, localization expansion, missing artwork, slow networking.
- Animation timing, interruption, state-update warnings, frame pacing, launch/open/scroll performance.

## 7. macOS 27 technology applicability record

No API is adopted merely because it is new. Each decision needs installed-SDK confirmation, official Apple guidance, project fit, compilation, macOS 26 availability handling, and regression proof.

MacWiki-specific applicability below is provisional because the current task has no official Xcode source-inspection result. Platform facts come from Apple's [Platforms State of the Union](https://developer.apple.com/videos/play/wwdc2026/102/), [What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/), [Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), and the Human Interface Guidelines for [materials](https://developer.apple.com/design/human-interface-guidelines/materials), [toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars), [split views](https://developer.apple.com/design/human-interface-guidelines/split-views), and [accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

| Candidate | Problem / possible benefit | macOS 27 approach and macOS 26 behavior | Risk | Decision |
|---|---|---|---|---|
| Native Liquid Glass/system materials | Consistent macOS hierarchy without imitation | Let standard navigation and controls receive system refinements; reserve interactive glass for important custom controls; preserve intentional macOS 26 material behavior | Contrast, over-layering, GPU cost, user glass personalization | **ADOPT AUDIT — high priority** |
| Toolbar visibility | Constrained toolbar items or clipped actions | Use `visibilityPriority` only for a reproduced defect and gate its macOS 26.1 availability; preserve explicit menus/commands on 26.0 | Customization persistence, traffic-light/titlebar geometry | **ADOPT SELECTIVELY** |
| `ToolbarOverflowMenu` / `.topBarPinnedTrailing` | Possible overflow/pinning | These are not macOS APIs; keep every command available through macOS-native toolbar/menu behavior | Incorrect platform assumption | **REJECT** |
| Split views and sidebars | Native column hierarchy, focus, restoration, edge materials | Retain a system split/inspector structure where current source confirms it; preserve hide/show commands and width behavior on 26 | Fixed widths, alternate shells, focus and selection loss | **KEEP/AUDIT; no speculative rewrite** |
| AsyncImage request/session controls | Repeated image loads/cache policy | New macOS 27 transport caching does not automatically replace decoded image caches, downsampling, coalescing, or eviction; retain the characterized 26 path | Duplicate caches, memory/network regressions | **DEFER migration for beta** |
| Reorderable containers | Native list/tab/folder reordering | Prototype only after current drag/reorder characterization; preserve the current path on 26 | Identity, persistence, close-button arbitration, autoscroll, accessibility | **DEFER** |
| Item-bound alerts/dialogs | Safer optional-item presentation | Modernize deprecated alert construction; use SDK 27 item binding only where it materially simplifies state and share action semantics with the 26 fallback | Startup interruption, stale item state, destructive defaults | **ADOPT after source audit** |
| SwiftUI State macro / ContentBuilder changes | SDK 27 source compatibility | Follow [TN3211](https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder); never repair State initialization errors by reordering assignments; behavior must remain identical at the macOS 26 deployment floor | Plausible compile fixes can silently retain the wrong default value | **MANDATORY compile and behavior audit** |
| AppKit/WebKit modernization | Correct native seams where SwiftUI is insufficient | Keep WKWebView/AppKit where required; characterize behavior, then extract narrow coordinator responsibilities; evaluate WebKit for SwiftUI only against a parity checklist | Lifecycle/state feedback loops; loss of highlight, menu, scroll, pooling, or recovery behavior | **ADOPT focused refactoring; defer framework rewrite** |
| Accessibility personalization | Glass, custom controls, WebKit/native focus, reading workflows | Audit Reduce Transparency, Increase Contrast, Show Borders where available, Differentiate Without Color, Reduce Motion, VoiceOver, and Full Keyboard Access; preserve semantic/macOS 26 equivalents | Hover-only affordances and custom glass can become unusable | **ADOPT — release gate** |
| Localization foundation | Long strings, layout expansion, user-facing text outside SwiftUI literals | Inventory strings and consider a String Catalog/`LocalizedStringResource`; test pseudo-localization, long content, and directionality while recording the actual beta language scope | Fixed thresholds, sentence fragments, Web/native mixing, unreviewed machine translation | **AUDIT; foundation decision pending source map** |
| Xcode 27 diagnostics/testing | Compiler/source changes, UI behavior, accessibility, performance | Swift Testing for suitable unit/integration tests; XCTest remains required for UI automation and performance; profile reader, tabs, resizing, search, scroll, and WebContent processes | Xcode 27 beta tooling defects must not be misclassified as app defects | **ADOPT — release gate** |
| New document APIs | Document lifecycle | MacWiki is not currently a document app | Scope mismatch | REJECT |
| C bounds safety / UIKit modernization | C memory safety or UIKit lifecycle | Apply only if those languages/frameworks enter project scope | Unnecessary scope | PROVISIONAL N/A |

## 8. Architecture and maintainability gates

The architecture note is a dated map, not proof of current source. Official Xcode source inspection must verify modules, dependency direction, state ownership, persistence boundaries, services, concurrency, error handling, test seams, and current file sizes.

| Gate | Required proof | Status |
|---|---|---|
| Module/dependency map | Official project inventory plus source citations | BLOCKED |
| State ownership | `AppState`, feature models, window-local state, observation invalidation review | BLOCKED |
| Persistence boundaries | SwiftData queries/mutations, save errors, migrations, isolated test stores | BLOCKED |
| Networking/cache | Actor boundaries, transport injection, retry/offline, cache ownership and budgets | BLOCKED |
| WebKit bridge | Lifecycle, script routing, state publication, scroll/restore, context menus, task cancellation | BLOCKED |
| Large-file hotspots | Current line counts and responsibilities; extraction decision before extension | BLOCKED |
| Typed settings | No new raw keys; ownership and defaults verified | BLOCKED |
| Characterization coverage | Tests before risky behavior-preserving refactors | PENDING |
| Maintainability checks | Repository checker and release-relevant advisories for exact candidate | PENDING |

Broad rewrites are forbidden. Prefer characterization tests and small boundary extractions where a current defect or required change demonstrates the need.

## 9. Automated, static, performance, and real-app program

| Gate | Required evidence | Status |
|---|---|---|
| Official Xcode clean build | Exact target/scheme, commit, output, and zero unresolved severe diagnostics | BLOCKED |
| Focused tests per fix | Exact official Xcode result and regression coverage | BLOCKED |
| Complete automated suite | Exact official Xcode full-test result for candidate commit | BLOCKED |
| Static analysis / compiler diagnostics | Official Xcode results and dispositions | BLOCKED |
| UI/integration harness | Safe isolated state; positive app/PID/path identity; reproducible results | PENDING |
| Launch/article/scroll performance | Instrumented scenarios on long image-heavy content; compare current baseline | PENDING |
| Computer Use QA | Fresh packaged candidate, screenshot + AX evidence, cleanup after each group | PENDING |
| macOS 26 compatibility | Availability review, deployment compilation/tests, real-OS limitation recorded | PENDING |

## 10. Accessibility, resilience, privacy, and data integrity

| Gate | Required scenarios | Status |
|---|---|---|
| Keyboard/focus | Core journeys, menus, tab order, escape/return, focus restoration | PENDING |
| VoiceOver | Shell, tabs, sidebar, directory, reader, inspector, Settings, sheets/popovers | PENDING |
| Contrast/transparency/motion | Increase Contrast, Reduce Transparency, Reduce Motion, light/dark/inactive | PENDING |
| Localization/long content | English baseline, long strings/titles, layout expansion; limitation recorded | PENDING |
| Networking/offline/retry | Deterministic transport or safe network control, cache fallback, recovery copy | PENDING |
| Persistence/data integrity | Isolated create/edit/move/delete/relaunch/recovery; no live user data | PENDING |
| Cache safety | Cold/warm/hot, clear temporary/offline cache, no cross-state corruption | PENDING |
| Secrets/privacy | Redacted secret scan; no values printed; account-free fixtures only | PENDING |
| Security settings | Read-only audit and user-approved plan before any build-setting/entitlement change | BLOCKED |

## 11. Candidate provenance, packaging, signing, and process discipline

Before every Computer Use session:

1. Commit and independently verify all relevant Goal changes.
2. Confirm `HEAD`, branch, and empty porcelain status in the clean candidate worktree.
3. Build/package from that commit only; never select by name or modification time alone.
4. Record BuildInfo commit, dirty state, build timestamp, Xcode/Swift, app path, executable path, hashes, package timestamp, and signing state.
5. Use ad-hoc signing only and verify with strict `codesign`; no Developer ID or notarization.
6. Use an isolated test-state location and public/sample content; never mutate live user data.
7. Identify candidate processes by exact executable path and PID. Do not close ambiguous/user-owned processes.
8. Capture fresh UI state after every meaningful action; do not reuse stale element references.
9. Gracefully quit the exact candidate after each scenario group; force-quit only that positively identified process if necessary and record why.
10. Verify no candidate process or window remains. Leave Xcode open.

| Packaging gate | Status |
|---|---|
| Clean committed source boundary | PENDING candidate |
| BuildInfo provenance and hashes | PENDING |
| Ad-hoc signing and strict verification | PENDING |
| Fresh launch/install verification | PENDING |
| Exact PID/test-state record | PENDING |
| End-of-scenario cleanup | PENDING |

## 12. Defect ledger

| ID | Severity | Affected build/state | Reproduction and evidence | Likely root cause | Owner / status | Fix commit | Regression coverage | Final verification | Disposition |
|---|---|---|---|---|---|---|---|---|---|
| IB-001 | Blocker (process) | Pre-candidate baseline `9896c047`; current Codex task | Start official `xcode` server or list resources: MCP startup times out awaiting `tools/list`; no tools are exposed | Task attachment/handshake failure; exact cause unknown | Goal environment / BLOCKED | — | Repeat configuration, `tools/list`, and first official project-inspection call | — | Restore official bridge tools; capture project inspection/build/test/diagnostic evidence. |
| IB-002 | Blocker (process) | Clean baseline `9896c047`; no candidate | Active tracked README/release tests/scripts point to the public-beta process; official source inspection is pending | Release-process documentation/test drift | Goal / PENDING confirmation | — | Regression searches and tests must assert only the internal program is active | — | Replace active references after official source inspection; retain explicitly retired historical context. |
| IB-003 | High, unverified | Unknown older development run in the original non-candidate Xcode window | Issue navigator shows repeated `Modifying state during view update`; provenance and current reproducibility are unknown | Unknown; possible synchronous representable-to-SwiftUI publication | Goal / PENDING reproduction | — | Fresh isolated cached/open/tab scenario plus official console/diagnostic result | — | If current, identify root cause, add regression coverage, fix, and re-run the scenario. |
| IB-004 | High (truth) | Current Jack documentation corpus | Product Vision/Roadmap/Readwise spec/Architecture disagree about Readwise implementation and completion | Documentation status/checkmark drift | Goal / OPEN | — | Source-of-truth validation and release-doc regression searches | — | Keep Readwise deferred; correct only current source-backed claims at commit-ready milestones. |
| IB-005 | Medium (operations) | Current Jack/Indy documentation corpus | Jack dashboard read returns file-not-found; `Project Indy` returns vault-not-found while `Indy` succeeds | Vault migration and bootstrap-link drift | Goal / OPEN | — | CLI read of every corrected bootstrap target plus link/routing searches | — | Repair current routing/bootstrap docs without rewriting history. |
| IB-006 | High (compatibility) | Pre-candidate baseline `9896c047`; no candidate | Architecture/history disagree on macOS 15 vs 26; current project settings lack official Xcode evidence | Deployment-floor documentation drift | Goal / BLOCKED | — | Official Package/Info/build-setting inspection; availability tests; macOS 26 compilation and runtime/limitation record | — | Prove the floor, fallback behavior, and real-OS coverage before sign-off. |
| IB-007 | Medium, unverified | Current Reading Lists documentation; source/build unknown | Feature note is Complete but retains open whitespace-only naming and duplicate-save normalization defects | Unknown until current source/runtime reproduction | Goal / PENDING reproduction | — | Focused persistence/input regressions plus isolated runtime scenarios | — | Reproduce against current source; fix or close with current evidence. |

Each new defect must preserve severity, affected build, reproducibility, evidence, root cause, owner/status, fix commit, regression coverage, final verification, and disposition. Severity may not be lowered merely to pass the program.

## 13. Final sign-off

No item below can pass by inference.

| Release-blocking gate | Exact pass criterion | Required evidence IDs/paths | Status / disposition |
|---|---|---|---|
| Clean traceable commit and provenance | Candidate `HEAD` equals BuildInfo commit; porcelain is empty; dirty is false; current build/package timestamps, app/binary paths, and hashes are recorded |  | PENDING |
| Official Xcode 27 MCP program | Official results exist for project/scheme/settings inspection, clean build, run, focused/full tests, analysis, issues, debugger/console, entitlements, and Info.plist; required tests all pass; zero unresolved errors, crashes, data-loss risks, or severe diagnostics | ENV-007 | BLOCKED |
| No third-party Xcode integration | `XcodeBuildMCP` remains disabled and the evidence ledger contains no invocation or configuration change; every Xcode-specific claim cites official `xcode` MCP | ENV-008 | PENDING final recheck |
| macOS 26 compatibility | Deployment floor is exactly macOS 26; every macOS 27 API has deliberate availability behavior; deployment build/tests and code review pass; real macOS 26 run passes or is named as an unpassed limitation |  | PENDING |
| Complete feature/journey inventory | Every current source/runtime feature and user journey has a stable ID, source locations, scenarios, and evidence/disposition; no official source or reachable behavior is unmapped |  | PENDING |
| Exhaustive interface inventory | Every reachable screen, pane, toolbar, sidebar, tab, reader/discover/settings state, sheet, popover, menu, context menu, empty/loading/error/offline/first-run state has a stable ID and rendered evidence |  | PENDING |
| Native Liquid Glass quality | Every interface ID passes active Design Guide/User Preferences/HIG criteria on macOS 27 and intentional macOS 26 behavior; all material defects are fixed and reverified |  | PENDING |
| Accessibility and layout | All applicable interface IDs pass keyboard/focus, VoiceOver/accessibility audit, contrast, Reduce Motion, Reduce Transparency, Show Borders where available, localization/long text, narrow/wide/fullscreen/inactive-window scenarios; zero unresolved major accessibility defects |  | PENDING |
| Functional/resilience/data integrity | Every functional, persistence, networking, offline/retry, cache, recovery, and isolated-data scenario passes; zero crashes, data loss/corruption, account access, or unsafe live-data mutation |  | PENDING |
| Architecture and maintainability | Dependency/state/persistence/concurrency/error/test-seam audit is complete; all release-blocking debt is fixed with characterization/regression tests; maintainability errors are zero and every advisory is dispositioned |  | PENDING |
| Performance | Every required launch/open/tab/search/resize/scroll scenario has a sourced budget or committed baseline and current result at or below it; no reproducible hitch, state-update warning, hang, or unbounded task remains |  | PENDING |
| Security/privacy/test-data safety | Approved security-audit plan is applied or explicitly deferred with rationale; redacted secret scan has zero unresolved hits; no sensitive value is printed; external accounts are untouched; isolated fixtures/state are proven |  | PENDING |
| Defect closure | Every blocker/high defect has fix commit, regression, and final verification; accepted lower-severity limitations are explicit and do not violate the beta definition |  | PENDING |
| Legacy QA retirement | Repo-wide search and regression tests prove all active docs, scripts, and tests use only `INTERNAL_BETA_QUALITY_PROGRAM.md`; legacy references remain solely in content explicitly marked RETIRED/historical |  | PENDING |
| Fresh ad-hoc package and Computer Use | Strict ad-hoc codesign passes; exact candidate path/binary/PID/state are recorded; every Computer Use scenario group passes against that candidate with fresh UI evidence |  | PENDING |
| Candidate cleanup | Graceful quit succeeds after every group or exact-PID fallback is recorded; final process/window check finds no agent-launched candidate; Xcode remains open |  | PENDING |
| Final readiness decision | Every row above is PASS with current candidate evidence and every known limitation/unverified area is explicit |  | PENDING |

**Current readiness decision:** **NOT READY — official Xcode MCP evidence is blocked and all candidate-quality gates remain incomplete.**
