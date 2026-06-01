#!/usr/bin/env bash

set -euo pipefail

APP_NAME="${APP_NAME:-MacWiki}"

echo "Running Settings popups smoke QA..."

osascript -l JavaScript <<'JXA'
ObjC.import('stdlib');

const se = Application('System Events');
const appName = ObjC.unwrap($.getenv('APP_NAME')) || 'MacWiki';
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
      const value = String(read());
      if (value.length > 0) return value;
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
  ok = validate(popupName(popup, index), togglePopupDownUp(popup)) && ok;
});

if (!ok) {
  throw new Error('settings popup smoke failed');
}

console.log(`PASS: ${popups.length} Settings popup controls changed and restored successfully.`);
JXA
