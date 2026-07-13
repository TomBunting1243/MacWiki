#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP_NAME:-MacWiki}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"
APP_BIN_DEFAULT="$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki"
APP_BIN_FALLBACK="$REPO_ROOT/.build/debug/MacWiki"
APP_BIN="${APP_BIN:-$APP_BIN_DEFAULT}"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/settings-popups-home-$(date +%Y%m%d_%H%M%S)-$RANDOM}"

if [[ ! -x "$APP_BIN" && -x "$APP_BIN_FALLBACK" ]]; then
  APP_BIN="$APP_BIN_FALLBACK"
fi
if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: App binary not found: $APP_BIN" >&2
  exit 1
fi

qa_prepare_isolated_home
cleanup() {
  qa_stop_exact
  qa_remove_isolated_home
}
trap cleanup EXIT INT TERM
qa_launch_exact_bundle "/tmp/macwiki-qa-settings-popups-launch.log"

echo "Running Settings popups smoke QA..."

APP_NAME="$APP_NAME" APP_PID="$QA_APP_PID" SCRIPT_DIR="$SCRIPT_DIR" osascript -l JavaScript <<'JXA'
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

function settingsWindow() {
  const windows = app.windows();
  for (const w of windows) {
    let name = '';
    try { name = w.name(); } catch (e) {}
    const normalizedName = String(name).toLowerCase();
    if (normalizedName.includes('settings') || ['reading', 'library', 'navigation', 'chrome', 'advanced'].includes(normalizedName)) {
      return w;
    }
  }
  if (windows.length > 1) {
    for (const w of windows) {
      let name = '';
      try { name = String(w.name()); } catch (e) {}
      if (name !== 'MacWiki') {
        return w;
      }
    }
    return windows[0];
  }
  return null;
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
          let windowName = '';
          try { windowName = String(refreshed.name()); } catch (e) {}
          if (windowName.toLowerCase() === title.toLowerCase()) return refreshed;
        }
      }
    }
    delay(0.1);
  }
  throw new Error(`Settings tab did not become active: ${title}`);
}

function auditSettingsPane(title, expectedStrings) {
  pressSettingsTab(title);
  delay(0.4);
  const observedStrings = new Set();
  let interactiveCount = 0;
  let scrollArea = null;
  let verticalScrollBar = null;
  for (let pass = 0; pass < 10; pass += 1) {
    const currentWindow = settingsWindow();
    if (!currentWindow) {
      delay(0.2);
      continue;
    }
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
    if (!scrolled) se.keyCode(121); // Page Down
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
    se.keyCode(53);
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
    app.frontmost = true;
    se.keystroke(',', { using: 'command down' });
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
  ['Reading', ['Font', 'Font Size', 'Line Height', 'Paragraph Spacing', 'Content Width', 'Side Margin', 'Heading Scale', 'Immediate Reveal']],
  ['Library', ['Sidebar Sort', 'Default Save List', 'Label Display', 'Highlight Marker']],
  ['Navigation', ['Discover', 'Discover Button Opens', 'Recents', 'Recents Shows']],
  ['Chrome', ['Chrome', 'Use translucent Liquid Glass treatment']],
  ['Advanced', ['Advanced', 'Experimental features, cache maintenance', 'In-Memory', 'Disk', 'Pinned on Disk', 'Performance samples appear here']]
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

let ok = true;
popups.forEach((popup, index) => {
  ok = validate(popupName(popup, index), togglePopupAndRestore(popup, index)) && ok;
});

if (!ok) {
  throw new Error('settings popup smoke failed');
}

console.log(`PASS: ${paneContracts.length} Settings panes exposed expected semantics; ${sliders.length} native sliders exposed labels/values and ${popups.length} popup controls changed/restored.`);
JXA
