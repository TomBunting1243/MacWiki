#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP_NAME:-MacWiki}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"
APP_BIN="${APP_BIN:-}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/settings-popups-home-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
INFO_PLIST="$APP_BUNDLE_PATH/Contents/Info.plist"
BUILD_INFO_PLIST="$APP_BUNDLE_PATH/Contents/Resources/BuildInfo.plist"

if [[ -z "$APP_BIN" || ! -x "$APP_BIN" ]]; then
  echo "ERROR: Set APP_BIN to an executable inside the exact packaged candidate." >&2
  exit 1
fi

[[ -f "$INFO_PLIST" ]] || { echo "Candidate Info.plist is missing: $INFO_PLIST" >&2; exit 1; }
[[ -f "$BUILD_INFO_PLIST" ]] || { echo "Candidate BuildInfo.plist is missing: $BUILD_INFO_PLIST" >&2; exit 1; }

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
TRACE_VERSION="$(plutil -extract Version raw "$BUILD_INFO_PLIST")"
TRACE_BUILD="$(plutil -extract BuildNumber raw "$BUILD_INFO_PLIST")"
TRACE_COMMIT="$(plutil -extract GitCommit raw "$BUILD_INFO_PLIST")"
TRACE_DIRTY="$(plutil -extract GitDirty raw "$BUILD_INFO_PLIST")"

