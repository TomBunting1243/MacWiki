(function () {
    'use strict';

    const wrapperClass = 'macwiki-table-scroll';
    const dataTableClass = 'macwiki-reader-data-table';
    const overflowTolerance = 1;
    const dataTableSelector =
        'table:not(:is(.infobox, .infobox-full-data, .pcs-table-infobox))';
    const skipContainerSelector = [
        '.infobox',
        '.infobox-full-data',
        '.pcs-collapse-table-container',
        '.pcs-collapse-table-content',
        '.pcs-table-infobox',
        '.pcs-table-other',
        '.pcs-table-scroll',
        '.pcs-horizontal-scroll',
        '.mw-table-scroll'
    ].join(', ');

    function normalizedLabel(value) {
        return (value || '').replace(/\s+/g, ' ').trim();
    }

    function accessibleLabel(table) {
        const caption = table.querySelector('caption');
        const captionText = normalizedLabel(caption && caption.textContent);
        if (captionText) {
            return `Scrollable table: ${captionText}`;
        }

        const authoredLabel = normalizedLabel(table.getAttribute('aria-label'));
        if (authoredLabel) {
            return `Scrollable table: ${authoredLabel}`;
        }

        return 'Scrollable data table';
    }

    function updateOverflowAccessibility(wrapper, table, label) {
        const overflows = table.scrollWidth > wrapper.clientWidth + overflowTolerance;
        wrapper.classList.toggle('macwiki-table-scroll--overflowing', overflows);

        if (overflows) {
            wrapper.dataset.macwikiTableOverflow = 'true';
            wrapper.tabIndex = 0;
            wrapper.setAttribute('role', 'region');
            wrapper.setAttribute('aria-label', label);
        } else {
            delete wrapper.dataset.macwikiTableOverflow;
            wrapper.removeAttribute('tabindex');
            wrapper.removeAttribute('role');
            wrapper.removeAttribute('aria-label');
        }
    }

    function observeOverflow(wrapper, table, label) {
        let frameID = 0;
        const scheduleUpdate = function () {
            if (frameID) {
                window.cancelAnimationFrame(frameID);
            }
            frameID = window.requestAnimationFrame(function () {
                frameID = 0;
                updateOverflowAccessibility(wrapper, table, label);
            });
        };

        scheduleUpdate();

        if (typeof ResizeObserver === 'function') {
            const observer = new ResizeObserver(scheduleUpdate);
            observer.observe(wrapper);
            observer.observe(table);
        } else {
            window.addEventListener('resize', scheduleUpdate, { passive: true });
        }
    }

    function shouldSkip(table) {
        return !table.matches(dataTableSelector) ||
            table.closest(skipContainerSelector) !== null ||
            table.parentElement?.classList.contains(wrapperClass);
    }

    function wrapTable(table) {
        if (shouldSkip(table) || !table.parentNode) {
            return;
        }

        table.classList.add(dataTableClass);
        const wrapper = document.createElement('div');
        wrapper.className = wrapperClass;
        wrapper.dir = 'auto';
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
})();
