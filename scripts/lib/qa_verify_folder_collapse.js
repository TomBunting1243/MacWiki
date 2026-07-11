function safe(getter, fallback = null) {
    try {
        const value = getter();
        return value === undefined ? fallback : value;
    } catch (_) {
        return fallback;
    }
}

function descendants(element, maximumDepth, depth = 0) {
    if (depth >= maximumDepth) {
        return [];
    }
    const children = safe(() => element.uiElements(), []);
    return children.flatMap(child => [child, ...descendants(child, maximumDepth, depth + 1)]);
}

function identifier(element) {
    return safe(() => element.attributes.byName("AXIdentifier").value(), "");
}

function rowContainsIdentifier(row, predicate) {
    return [row, ...descendants(row, 4)].some(element => predicate(identifier(element)));
}

function elementWithRole(row, role) {
    return [row, ...descendants(row, 4)].find(element => safe(() => element.role(), "") === role) || null;
}

function attribute(element, name, fallback = null) {
    return safe(() => element.attributes.byName(name).value(), fallback);
}

function sidebarOutline(process) {
    for (const window of safe(() => process.windows(), [])) {
        const outline = safe(
            () => window.groups[0].splitterGroups[0].groups[0].splitterGroups[0].groups[0].scrollAreas[0].outlines[0]
        );
        if (!outline) {
            continue;
        }
        const rows = safe(() => outline.rows(), []);
        if (rows.some(row => rowContainsIdentifier(row, value => value === "sidebar-row-root-recents"))) {
            return outline;
        }
    }
    return null;
}

function rows(process) {
    const outline = sidebarOutline(process);
    return outline ? safe(() => outline.rows(), []) : [];
}

function findFolderRow(process, folderIdentifier) {
    const currentRows = rows(process);
    return currentRows.find(row => rowContainsIdentifier(row, value => value === folderIdentifier))
        || currentRows.find(row => elementWithRole(row, "AXDisclosureTriangle"))
        || null;
}

function findListRow(process, listIdentifier = null) {
    return rows(process).find(row => rowContainsIdentifier(row, value =>
        listIdentifier ? value === listIdentifier : value.startsWith("sidebar-row-list-")
    )) || null;
}

function listIdentifier(row) {
    const element = [row, ...descendants(row, 4)].find(candidate => identifier(candidate).startsWith("sidebar-row-list-"));
    return element ? identifier(element) : null;
}

function performPress(element) {
    try {
        element.actions.byName("AXPress").perform();
        return;
    } catch (_) {
        // JXA action proxies do not reliably implement exists(); invoke first.
    }
    try {
        element.click();
        return;
    } catch (_) {
        // SwiftUI-hosted elements may expose click only through System Events.
    }
    try {
        Application("System Events").click(element);
        return;
    } catch (_) {
        // Fall through to an evidence-rich error.
    }
    throw new Error(`Element has no AXPress action: ${safe(() => element.role(), "unknown role")}`);
}

function waitUntil(predicate, timeoutSeconds, failureMessage) {
    const deadline = Date.now() + timeoutSeconds * 1_000;
    while (Date.now() < deadline) {
        const result = predicate();
        if (result) {
            return result;
        }
        delay(0.1);
    }
    throw new Error(failureMessage);
}

function disclosureState(folderRow) {
    const disclosure = elementWithRole(folderRow, "AXDisclosureTriangle");
    if (!disclosure) {
        return null;
    }
    const value = attribute(disclosure, "AXValue");
    return Number(value) !== 0;
}

function ensureExpanded(process, folderIdentifier, desiredState, failureMessage) {
    const deadline = Date.now() + 8_000;
    while (Date.now() < deadline) {
        const folderRow = findFolderRow(process, folderIdentifier);
        if (folderRow) {
            const state = disclosureState(folderRow);
            if (state === desiredState) {
                return;
            }
            const disclosure = elementWithRole(folderRow, "AXDisclosureTriangle");
            if (disclosure) {
                performPress(disclosure);
                delay(0.2);
            }
        }
        delay(0.1);
    }
    throw new Error(failureMessage);
}

function rowIsSelected(row) {
    if (attribute(row, "AXSelected", false) === true) {
        return true;
    }
    return [row, ...descendants(row, 4)].some(element => attribute(element, "AXValue", "") === "Selected");
}

function rowDiagnostics(process) {
    return rows(process).map((row, index) => {
        const elements = [row, ...descendants(row, 4)];
        const roles = elements.map(element => safe(() => element.role(), "")).filter(Boolean);
        const identifiers = elements.map(identifier).filter(Boolean);
        const values = elements.map(element => attribute(element, "AXValue", "")).filter(value => value !== "");
        return `${index}:${roles.join("|")}:${identifiers.join("|")}:selected=${attribute(row, "AXSelected", false)}:values=${values.join("|")}`;
    }).join(", ");
}

function run(argv) {
    const [appName, folderIdentifier] = argv;
    if (!appName || !folderIdentifier) {
        throw new Error("Usage: qa_verify_folder_collapse.js APP_NAME FOLDER_IDENTIFIER");
    }

    const systemEvents = Application("System Events");
    const process = systemEvents.processes.byName(appName);
    waitUntil(() => safe(() => process.exists(), false) && sidebarOutline(process), 10, "MacWiki content window was not available");

    ensureExpanded(process, folderIdentifier, true, "Could not ensure folder was expanded before selection");
    let initialListRow;
    try {
        initialListRow = waitUntil(() => findListRow(process), 10, "Moved list was not visible inside the expanded folder");
    } catch (error) {
        throw new Error(`${error.message}; rows=${rowDiagnostics(process)}`);
    }
    const runtimeListIdentifier = listIdentifier(initialListRow);
    if (!runtimeListIdentifier) {
        throw new Error("Moved list did not expose a stable accessibility identifier");
    }

    const listButton = [initialListRow, ...descendants(initialListRow, 4)].find(element => identifier(element) === runtimeListIdentifier);
    performPress(listButton || initialListRow);
    waitUntil(() => {
        const row = findListRow(process, runtimeListIdentifier);
        return row && rowIsSelected(row);
    }, 5, "List did not become selected before collapse");

    ensureExpanded(process, folderIdentifier, false, "Could not collapse folder");
    waitUntil(() => !findListRow(process, runtimeListIdentifier), 5, "Selected child list stayed visible after folder collapse");
    try {
        waitUntil(() => {
            const recentsRow = rows(process).find(row => rowContainsIdentifier(row, value => value === "sidebar-row-root-recents"));
            return recentsRow && rowIsSelected(recentsRow);
        }, 5, "Selection did not fall back to Recents after folder collapse");
    } catch (error) {
        throw new Error(`${error.message}; rows=${rowDiagnostics(process)}`);
    }

    ensureExpanded(process, folderIdentifier, true, "Could not re-expand folder");
    waitUntil(() => findListRow(process, runtimeListIdentifier), 5, "Child list did not return after re-expanding folder");
    ensureExpanded(process, folderIdentifier, false, "Folder stopped responding after first re-expand");
    ensureExpanded(process, folderIdentifier, true, "Folder stopped responding after second expand");
    waitUntil(() => findListRow(process, runtimeListIdentifier), 5, "Child list did not return after repeated disclosure toggles");

    return `verified ${runtimeListIdentifier}`;
}
