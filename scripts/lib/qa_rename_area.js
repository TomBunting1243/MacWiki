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

function sidebarOutline(process) {
    for (const window of safe(() => process.windows(), [])) {
        const outline = safe(
            () => window.groups[0].splitterGroups[0].groups[0].splitterGroups[0].groups[0].scrollAreas[0].outlines[0]
        );
        if (outline) {
            return outline;
        }
    }
    return null;
}

function findAreaRow(process, areaIdentifier) {
    const outline = sidebarOutline(process);
    if (!outline) {
        return null;
    }
    return safe(() => outline.rows(), []).find(row =>
        [row, ...descendants(row, 4)].some(element => identifier(element) === areaIdentifier)
    ) || null;
}

function actionNames(element) {
    return safe(() => element.actions().map(action => action.name()), []);
}

function showContextMenu(row) {
    const target = [row, ...descendants(row, 4)].find(element => actionNames(element).includes("AXShowMenu"));
    if (!target) {
        throw new Error("Nested folder row did not expose AXShowMenu");
    }
    target.actions.byName("AXShowMenu").perform();
}

function menuItems(row) {
    return descendants(row, 7).filter(element => safe(() => element.role(), "") === "AXMenuItem");
}

function menuItemTitle(item) {
    return safe(() => item.title(), safe(() => item.name(), safe(() => item.description(), "")));
}

function chooseRename(row, systemEvents) {
    const deadline = Date.now() + 4_000;
    while (Date.now() < deadline) {
        for (const item of menuItems(row)) {
            if (menuItemTitle(item) === "Rename") {
                try {
                    item.actions.byName("AXPress").perform();
                } catch (_) {
                    item.click();
                }
                return;
            }
        }
        delay(0.05);
    }

    // Rename is intentionally the first action in AreaRowView's context menu.
    systemEvents.keyCode(36);
}

function renameSheetField(process) {
    for (const window of safe(() => process.windows(), [])) {
        for (const sheet of safe(() => window.sheets(), [])) {
            const field = [sheet, ...descendants(sheet, 6)].find(element => safe(() => element.role(), "") === "AXTextField");
            if (field) {
                return field;
            }
        }
    }
    return null;
}

function run(argv) {
    const [appName, areaIdentifier, renamedName] = argv;
    if (!appName || !areaIdentifier || !renamedName) {
        throw new Error("Usage: qa_rename_area.js APP_NAME AREA_IDENTIFIER RENAMED_NAME");
    }

    const systemEvents = Application("System Events");
    const process = systemEvents.processes.byName(appName);
    process.frontmost = true;

    const row = (() => {
        const deadline = Date.now() + 10_000;
        while (Date.now() < deadline) {
            const candidate = findAreaRow(process, areaIdentifier);
            if (candidate) {
                return candidate;
            }
            delay(0.1);
        }
        throw new Error(`Nested folder row was not visible: ${areaIdentifier}`);
    })();

    showContextMenu(row);
    chooseRename(row, systemEvents);

    const field = (() => {
        const deadline = Date.now() + 8_000;
        while (Date.now() < deadline) {
            const candidate = renameSheetField(process);
            if (candidate) {
                return candidate;
            }
            delay(0.05);
        }
        const visibleMenuItems = menuItems(row).map(menuItemTitle).filter(Boolean);
        throw new Error(`Rename sheet did not appear; visible menu items=${visibleMenuItems.join("|") || "none"}`);
    })();

    field.value = renamedName;
    systemEvents.keyCode(36);
    return `renamed ${areaIdentifier}`;
}
