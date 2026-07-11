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

APP_NAME="$APP_NAME" APP_PID="$QA_APP_PID" osascript -l JavaScript <<'JXA'
ObjC.import('stdlib');

const se = Application('System Events');
const appName = ObjC.unwrap($.getenv('APP_NAME')) || 'MacWiki';
const appPid = Number(ObjC.unwrap($.getenv('APP_PID')) || '0');
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
    if (String(name).toLowerCase().includes('settings')) {
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

function popupValue(popup) {
  try { return String(popup.value()); } catch (e) { return ''; }
}

function togglePopupAndRestore(popup, popupIndex) {
  const before = popupValue(popup);
  popup.actions.byName('AXPress').perform();
  delay(0.15);
  let changedByName = false;
  try {
    const menus = popup.menus();
    if (menus.length > 0) {
      for (const item of menus[0].menuItems()) {
        let itemName = '';
        try { itemName = String(item.name()); } catch (e) {}
        if (itemName.length > 0 && itemName !== before) {
          item.actions.byName('AXPress').perform();
          changedByName = true;
          break;
        }
      }
    }
  } catch (e) {}
  if (!changedByName) {
    se.keyCode(53); // escape when no alternate item is available
  }
  delay(0.20);
  const changed = popupValue(popup);

  const refreshedPopups = [];
  collectPopups(settingsWindow(), refreshedPopups);
  const restorePopup = refreshedPopups[popupIndex] || popup;
  restorePopup.actions.byName('AXPress').perform();
  delay(0.15);
  let restoredByName = false;
  const restoreCandidates = [];
  try {
    const menus = restorePopup.menus();
    if (menus.length > 0) {
      for (const item of menus[0].menuItems()) {
        let itemName = '';
        try { itemName = String(item.name()); } catch (e) {}
        restoreCandidates.push(itemName);
        if (itemName === before) {
          item.actions.byName('AXPress').perform();
          restoredByName = true;
          break;
        }
      }
    }
  } catch (e) {}
  if (!restoredByName) {
    console.log(`Restore candidates for '${before}': ${restoreCandidates.join(' | ')}`);
    se.keyCode(53); // escape without committing another value
  }
  delay(0.20);
  const after = popupValue(restorePopup);

  return { before, changed, after };
}

app.frontmost = true;
let win = settingsWindow();
if (!win) {
  se.keystroke(',', { using: 'command down' });
  for (let attempt = 0; attempt < 12 && !win; attempt += 1) {
    delay(0.25);
    win = settingsWindow();
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

console.log(`PASS: ${popups.length} Settings popup controls changed and restored successfully.`);
JXA
