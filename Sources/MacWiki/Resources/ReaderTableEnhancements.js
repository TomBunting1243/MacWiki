(function () {
    'use strict';

    const wrapperClass = 'macwiki-table-scroll';
    const dataTableClass = 'macwiki-reader-data-table';
    const overflowTolerance = 1;
    const dataTableSelector =
        'table:not(:is(.infobox, .infobox-full-data, .pcs-table-infobox, ' +
        '[role="presentation"], [role="none"]))';
    const skipContainerSelector = [
        '.infobox',
        '.infobox-full-data',
        '.pcs-collapse-table-container',
        '.pcs-collapse-table-content',
        '.pcs-table-infobox',
        '.pcs-table-other',
        '.pcs-table-scroll',
        '.pcs-horizontal-scroll',
        '.mw-table-scroll',
        '.macwiki-table-scroll'
    ].join(', ');
    const authoredSurfaceSelector = [
        'tr[bgcolor]',
        'th[bgcolor]',
        'td[bgcolor]',
        'tr[style*="background" i]',
        'th[style*="background" i]',
        'td[style*="background" i]'
    ].join(', ');
    const observedRecords = new Set();
    const observedTargets = new WeakMap();
    const pendingRecords = new Set();
    let sharedResizeObserver = null;
    let fallbackResizeListenerInstalled = false;
    let overflowFrameID = 0;

    function normalizedLabel(value) {
        return (value || '').replace(/\s+/g, ' ').trim();
    }

    function accessibleLabel(table) {
        const caption = table.querySelector('caption');
        const captionText = normalizedLabel(caption && caption.textContent);
        if (captionText) {
            return `Scrollable table: ${captionText}`;
        }

        const labelledBy = normalizedLabel(table.getAttribute('aria-labelledby'));
        if (labelledBy) {
            const referencedText = normalizedLabel(
                labelledBy
                    .split(' ')
                    .map(function (id) {
                        return document.getElementById(id)?.textContent || '';
                    })
                    .join(' ')
            );
            if (referencedText) {
                return `Scrollable table: ${referencedText}`;
            }
        }

        const authoredLabel = normalizedLabel(table.getAttribute('aria-label'));
        if (authoredLabel) {
            return `Scrollable table: ${authoredLabel}`;
        }

        const sectionHeading = table.closest('section')?.querySelector(
            'h1, h2, h3, h4, h5, h6'
        );
        const sectionHeadingText = normalizedLabel(sectionHeading?.textContent);
        if (sectionHeadingText) {
            return `Scrollable table in ${sectionHeadingText}`;
        }

        return 'Scrollable data table';
    }

    function parsedRGBColor(value) {
        if (!value || !value.toLowerCase().startsWith('rgb')) {
            return null;
        }

        const components = value.match(/[\d.]+/g);
        if (!components || components.length < 3) {
            return null;
        }

        const red = Number(components[0]);
        const green = Number(components[1]);
        const blue = Number(components[2]);
        const alpha = components.length > 3 ? Number(components[3]) : 1;
        if (![red, green, blue, alpha].every(Number.isFinite) || alpha < 0.9) {
            return null;
        }

        return [red, green, blue];
    }

    function linearizedColorComponent(component) {
        const value = Math.min(Math.max(component / 255, 0), 1);
        return value <= 0.04045
            ? value / 12.92
            : Math.pow((value + 0.055) / 1.055, 2.4);
    }

    function relativeLuminance(color) {
        return (0.2126 * linearizedColorComponent(color[0])) +
            (0.7152 * linearizedColorComponent(color[1])) +
            (0.0722 * linearizedColorComponent(color[2]));
    }

    function classifyAuthoredSurfaces(table) {
        const classifications = [];

        // Keep computed-style reads together so class writes do not repeatedly invalidate layout.
        table.querySelectorAll(authoredSurfaceSelector).forEach(function (surface) {
            if (surface.closest('table') !== table) {
                return;
            }
            const color = parsedRGBColor(
                window.getComputedStyle(surface).backgroundColor
            );
            if (color) {
                classifications.push({
                    surface,
                    usesDarkForeground: relativeLuminance(color) > 0.179
                });
            }
        });

        classifications.forEach(function (classification) {
            classification.surface.classList.toggle(
                'macwiki-authored-light-surface',
                classification.usesDarkForeground
            );
            classification.surface.classList.toggle(
                'macwiki-authored-dark-surface',
                !classification.usesDarkForeground
            );
        });
    }

    function restoreAttribute(element, name, originalValue) {
        if (originalValue === null) {
            element.removeAttribute(name);
        } else {
            element.setAttribute(name, originalValue);
        }
    }

    function updateOverflowAccessibility(record, overflows) {
        const { wrapper, label } = record;
        wrapper.classList.toggle('macwiki-table-scroll--overflowing', overflows);

        if (overflows) {
            wrapper.dataset.macwikiTableOverflow = 'true';
            wrapper.tabIndex = 0;
            if (record.originalRole === null) {
                wrapper.setAttribute('role', 'group');
            }
            if (record.originalAriaLabel === null && record.originalAriaLabelledBy === null) {
                wrapper.setAttribute('aria-label', label);
            }
        } else {
            delete wrapper.dataset.macwikiTableOverflow;
            if (record.originalTabIndex === null) {
                wrapper.removeAttribute('tabindex');
            } else {
                restoreAttribute(wrapper, 'tabindex', record.originalTabIndex);
            }
            restoreAttribute(wrapper, 'role', record.originalRole);
            restoreAttribute(wrapper, 'aria-label', record.originalAriaLabel);
        }
    }

    function scheduleOverflowUpdate(record) {
        pendingRecords.add(record);
        if (overflowFrameID) {
            return;
        }

        overflowFrameID = window.requestAnimationFrame(function () {
            overflowFrameID = 0;
            const measurements = [];
            pendingRecords.forEach(function (pendingRecord) {
                measurements.push({
                    record: pendingRecord,
                    overflows: pendingRecord.table.scrollWidth >
                        pendingRecord.wrapper.clientWidth + overflowTolerance
                });
            });
            pendingRecords.clear();

            measurements.forEach(function (measurement) {
                updateOverflowAccessibility(measurement.record, measurement.overflows);
            });
        });
    }

    function scheduleAllOverflowUpdates() {
        observedRecords.forEach(scheduleOverflowUpdate);
    }

    function ensureObservationInfrastructure() {
        if (typeof ResizeObserver === 'function') {
            if (!sharedResizeObserver) {
                sharedResizeObserver = new ResizeObserver(function (entries) {
                    const scheduledRecords = new Set();
                    entries.forEach(function (entry) {
                        const record = observedTargets.get(entry.target);
                        if (record && !scheduledRecords.has(record)) {
                            scheduledRecords.add(record);
                            scheduleOverflowUpdate(record);
                        }
                    });
                });
            }
            return;
        }

        if (!fallbackResizeListenerInstalled) {
            window.addEventListener('resize', scheduleAllOverflowUpdates, { passive: true });
            fallbackResizeListenerInstalled = true;
        }
    }

    function observeOverflow(wrapper, table, label) {
        const record = {
            wrapper,
            table,
            label,
            originalTabIndex: wrapper.getAttribute('tabindex'),
            originalRole: wrapper.getAttribute('role'),
            originalAriaLabel: wrapper.getAttribute('aria-label'),
            originalAriaLabelledBy: wrapper.getAttribute('aria-labelledby')
        };
        observedRecords.add(record);
        observedTargets.set(wrapper, record);
        observedTargets.set(table, record);
        scheduleOverflowUpdate(record);
        ensureObservationInfrastructure();

        if (sharedResizeObserver) {
            sharedResizeObserver.observe(wrapper);
            sharedResizeObserver.observe(table);
        }
    }

    function disconnectObservers() {
        if (sharedResizeObserver) {
            sharedResizeObserver.disconnect();
            sharedResizeObserver = null;
        }
        if (fallbackResizeListenerInstalled) {
            window.removeEventListener('resize', scheduleAllOverflowUpdates);
            fallbackResizeListenerInstalled = false;
        }
        if (overflowFrameID) {
            window.cancelAnimationFrame(overflowFrameID);
            overflowFrameID = 0;
        }
        pendingRecords.clear();
        observedRecords.clear();
    }

    function handlePageHide(event) {
        if (!event.persisted) {
            disconnectObservers();
        }
    }

    function shouldSkip(table) {
        return !table.matches(dataTableSelector) ||
            table.closest(skipContainerSelector) !== null ||
            table.parentElement?.closest('table, .macwiki-table-scroll') !== null;
    }

    function wrapTable(table) {
        if (shouldSkip(table) || !table.parentNode) {
            return;
        }

        table.classList.add(dataTableClass);
        classifyAuthoredSurfaces(table);
        const wrapper = document.createElement('div');
        wrapper.className = wrapperClass;
        const authoredDirection = table.getAttribute('dir');
        if (authoredDirection) {
            wrapper.setAttribute('dir', authoredDirection);
        }
        table.parentNode.insertBefore(wrapper, table);
        wrapper.appendChild(table);
        observeOverflow(wrapper, table, accessibleLabel(table));
    }

    function enhanceReaderTables() {
        document.querySelectorAll('table').forEach(wrapTable);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', enhanceReaderTables, { once: true });
    } else {
        enhanceReaderTables();
    }
    window.addEventListener('pagehide', handlePageHide);
})();