[[ "$VERSION" == 1.0* ]] || { echo "Candidate is not on the 1.0 line: $VERSION" >&2; exit 1; }
[[ "$TRACE_VERSION" == "$VERSION" ]] || { echo "BuildInfo version does not match Info.plist" >&2; exit 1; }
[[ "$TRACE_BUILD" == "$BUILD" ]] || { echo "BuildInfo build does not match Info.plist" >&2; exit 1; }
[[ "$TRACE_DIRTY" == "false" ]] || { echo "BuildInfo says candidate source was dirty" >&2; exit 1; }
[[ "$TRACE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "BuildInfo commit is invalid" >&2; exit 1; }
qa_assert_candidate_manifest_matches_executable "$BUILD_INFO_PLIST"

qa_prepare_isolated_home
qa_assert_no_conflicting_processes
cleanup() {
  qa_stop_exact
  qa_stop_matching_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM
qa_launch_exact_bundle "/tmp/macwiki-qa-settings-popups-launch.log"

echo "Running Settings popups smoke QA..."

APP_NAME="$APP_NAME" APP_PID="$QA_APP_PID" SCRIPT_DIR="$SCRIPT_DIR" qa_run_command_with_timeout 180 osascript -l JavaScript <<'JXA'
ObjC.import('stdlib');

const se = Application('System Events');
const appName = ObjC.unwrap($.getenv('APP_NAME')) || 'MacWiki';
const appPid = Number(ObjC.unwrap($.getenv('APP_PID')) || '0');
const scriptDir = ObjC.unwrap($.getenv('SCRIPT_DIR')) || '';
const matchingProcesses = se.processes.whose({ unixId: appPid })();

if (matchingProcesses.length !== 1) {
  console.log('ERROR: verified app PID not found: ' + appPid + ' (' + appName + ')');
  throw new Error('app process missing');
}
const app = matchingProcesses[0];

function assertExactTargetFrontmost(targetWindow = null) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const exactProcesses = se.processes.whose({ unixId: appPid })();
    if (exactProcesses.length !== 1) {
      throw new Error(`verified app PID disappeared before global input: ${appPid}`);
    }
    app.frontmost = true;
    if (targetWindow) {
      try { targetWindow.actions.byName('AXRaise').perform(); } catch (e) {}
    }
    delay(0.1);
    if (Boolean(app.frontmost())) return;
  }
  throw new Error(`verified app PID is not frontmost before global input: ${appPid}`);
}

function exactKeyCode(keyCode, targetWindow = null) {
  assertExactTargetFrontmost(targetWindow);
  se.keyCode(keyCode);
}

function exactKeystroke(character, modifiers, targetWindow = null) {
  assertExactTargetFrontmost(targetWindow);
  se.keystroke(character, modifiers);
}

function settingsWindow() {
  const windows = app.windows();
  const settingsTitles = new Set(['reading', 'library', 'navigation', 'chrome', 'advanced']);
  for (const w of windows) {
    let name = '';
    try { name = w.name(); } catch (e) {}
    const normalizedName = String(name).toLowerCase();
    if (normalizedName.includes('settings') || settingsTitles.has(normalizedName)) {
      return w;
    }
  }
  return null;
}

function commandMenuItem(title) {
  const menuBars = app.menuBars();
  if (menuBars.length === 0) return null;
  const menuBarItems = menuBars[0].menuBarItems();
  for (const menuBarItem of menuBarItems) {
    let menus = [];
    try { menus = menuBarItem.menus(); } catch (e) { menus = []; }
    for (const menu of menus) {
      let items = [];
      try { items = menu.menuItems(); } catch (e) { items = []; }
      for (const item of items) {
        try {
          if (String(item.name()) === title) return item;
        } catch (e) {}
      }
    }
  }
  return null;
}

function assertDocumentCommandsUnavailableInSettings() {
  const requiredReaderTitles = new Set([
    'Back',
    'Forward',
    'Reader Style…',
    'Page Views…',
    'Open in Browser',
    'Share…'
  ]);
  const titles = [
    'Search Wikipedia',
    'Find in Page',
    'New Reading List',
    'New Folder',
    'New Tab',
    'Close Tab',
    'Reopen Closed Tab',
    'Save Article…',
    'Add to List…',
    'Toggle Inspector',
    ...requiredReaderTitles,
    'Next Tab',
    'Previous Tab',
    'Increase Reader Font Size',
    'Decrease Reader Font Size',
    'Reset Reader Font Size'
  ];
  for (const title of titles) {
    const item = commandMenuItem(title);
    if (!item) {
      if (requiredReaderTitles.has(title)) {
        throw new Error(`${title} was missing while Settings was frontmost`);
      }
      continue;
    }
    let enabled = false;
    try { enabled = Boolean(item.enabled()); } catch (e) {}
    if (enabled) throw new Error(`${title} stayed enabled while Settings was frontmost`);
  }

  const readStateItems = ['Mark as Read', 'Mark as Unread']
    .map(commandMenuItem)
    .filter(item => item !== null);
  if (readStateItems.length !== 1) {
    throw new Error('Settings must expose exactly one disabled Mark as Read/Unread command');
  }
  let readStateEnabled = false;
  try { readStateEnabled = Boolean(readStateItems[0].enabled()); } catch (e) {}
  if (readStateEnabled) {
    throw new Error('Mark as Read/Unread stayed enabled while Settings was frontmost');
  }
}

function collectPopups(el, out) {
  let role = '';
  try { role = el.role(); } catch (e) {}
  if (role === 'AXPopUpButton') out.push(el);
  let children = [];
  try { children = el.uiElements(); } catch (e) { children = []; }
  for (const child of children) collectPopups(child, out);
}

function collectSliders(el, out) {
  let role = '';
  try { role = el.role(); } catch (e) {}
  if (role === 'AXSlider') out.push(el);
  let children = [];
  try { children = el.uiElements(); } catch (e) { children = []; }
  for (const child of children) collectSliders(child, out);
}

function collectElements(el, out) {
  out.push(el);
  let children = [];
  try { children = el.uiElements(); } catch (e) { children = []; }
  for (const child of children) collectElements(child, out);
}

function elementStrings(el) {
  const values = [];
  for (const read of [() => el.name(), () => el.description(), () => el.title(), () => el.value()]) {
    try {
      const raw = read();
      if (raw !== null && raw !== undefined && String(raw).length > 0) values.push(String(raw));
    } catch (e) {}
  }
  return values;
}

function cgScrollArea(scrollArea, deltaY) {
  if (!scrollArea || scriptDir.length === 0) return false;
  try {
    const position = scrollArea.position();
    const size = scrollArea.size();
    const x = Math.round(Number(position[0]) + Number(size[0]) / 2);
    const y = Math.round(Number(position[1]) + Number(size[1]) / 2);
    const app = Application.currentApplication();
    app.includeStandardAdditions = true;
    const escapedScriptDir = scriptDir.replace(/'/g, `'\\''`);
    app.doShellScript(`/usr/bin/swift '${escapedScriptDir}/cg_scroll.swift' --x ${x} --y ${y} --delta-y ${deltaY} --steps 18 --interval-ms 12`);
    delay(0.25);
    return true;
  } catch (e) {
    console.log(`CG scroll fallback failed: ${e}`);
    return false;
  }
}

function pressSettingsTab(title) {
  const deadline = Date.now() + 6000;
  while (Date.now() < deadline) {
    const currentWindow = settingsWindow();
    if (currentWindow) {
      const elements = [];
      collectElements(currentWindow, elements);
      const target = elements.find(el => {
        let role = '';
        try { role = String(el.role()); } catch (e) {}
        return ['AXButton', 'AXRadioButton'].includes(role) && elementStrings(el).includes(title);
      });
      if (target) {
        try { target.actions.byName('AXPress').perform(); } catch (e) { target.click(); }
        for (let attempt = 0; attempt < 20; attempt += 1) {
          delay(0.1);
          const refreshed = settingsWindow();
          if (refreshed && settingsTabIsSelected(title, refreshed)) return refreshed;
        }
      }
    }
    delay(0.1);
  }
  throw new Error(`Settings tab did not become active: ${title}`);
}

function settingsTabIsSelected(title, window) {
  let windowName = '';
  try { windowName = String(window.name()); } catch (e) {}
  if (windowName.toLowerCase() === title.toLowerCase()) return true;

  const elements = [];
  collectElements(window, elements);
  const tab = elements.find(element => {
    let role = '';
    try { role = String(element.role()); } catch (e) {}
    return role === 'AXRadioButton' && elementStrings(element).includes(title);
  });
  if (!tab) return false;
  try {
    const value = String(tab.value()).toLowerCase();
    return value === '1' || value === 'true' || value === 'selected';
  } catch (e) {
    return false;
  }
}

function auditSettingsPane(title, expectedStrings) {
  pressSettingsTab(title);
  delay(0.4);
  const observedStrings = new Set();
  let interactiveCount = 0;
  let scrollArea = null;
  let verticalScrollBar = null;
  let missingWindowPasses = 0;
  for (let pass = 0; pass < 60; pass += 1) {
    const currentWindow = settingsWindow();
    if (!currentWindow) {
      missingWindowPasses += 1;
      if (missingWindowPasses % 10 === 0) {
        exactKeystroke(',', { using: 'command down' });
      }
      delay(0.2);
      continue;
    }
    if (!settingsTabIsSelected(title, currentWindow)) {
      pressSettingsTab(title);
      delay(0.25);
      continue;
    }
    missingWindowPasses = 0;
    const elements = [];
    collectElements(currentWindow, elements);
    elements.flatMap(elementStrings).forEach(value => observedStrings.add(value));
    interactiveCount = Math.max(interactiveCount, elements.filter(el => {
      let role = '';
      try { role = String(el.role()); } catch (e) {}
      return ['AXButton', 'AXRadioButton', 'AXPopUpButton', 'AXSlider', 'AXCheckBox'].includes(role);
    }).length);
    const observedText = [...observedStrings].join('\n');
    if (expectedStrings.every(expected => observedText.includes(expected))) break;

    const scrollAreas = elements.filter(el => {
      try { return String(el.role()) === 'AXScrollArea'; } catch (e) { return false; }
    }).sort((lhs, rhs) => {
      try {
        const leftSize = lhs.size();
        const rightSize = rhs.size();
        return Number(rightSize[0]) * Number(rightSize[1]) - Number(leftSize[0]) * Number(leftSize[1]);
      } catch (e) { return 0; }
    });
    scrollArea = scrollAreas[0] || scrollArea;
    verticalScrollBar = elements.find(el => {
      try {
        if (String(el.role()) !== 'AXScrollBar') return false;
        const size = el.size();
        return Number(size[1]) > Number(size[0]);
      } catch (e) { return false; }
    }) || verticalScrollBar;
    let scrolled = false;
    if (verticalScrollBar) {
      try {
        verticalScrollBar.value = 1;
        scrolled = true;
      } catch (e) {}
    }
    if (scrollArea) {
      try {
        scrollArea.actions.byName('AXScrollDownByPage').perform();
        scrolled = true;
      } catch (e) {}
    }
    if (!scrolled) exactKeyCode(121, currentWindow); // Page Down
    delay(0.15);
  }
  let visibleText = [...observedStrings].join('\n');
  const missingBeforeCG = expectedStrings.filter(expected => !visibleText.includes(expected));
  let usedCGScroll = false;
  if (missingBeforeCG.length > 0 && scrollArea) {
    usedCGScroll = cgScrollArea(scrollArea, -8);
    if (usedCGScroll) {
      for (let pass = 0; pass < 4; pass += 1) {
        const currentWindow = settingsWindow();
        if (!currentWindow) {
          delay(0.2);
          continue;
        }
        const elements = [];
        collectElements(currentWindow, elements);
        elements.flatMap(elementStrings).forEach(value => observedStrings.add(value));
        delay(0.1);
      }
      visibleText = [...observedStrings].join('\n');
    }
  }
  const missing = expectedStrings.filter(expected => !visibleText.includes(expected));
  if (scrollArea) {
    for (let restorePass = 0; restorePass < 10; restorePass += 1) {
      try { scrollArea.actions.byName('AXScrollUpByPage').perform(); } catch (e) { break; }
    }
  }
  if (verticalScrollBar) {
    try { verticalScrollBar.value = 0; } catch (e) {}
  }
  if (usedCGScroll) cgScrollArea(scrollArea, 8);
  console.log(`Pane ${title}: interactive=${interactiveCount}, expected=${expectedStrings.length}, missing=${missing.join(' | ') || 'none'}`);
  if (missing.length > 0) {
    let windowSize = '';
    try { windowSize = String(settingsWindow().size()); } catch (e) {}
    let scrollActions = '';
    try { scrollActions = scrollArea.actions().map(action => String(action.name())).join(' | '); } catch (e) {}
    let scrollValue = '';
    try { scrollValue = String(verticalScrollBar.value()); } catch (e) {}
    console.log(`Pane ${title} diagnostics: window=${windowSize}, scrollActions=${scrollActions || 'none'}, scrollValue=${scrollValue || 'none'}`);
    console.log(`Pane ${title} observed strings: ${[...observedStrings].slice(0, 80).join(' | ')}`);
    throw new Error(`${title} pane is missing expected visible semantics: ${missing.join(', ')}`);
  }
}

function popupValue(popup) {
  try { return String(popup.value()); } catch (e) { return ''; }
}

function refreshedPopup(popupIndex, fallback) {
  const refreshedPopups = [];
  collectPopups(settingsWindow(), refreshedPopups);
  return refreshedPopups[popupIndex] || fallback;
}

function selectPopupItem(popupIndex, fallback, acceptsName) {
  const observedCandidates = new Set();
  for (let openAttempt = 0; openAttempt < 4; openAttempt += 1) {
    const currentPopup = refreshedPopup(popupIndex, fallback);
    try { currentPopup.actions.byName('AXPress').perform(); } catch (e) { continue; }
    for (let readinessAttempt = 0; readinessAttempt < 12; readinessAttempt += 1) {
      delay(0.1);
      try {
        const menus = currentPopup.menus();
        if (menus.length === 0) continue;
        for (const item of menus[0].menuItems()) {
          let itemName = '';
          try { itemName = String(item.name()); } catch (e) {}
          if (itemName.length > 0) observedCandidates.add(itemName);
          if (itemName.length > 0 && acceptsName(itemName)) {
            item.actions.byName('AXPress').perform();
            delay(0.25);
            return { selected: true, candidates: [...observedCandidates] };
          }
        }
      } catch (e) {}
    }
    exactKeyCode(53, settingsWindow());
    delay(0.1);
  }
  return { selected: false, candidates: [...observedCandidates] };
}

function togglePopupAndRestore(popup, popupIndex) {
  const before = popupValue(popup);
  const changeResult = selectPopupItem(popupIndex, popup, name => name !== before);
  const changedPopup = refreshedPopup(popupIndex, popup);
  const changed = popupValue(changedPopup);

  const restoreResult = selectPopupItem(popupIndex, changedPopup, name => name === before);
  const restorePopup = refreshedPopup(popupIndex, changedPopup);
  const after = popupValue(restorePopup);
  if (!changeResult.selected) {
    console.log(`Change candidates for '${before}': ${changeResult.candidates.join(' | ')}`);
  }
  if (!restoreResult.selected) {
    console.log(`Restore candidates for '${before}': ${restoreResult.candidates.join(' | ')}`);
  }

  return { before, changed, after };
}

app.frontmost = true;
let win = settingsWindow();
if (!win) {
  for (let commandAttempt = 0; commandAttempt < 4 && !win; commandAttempt += 1) {
    exactKeystroke(',', { using: 'command down' });
    for (let readinessAttempt = 0; readinessAttempt < 12 && !win; readinessAttempt += 1) {
      delay(0.25);
      win = settingsWindow();
    }
  }
}
if (!win) {
  const observedNames = app.windows().map(w => {
    try { return String(w.name()); } catch (e) { return '<unknown>'; }
  });
  console.log('Observed windows after Settings command: ' + observedNames.join(', '));
  console.log('ERROR: settings window not found');
  throw new Error('settings window missing');
}
assertDocumentCommandsUnavailableInSettings();

try {
  const currentPosition = win.position();
  win.position = [currentPosition[0], 80];
  win.size = [760, 960];
  delay(0.25);
  win = settingsWindow() || win;
} catch (e) {
  console.log('Settings window resize unavailable; continuing with scroll traversal: ' + e);
}

const paneContracts = [
  ['Advanced', ['Advanced', 'Experimental features, cache maintenance', 'In-Memory', 'Disk', 'Pinned on Disk', 'Performance samples appear here']],
  ['Reading', ['Font', 'Font Size', 'Line Height', 'Paragraph Spacing', 'Content Width', 'Side Margin', 'Heading Scale', 'Immediate Reveal']],
  ['Library', ['Sidebar Sort', 'Default Save List', 'Label Display', 'Highlight Marker']],
  ['Navigation', ['Discover', 'Hide Sidebar Time Machine', 'Recents', 'Recents Shows']],
  ['Chrome', ['Chrome', 'Use translucent Liquid Glass treatment']]
];
for (const [title, expectedStrings] of paneContracts) {
  auditSettingsPane(title, expectedStrings);
}
win = pressSettingsTab('Reading');

const popups = [];
for (let attempt = 0; attempt < 12 && popups.length < 2; attempt += 1) {
  popups.length = 0;
  collectPopups(win, popups);
  if (popups.length < 2) delay(0.25);
}
if (popups.length < 2) {
  console.log('ERROR: expected >=2 visible popup controls, found ' + popups.length);
  throw new Error('insufficient popup controls');
}

const sliders = [];
collectSliders(win, sliders);
if (sliders.length < 6) {
  console.log('ERROR: expected >=6 visible native slider controls, found ' + sliders.length);
  throw new Error('insufficient slider controls');
}

for (const [index, slider] of sliders.entries()) {
  let label = '';
  let value = '';
  for (const read of [() => slider.description(), () => slider.title(), () => slider.name()]) {
    try {
      const candidate = read();
      if (candidate !== null && candidate !== undefined && String(candidate).length > 0) {
        label = String(candidate);
        break;
      }
    } catch (e) {}
  }
  try { value = String(slider.value()); } catch (e) {}
  console.log(`Slider ${index + 1}: label='${label}' value='${value}'`);
  if (label.length === 0 || label.toLowerCase() === 'slider' || value.length === 0) {
    throw new Error(`slider ${index + 1} is missing accessible label or value`);
  }
}

function popupName(popup, index) {
  for (const read of [
    () => popup.name(),
    () => popup.description(),
    () => popup.title(),
    () => popupValue(popup)
  ]) {
    try {
      const rawValue = read();
      if (rawValue !== null && rawValue !== undefined) {
        const value = String(rawValue);
        if (value.length > 0) return value;
      }
    } catch (e) {}
  }
  return `Popup ${index + 1}`;
}

function validate(name, result) {
  const changed = result.changed !== result.before;
  const restored = result.after === result.before;
  console.log(`${name}: before='${result.before}' changed='${result.changed}' after='${result.after}'`);
  if (!changed) {
    console.log(`ERROR: ${name} did not change when selecting next option`);
    return false;
  }
  if (!restored) {
    console.log(`ERROR: ${name} did not restore to original value`);
    return false;
  }
  return true;
}

function processText() {
  const values = new Set();
  for (const window of app.windows()) {
    const elements = [];
    collectElements(window, elements);
    elements.flatMap(elementStrings).forEach(value => values.add(value));
  }
  return [...values].join('\n');
}

function findAdvancedButton(title) {
  pressSettingsTab('Advanced');
  let observedButtons = new Set();
  for (let pass = 0; pass < 12; pass += 1) {
    const currentWindow = settingsWindow();
    if (!currentWindow) {
      delay(0.15);
      continue;
    }
    const elements = [];
    collectElements(currentWindow, elements);
    const buttons = elements.filter(element => {
      let role = '';
      try { role = String(element.role()); } catch (e) {}
      return role === 'AXButton';
    });
    buttons.flatMap(elementStrings).forEach(value => observedButtons.add(value));
    const button = buttons.find(element => elementStrings(element).includes(title));
    if (button) return button;

    const scrollAreas = elements.filter(element => {
      try { return String(element.role()) === 'AXScrollArea'; } catch (e) { return false; }
    }).sort((lhs, rhs) => {
      try {
        const leftSize = lhs.size();
        const rightSize = rhs.size();
        return Number(rightSize[0]) * Number(rightSize[1]) - Number(leftSize[0]) * Number(leftSize[1]);
      } catch (e) { return 0; }
    });
    const scrollArea = scrollAreas[0] || null;
    const verticalScrollBar = elements.find(element => {
      try {
        if (String(element.role()) !== 'AXScrollBar') return false;
        const size = element.size();
        return Number(size[1]) > Number(size[0]);
      } catch (e) { return false; }
    });
    let scrolled = false;
    if (verticalScrollBar) {
      try {
        verticalScrollBar.value = 1;
        scrolled = true;
      } catch (e) {}
    }
    if (scrollArea) {
      try {
        scrollArea.actions.byName('AXScrollDownByPage').perform();
        scrolled = true;
      } catch (e) {}
      // SwiftUI may report a successful AX scroll action without moving its
      // lazily exposed content. A real pointer scroll keeps this deterministic.
      scrolled = cgScrollArea(scrollArea, -8) || scrolled;
    }
    if (!scrolled) exactKeyCode(121, currentWindow);
    delay(0.25);
  }
  throw new Error(`Advanced action button not found: ${title}; observed buttons: ${[...observedButtons].join(' | ')}`);
}

function verifyDestructiveCancel(buttonTitle, confirmationTitle, requiredMessage, destructiveLabel) {
  const button = findAdvancedButton(buttonTitle);
  button.actions.byName('AXPress').perform();

  let alertText = '';
  const deadline = Date.now() + 6000;
  while (Date.now() < deadline) {
    alertText = processText();
    if (
      alertText.includes(confirmationTitle) &&
      alertText.includes(requiredMessage) &&
      alertText.includes('Cancel') &&
      alertText.includes(destructiveLabel)
    ) break;
    delay(0.1);
  }
  if (
    !alertText.includes(confirmationTitle) ||
    !alertText.includes(requiredMessage) ||
    !alertText.includes('Cancel') ||
    !alertText.includes(destructiveLabel)
  ) {
    throw new Error(`Incomplete confirmation semantics for ${buttonTitle}: ${alertText}`);
  }

  exactKeyCode(53, settingsWindow()); // Escape must choose the safe cancel path.
  for (let attempt = 0; attempt < 40; attempt += 1) {
    delay(0.1);
    if (!processText().includes(confirmationTitle)) {
      console.log(`Confirmation ${confirmationTitle}: complete semantics and Escape cancellation PASS`);
      return;
    }
  }
  throw new Error(`Escape did not dismiss ${confirmationTitle}`);
}

let ok = true;
popups.forEach((popup, index) => {
  ok = validate(popupName(popup, index), togglePopupAndRestore(popup, index)) && ok;
});

if (!ok) {
  throw new Error('settings popup smoke failed');
}

verifyDestructiveCancel(
  'Clear All Article Cache',
  'Clear All Article Cache?',
  'including pinned saved/highlighted/tagged entries',
  'Clear'
);
verifyDestructiveCancel(
  'Reset All App Data',
  'Reset All App Data?',
  'This action cannot be undone.',
  'Reset'
);

win = settingsWindow();
if (!win) throw new Error('Settings disappeared before the close-window check');
try { win.actions.byName('AXRaise').perform(); } catch (e) {}
delay(0.15);
exactKeystroke('w', { using: 'command down' }, win);
for (let attempt = 0; attempt < 30 && settingsWindow(); attempt += 1) delay(0.1);
if (settingsWindow()) throw new Error('Command-W did not close the separate Settings window');
if (!app.windows().some(window => {
  try { return String(window.name()) === 'MacWiki'; } catch (e) { return false; }
})) {
  throw new Error('Closing Settings also closed or replaced the main MacWiki window');
}

console.log(`PASS: ${paneContracts.length} Settings panes exposed expected semantics; document commands were unavailable there; Command-W closed only Settings; ${sliders.length} native sliders exposed labels/values; ${popups.length} popup controls changed/restored; both destructive confirmations exposed complete semantics and cancelled with Escape.`);
JXA
