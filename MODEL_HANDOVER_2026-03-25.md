# MacWiki Model Handover

Date: 2026-03-25
Scope: window shell, left sidebar, directory top chrome

## What I Reverted Before Handing Off

I backed out the experimental shell changes from this session so the tree is back on the prior path instead of a half-tried branch.

- Removed the new scene-level toolbar modifiers from `Sources/MacWiki/App/MacWikiApp.swift`.
  - Removed `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)`
  - Removed `.toolbar(removing: .title)`
- Restored the prior AppKit window-chrome behavior in `Sources/MacWiki/Views/Shared/AppKitMainSplitView.swift`.
  - Restored `sidebarItem.titlebarSeparatorStyle = .none`
  - Restored the old `configureWindowChrome()` behavior that nils any toolbar, inserts `.fullSizeContentView`, and makes the titlebar transparent/hidden
- Restored the prior `8pt` top inset in `Sources/MacWiki/Views/Columns/DirectoryColumnView.swift`

Important: I did **not** rebuild after reverting those changes, per the latest user instruction.

## Current State

The source tree is back to the same general shell state it was in before this session’s experimental fixes.

The explicit end goal for the next instance is a fully native AppKit `.sidebar` on the far left, with the correct Apple Human Interface Guidelines behavior and styling:

- proper full-height relationship to the traffic lights and titlebar
- native sidebar section ownership, not a custom painted imitation
- native collapse/show affordances
- native resizing behavior
- native-looking materials and separation, with Apple owning as much of the chrome as possible

The underlying product problem is still unresolved:

1. The left sidebar still does not look properly native against the traffic lights.
2. There is still awkward top chrome above the directory / “link contents” column.
3. The shell chrome story is still internally inconsistent across SwiftUI and AppKit.

## Highest-Signal Findings

### 1. The grey bar above the directory content is not random

The “grey bar above link contents” is coming from the directory column’s own pinned header lane.

Relevant code:

- `Sources/MacWiki/Views/Columns/DirectoryColumnView.swift`
- `Sources/MacWiki/Views/Sidebar/DirectoryView.swift`

Specific mechanism:

- `DirectoryColumnView` adds a top inset above `DirectoryView`
- `DirectoryView` uses a top `safeAreaInset(edge: .top)` for `directoryPinnedHeader`
- `directoryPinnedHeader` paints a `.background(.bar)` surface

That means the strip is deliberate top chrome, not a compositor glitch.

### 2. The whole app is not mounted below the titlebar anymore

This was the most useful runtime fact from the LLDB inspection:

- `NSApp.windows.first?.toolbar == nil`
- `NSApp.windows.first?.contentView?.frame == (0, 0, 1800, 1130)`
- `NSApp.windows.first?.contentViewController?.view.frame == (0, 0, 1800, 1130)`
- `NSApp.windows.first?.contentLayoutRect == (0, 0, 1800, 1098)`

Interpretation:

- The content view itself fills the full window frame.
- So the remaining “doesn’t reach the traffic lights” problem is **not** simply that the whole split view is mounted 32 points too low.
- The remaining problem is inside the split item / titlebar section / surface ownership relationship.

### 3. The shell is still contradictory

Even in the inspected runtime:

- The window had **no toolbar object**
- The titlebar was still transparent/hidden
- The content view filled the full frame

That means the window shell is still trying to get titlebar underlap without a real toolbar/titlebar section contract.

This is probably why the far-left traffic-light region still feels slightly “off” instead of truly native.

The most likely root cause is still one of these two things, or both together:

- a toolbar/titlebar contract bug
- a botched legacy fix from an older shell iteration that left window chrome, split-view item configuration, and sidebar surface ownership in an inconsistent state

### 4. Verification in this environment is brittle

Two recurring problems made the chrome work harder to verify than it should have been:

- There were multiple `MacWiki` processes around unless they were explicitly killed first
- `screencapture` was unreliable here for targeted captures

What *did* work:

- killing extra `MacWiki` processes first
- using LLDB to inspect the live window and view hierarchy

What did *not* work reliably:

- trusting whichever `MacWiki` window happened to be frontmost
- relying on a stale incremental runtime without a clean rebuild

## What The Next Instance Should Do

### First

Do a fresh process cleanup before any visual or runtime inspection.

1. Kill every `MacWiki` process.
2. Launch only the debug build you intend to inspect.
3. Do not mix the debug build with `dist/*.app` during diagnosis.

### Then

Re-check the live split-view hierarchy, but target the **leftmost split item only** instead of dumping the whole tree.

The main question to answer is:

- What exact AppKit views are wrapping the sidebar split item right now?
- Is AppKit already providing its own full-height sidebar alley/background or titlebar section?
- Is SwiftUI still layering another sidebar surface or glass treatment inside that wrapper?

### Most likely next fix path

The next model should treat this as a split-item ownership problem, not a padding problem.

Concretely:

1. Re-audit the leftmost `NSSplitViewItem` path in `Sources/MacWiki/Views/Shared/AppKitMainSplitView.swift`
2. Decide whether the app needs:
   - a real toolbar/titlebar section contract again, or
   - a cleaner full-size-content-without-toolbar contract
3. Remove any duplicate sidebar surface ownership if both AppKit and SwiftUI are painting the same layer
4. Only after that, revisit the directory top chrome strip

### Directory chrome follow-up

If the left sidebar/titlebar contract gets fixed, the next model should revisit:

- `Sources/MacWiki/Views/Columns/DirectoryColumnView.swift`
- `Sources/MacWiki/Views/Sidebar/DirectoryView.swift`

The likely cleanup target is the combination of:

- the extra top inset in `DirectoryColumnView`
- the pinned header lane in `DirectoryView`

That combination is what produces the visible “grey bar above contents” feel.

## Recommended LLDB Starting Points

These were the most useful runtime checks:

```lldb
expr -l Swift -O -- import AppKit; NSApp.windows.first?.toolbar
expr -l Swift -O -- import AppKit; NSApp.windows.first?.contentLayoutRect
expr -l Swift -O -- import AppKit; NSApp.windows.first?.contentView?.frame
expr -l Swift -O -- import AppKit; NSApp.windows.first?.contentViewController?.view.frame
```

Then inspect the split view and its first item specifically rather than the whole tree.

## What I Did Not Do

- I did **not** build again after restoring the pre-experiment source state.
- I did **not** claim the sidebar/titlebar issue is fixed.
- I dwid **not** leave the experimental scene-level toolbar modifiers in place.

## Short Version For The Next Model

The user is frustrated and wants less experimentation, not more.

The i       mmediate task is:

- keep the tree on the prior baseline 
- aim for a fully native `.sidebar` result, not a custom approximation
- treat the sidebar/titlebar bug as a split-item / titlebar-section ownership issue
- keep in mind that the breakage may be a toolbar bug, a stale legacy fix, or both
- treat the grey directory strip as deliberate pinned-header chrome
- avoid mixing debug and packaged app processes during verification
- do not claim visual fixes without a clean runtime check
`
