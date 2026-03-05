#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP_NAME:-MacWiki}"

echo "Running Settings popups smoke QA..."

osascript -l JavaScript <<'JXA'
const se = Application('System Events');
const appName = 'MacWiki';
const app = se.processes.byName(appName);

if (!app.exists()) {
  console.log('ERROR: app process not found: ' + appName);
  throw new Error('app process missing');
}

function settingsWindow() {
  for (const w of app.windows()) {
    let name = '';
    try { name = w.name(); } catch (e) {}
    if (String(name).toLowerCase().includes('settings')) {
      return w;
    }
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

function togglePopupDownUp(popup) {
  const before = popupValue(popup);
  popup.actions.byName('AXPress').perform();
  delay(0.15);
  se.keyCode(125); // down arrow
  delay(0.05);
  se.keyCode(36); // return
  delay(0.20);
  const changed = popupValue(popup);

  popup.actions.byName('AXPress').perform();
  delay(0.15);
  se.keyCode(126); // up arrow
  delay(0.05);
  se.keyCode(36); // return
  delay(0.20);
  const after = popupValue(popup);

  return { before, changed, after };
}

app.frontmost = true;
let win = settingsWindow();
if (!win) {
  se.keystroke(',', { using: 'command down' });
  delay(0.45);
  win = settingsWindow();
}
if (!win) {
  console.log('ERROR: settings window not found');
  throw new Error('settings window missing');
}

const popups = [];
for (const g of win.groups()) collectPopups(g, popups);
if (popups.length < 4) {
  console.log('ERROR: expected >=4 popups, found ' + popups.length);
  throw new Error('insufficient popup controls');
}

// Popup order in this UI:
// [0] Font, [1] Discover Button Opens, [2] Search Presentation, [3] Recents Shows
const discover = togglePopupDownUp(popups[1]);
const search = togglePopupDownUp(popups[2]);
const recents = togglePopupDownUp(popups[3]);

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
ok = validate('Discover Button Opens', discover) && ok;
ok = validate('Search Presentation', search) && ok;
ok = validate('Recents Shows', recents) && ok;

if (!ok) {
  throw new Error('settings popup smoke failed');
}

console.log('PASS: Settings popup controls changed and restored successfully.');
JXA
