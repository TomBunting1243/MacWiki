# MacWiki Public Beta QA Matrix

Use this matrix as a release gate for every public beta. A public beta is not ready until every item is either marked pass or called out explicitly in release notes as a known caveat.

## Shell And Reading Lists

- [ ] Collapse an area that currently contains the selected list; selection stays valid and the app does not jump to an unrelated destination.
- [ ] Rename a nested folder from the context menu; the new name persists after relaunch.
- [ ] Drag a list into a folder and into an area; drop feedback, ordering, and persistence all behave correctly.
- [ ] Remove or delete a folder/list through the intended confirmation flow; counts and selection update correctly.
- [ ] Sidebar search behaves correctly in the sidebar surface across compact, regular, and wide widths.

## Tabs And Navigation

- [ ] `Cmd+T` opens a new tab without disturbing existing tab history.
- [ ] Reorder tabs with drag and confirm active-tab fallback when closing the active tab.
- [ ] Open an article in a background tab and confirm the current tab remains selected.
- [ ] `Cmd+K` opens search and selecting a result routes to the expected destination.

## Reader And Highlights

- [ ] Open a saved article and a fresh article; reader reveal, restore, and loading states feel smooth.
- [ ] Scroll, relaunch the app, and confirm reading position restoration for a previously opened article.
- [ ] Create, edit, and delete a highlight; the toolbar and note state stay coherent.
- [ ] Hover preview, open-in-new-tab, and save actions from the reader behave correctly.

## Inspector And References

- [ ] `Cmd+Shift+I` toggles the inspector cleanly from the main reading flow.
- [ ] Switch between inspector modes and confirm the correct section content is shown.
- [ ] Resize the info split and relaunch the app; persisted section sizing restores safely.
- [ ] Reference export or citation-focus flows still work from the current article.

## Discover, Settings, And Appearance

- [ ] Discover Time Machine loads a new date and the result surfaces update without stale state.
- [ ] Theme switching updates shell, reader, and discover surfaces consistently.
- [ ] `Cmd+,` opens Settings and reset/cache actions present the expected confirmations.
- [ ] Focus mode still enters and exits cleanly through both shortcut and menu flows.

## Accessibility And Distribution

- [ ] VoiceOver smoke pass on core shell navigation, tab strip, reader, and inspector surfaces.
- [ ] Keyboard-only pass for the major shortcut flows (`Cmd+K`, `Cmd+T`, `Cmd+Shift+I`, `Cmd+,`).
- [ ] Fresh install launch succeeds without manual Gatekeeper bypass.
- [ ] Relaunch persistence works for the last-used layout, tabs, and reading position.

## Performance

- [ ] Run `scripts/profile_reader_open.sh` and compare results to the current known-good baseline before release.
- [ ] Confirm no obvious regression in reader scroll smoothness or TOC responsiveness on the test machine.
