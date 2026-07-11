function safe(getter, fallback = null) {
    try {
        const value = getter();
        return value === undefined ? fallback : value;
    } catch (_) {
        return fallback;
    }
}

function identifier(element) {
    return safe(() => element.attributes.byName("AXIdentifier").value(), "");
}

function descendants(element, maximumDepth, depth = 0) {
    if (depth >= maximumDepth) {
        return [];
    }

    const children = safe(() => element.uiElements(), []);
    return children.flatMap(child => [child, ...descendants(child, maximumDepth, depth + 1)]);
}

function rowContainsIdentifier(row, predicate) {
    return [row, ...descendants(row, 4)].some(element => predicate(identifier(element)));
}

function rowContainsRole(row, targetRole) {
    return [row, ...descendants(row, 4)].some(element => safe(() => element.role(), "") === targetRole);
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
        const currentShellOutline = safe(
            () => window.groups[0].splitterGroups[0].groups[0].splitterGroups[0].groups[0].scrollAreas[0].outlines[0]
        );
        if (currentShellOutline) {
            const rows = safe(() => currentShellOutline.rows(), []);
            if (rows.some(row => rowContainsIdentifier(row, value => value === "sidebar-row-root-recents"))) {
                return currentShellOutline;
            }
        }

        const elements = [window, ...descendants(window, 9)];
        for (const element of elements) {
            if (safe(() => element.role(), "") !== "AXOutline") {
                continue;
            }

            const rows = safe(() => element.rows(), []);
            if (rows.some(row => rowContainsIdentifier(row, value => value === "sidebar-row-root-recents"))) {
                return element;
            }
        }
    }
    return null;
}

function run(argv) {
    const [appName, folderIdentifier] = argv;
    if (!appName || !folderIdentifier) {
        throw new Error("Usage: qa_sidebar_row_centers.js APP_NAME FOLDER_IDENTIFIER");
    }

    const systemEvents = Application("System Events");
    const deadline = Date.now() + 20_000;
    let lastDiagnostic = "process not observed";
    let folderCenter = null;
    let listCenter = null;

    while (Date.now() < deadline) {
        const process = systemEvents.processes.byName(appName);
        const processExists = safe(() => process.exists(), false);
        if (processExists) {
            const outline = sidebarOutline(process);
            if (outline) {
                const rows = outline.rows();
                const folderRow = rows.find(row => rowContainsIdentifier(row, value => value === folderIdentifier))
                    || rows.find(row => rowContainsRole(row, "AXDisclosureTriangle"));
                const listRow = rows.find(row => rowContainsIdentifier(row, value => value.startsWith("sidebar-row-list-")));
                if (folderRow) {
                    folderCenter = center(folderRow);
                }
                if (listRow) {
                    listCenter = center(listRow);
                }
                const identifiers = rows.map(row =>
                    [row, ...descendants(row, 4)].map(identifier).filter(Boolean).join("|")
                );
                lastDiagnostic = `rows=${rows.length}, folder=${Boolean(folderCenter)}, list=${Boolean(listCenter)}, identifiers=${identifiers.join(",")}`;
                if (folderCenter && listCenter) {
                    return [...listCenter, ...folderCenter].join(" ");
                }
            } else {
                lastDiagnostic = `windows=${safe(() => process.windows().length, 0)}, sidebar outline not found`;
            }
        } else {
            lastDiagnostic = "process exists=false";
        }
        delay(0.1);
    }

    throw new Error(`Timed out waiting for dynamic sidebar rows in ${appName}: ${lastDiagnostic}`);
}
