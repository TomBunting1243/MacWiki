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

function rowContainsIdentifier(row, targetIdentifier) {
    return [row, ...descendants(row, 4)].some(element => identifier(element) === targetIdentifier);
}

function elementWithRole(row, role) {
    return [row, ...descendants(row, 4)].find(element => safe(() => element.role(), "") === role) || null;
}

function center(row) {
    const position = row.position();
    const size = row.size();
    return [
        Math.round(position[0] + size[0] / 2),
        Math.round(position[1] + size[1] / 2),
    ];
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

function rows(process) {
    const outline = sidebarOutline(process);
    return outline ? safe(() => outline.rows(), []) : [];
}

function findRow(process, targetIdentifier) {
    return rows(process).find(row => rowContainsIdentifier(row, targetIdentifier)) || null;
}

function performPress(element) {
    try {
        element.actions.byName("AXPress").perform();
        return;
    } catch (_) {
        // Fall through to System Events' click command for proxy differences.
    }
    Application("System Events").click(element);
}

function ensureExpanded(process, parentIdentifier) {
    const parentRow = findRow(process, parentIdentifier);
    if (!parentRow) {
        return false;
    }
    const disclosure = elementWithRole(parentRow, "AXDisclosureTriangle");
    if (!disclosure) {
        return false;
    }
    if (Number(safe(() => disclosure.value(), 0)) === 0) {
        performPress(disclosure);
        delay(0.2);
    }
    return true;
}

function diagnostics(process) {
    return rows(process).map(row =>
        [row, ...descendants(row, 4)].map(identifier).filter(Boolean).join("|")
    ).join(",");
}

function run(argv) {
    const [mode, appName, firstIdentifier, secondIdentifier] = argv;
    if (!["pair", "nested"].includes(mode) || !appName || !firstIdentifier || !secondIdentifier) {
        throw new Error("Usage: qa_area_row_centers.js pair|nested APP_NAME FIRST_IDENTIFIER SECOND_IDENTIFIER");
    }

    const process = Application("System Events").processes.byName(appName);
    const deadline = Date.now() + 20_000;
    let firstCenter = null;
    let secondCenter = null;

    while (Date.now() < deadline) {
        if (mode === "nested") {
            ensureExpanded(process, firstIdentifier);
            const childRow = findRow(process, secondIdentifier);
            if (childRow) {
                return center(childRow).join(" ");
            }
        } else {
            const firstRow = findRow(process, firstIdentifier);
            const secondRow = findRow(process, secondIdentifier);
            if (firstRow) {
                firstCenter = center(firstRow);
            }
            if (secondRow) {
                secondCenter = center(secondRow);
            }
            if (firstCenter && secondCenter) {
                return [...firstCenter, ...secondCenter].join(" ");
            }
        }
        delay(0.1);
    }

    throw new Error(`Timed out resolving ${mode} area rows in ${appName}: ${diagnostics(process)}`);
}
