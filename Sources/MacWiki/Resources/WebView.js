// Link Clicks (Native 'while' loop approach)
function isCitationLink(target, resolvedURL) {
    if (!resolvedURL) return false;
    var hash = resolvedURL.hash || '';
    if (hash.indexOf('#cite_note-') === 0 || hash.indexOf('#cite_ref-') === 0) {
        return true;
    }
    if (target && target.closest) {
        if (target.closest('sup.mw-ref')) return true;
        if (target.closest('a.reference-link')) return true;
    }
    return false;
}

function isMediaLinkTarget(anchor, node) {
    if (!anchor) return false;
    if (anchor.classList && anchor.classList.contains('image')) {
        return true;
    }

    var element = node;
    if (element && element.nodeType !== Node.ELEMENT_NODE) {
        element = element.parentElement || null;
    }
    if (!element || !element.closest) return false;

    var imageAnchor = element.closest('a.image');
    if (imageAnchor === anchor) {
        return true;
    }

    var mediaNode = element.closest('img, picture, figure, video, audio, source');
    if (mediaNode && anchor.contains(mediaNode)) {
        return true;
    }

    var mediaContainer = element.closest('.mw-file-element, .thumb, .gallerybox');
    return !!(mediaContainer && anchor.contains(mediaContainer));
}

function normalizedHashIdentifier(hash) {
    if (!hash) return null;
    var rawIdentifier = hash.replace(/^#/, '');
    if (!rawIdentifier) return null;
    try {
        return decodeURIComponent(rawIdentifier);
    } catch (_) {
        return rawIdentifier;
    }
}

function resolveCitationReferenceId(target, resolvedURL) {
    if (!resolvedURL) return null;
    var hashIdentifier = normalizedHashIdentifier(resolvedURL.hash || '');
    if (!hashIdentifier) return null;

    if (hashIdentifier.indexOf('cite_note-') === 0) {
        return hashIdentifier;
    }

    if (hashIdentifier.indexOf('cite_ref-') === 0) {
        var sourceReferenceItem = target && target.closest ? target.closest('li[id^="cite_note-"]') : null;
        if (sourceReferenceItem && sourceReferenceItem.id) {
            return sourceReferenceItem.id;
        }

        var citeRefNode = document.getElementById(hashIdentifier);
        if (citeRefNode && citeRefNode.querySelector) {
            var noteAnchor = citeRefNode.querySelector('a[href*="#cite_note-"]');
            if (noteAnchor) {
                try {
                    var noteResolvedURL = new URL(noteAnchor.getAttribute('href') || '', document.baseURI);
                    var noteIdentifier = normalizedHashIdentifier(noteResolvedURL.hash || '');
                    if (noteIdentifier) return noteIdentifier;
                } catch (_) {
                    // Fall through to generic identifier return.
                }
            }
        }
    }

    return hashIdentifier;
}

var _macwikiCitationPreClickScroll = null;

function snapshotCitationPreClickScroll(target, resolvedURL) {
    if (!isCitationLink(target, resolvedURL)) {
        _macwikiCitationPreClickScroll = null;
        return;
    }
    _macwikiCitationPreClickScroll = {
        x: window.scrollX || 0,
        y: window.scrollY || 0,
        at: Date.now()
    };
}

function restoreCitationPreClickScrollIfNeeded() {
    var snapshot = _macwikiCitationPreClickScroll;
    _macwikiCitationPreClickScroll = null;
    if (!snapshot) return;
    if ((Date.now() - snapshot.at) > 1500) return;

    function restore() {
        var deltaX = Math.abs((window.scrollX || 0) - snapshot.x);
        var deltaY = Math.abs((window.scrollY || 0) - snapshot.y);
        if (deltaX < 0.5 && deltaY < 0.5) return;
        window.scrollTo({
            left: snapshot.x,
            top: snapshot.y,
            behavior: 'auto'
        });
    }

    restore();
    if (window.requestAnimationFrame) {
        requestAnimationFrame(restore);
    } else {
        setTimeout(restore, 16);
    }
}

function postReferenceClick(referenceId, event) {
    if (!referenceId) return false;
    if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.referenceClicked)) {
        return false;
    }
    if (event) {
        if (event.cancelable) {
            event.preventDefault();
        }
        event.stopPropagation();
        if (typeof event.stopImmediatePropagation === 'function') {
            event.stopImmediatePropagation();
        }
    }
    window.webkit.messageHandlers.referenceClicked.postMessage({
        referenceId: referenceId
    });
    restoreCitationPreClickScrollIfNeeded();
    return true;
}

document.addEventListener('mousedown', function (e) {
    if (window._macwikiDisableScriptLinkInterception === true) return;
    if (e.defaultPrevented || e.button !== 0) return;

    var target = e.target;
    while (target && target.tagName !== 'A') {
        target = target.parentElement;
    }
    if (!target) {
        _macwikiCitationPreClickScroll = null;
        return;
    }

    var rawHref = (target.getAttribute('href') || '').trim();
    if (!rawHref) {
        _macwikiCitationPreClickScroll = null;
        return;
    }

    var resolvedURL = null;
    try {
        if (rawHref.charAt(0) === '#') {
            resolvedURL = new URL(rawHref, document.baseURI);
        } else {
            resolvedURL = new URL(target.href, document.baseURI);
        }
    } catch (_) {
        resolvedURL = null;
    }

    snapshotCitationPreClickScroll(target, resolvedURL);
}, true);

document.addEventListener('click', function (e) {
    // Default mode: intercept link taps for consistent article navigation.
    // Emergency kill switch for diagnostics:
    //   window._macwikiDisableScriptLinkInterception = true
    if (window._macwikiDisableScriptLinkInterception === true) return;

    if (e.defaultPrevented || e.button !== 0) return;

    var target = e.target;
    while (target && target.tagName !== 'A') {
        target = target.parentElement;
    }
    if (!target) return;
    if (window._macwikiHideLinkHoverPreview) {
        window._macwikiHideLinkHoverPreview();
    }

    if (isMediaLinkTarget(target, e.target)) {
        e.preventDefault();
        e.stopPropagation();
        if (typeof e.stopImmediatePropagation === 'function') {
            e.stopImmediatePropagation();
        }
        return;
    }

    var rawHref = (target.getAttribute('href') || '').trim();
    if (!rawHref) return;

    // Keep in-page anchors native to avoid unnecessary app-level navigation churn,
    // except for citations which we route into the References inspector.
    if (rawHref.charAt(0) === '#') {
        var hashResolvedURL = null;
        try {
            hashResolvedURL = new URL(rawHref, document.baseURI);
        } catch (_) {
            hashResolvedURL = null;
        }
        if (isCitationLink(target, hashResolvedURL)) {
            var hashReferenceId = resolveCitationReferenceId(target, hashResolvedURL);
            postReferenceClick(hashReferenceId, e);
        }
        return;
    }

    var resolvedURL = null;
    try {
        resolvedURL = new URL(target.href, document.baseURI);
    } catch (_) {
        return;
    }
    if (!resolvedURL) return;

    if (isCitationLink(target, resolvedURL)) {
        var citationReferenceId = resolveCitationReferenceId(target, resolvedURL);
        if (postReferenceClick(citationReferenceId, e)) {
            return;
        }
    }

    // Let non-http links follow default browser behavior.
    if (resolvedURL.protocol !== 'http:' && resolvedURL.protocol !== 'https:') return;

    // Same-document fragment links should scroll in-place without opening a new article.
    var isSameDocumentFragment =
        resolvedURL.origin === window.location.origin &&
        resolvedURL.pathname === window.location.pathname &&
        !!resolvedURL.hash;
    if (isSameDocumentFragment) {
        return;
    }

    // Guard against duplicate bridge posts caused by event storms.
    var now = Date.now();
    var anyLinkLockUntil = window._macwikiLinkClickLockUntil || 0;
    if (now < anyLinkLockUntil) return;

    var clickSignature =
        resolvedURL.origin +
        resolvedURL.pathname +
        resolvedURL.search +
        "|" +
        (e.metaKey ? "1" : "0") +
        "|" +
        (e.altKey ? "1" : "0");
    if (clickSignature === window._macwikiLastLinkClickSignature &&
        (now - (window._macwikiLastLinkClickAt || 0)) < 500) {
        return;
    }
    window._macwikiLastLinkClickSignature = clickSignature;
    window._macwikiLastLinkClickAt = now;
    window._macwikiLinkClickLockUntil = now + 100;

    e.preventDefault();
    e.stopPropagation();
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkClicked) {
        window.webkit.messageHandlers.linkClicked.postMessage({
            url: resolvedURL.toString(),
            metaKey: e.metaKey,
            altKey: e.altKey
        });
    }
}, true);

// Right Clicks (Same reliable approach)
document.addEventListener('contextmenu', function (e) {
    var target = e.target;
    while (target && target.tagName !== 'A') {
        target = target.parentElement;
    }
    if (target && target.href) {
        if (isMediaLinkTarget(target, e.target)) {
            return;
        }
        if (window._macwikiHideLinkHoverPreview) {
            window._macwikiHideLinkHoverPreview();
        }
        e.preventDefault();
        e.stopPropagation();
        window.webkit.messageHandlers.linkRightClicked.postMessage({
            url: target.href,
            x: e.clientX,
            y: e.clientY
        });
    }
}, true);

// Link hover previews (SwiftUI floating-overlay bridge)
(function () {
    if (window._macwikiLinkHoverPreviewInstalled) return;
    window._macwikiLinkHoverPreviewInstalled = true;

    if (typeof window._macwikiLinkPreviewImmediateModifier === 'undefined') {
        window._macwikiLinkPreviewImmediateModifier = 'command';
    }

    var hoverDelayMs = 280;
    var hideDelayMs = 180;
    var hoverTimer = null;
    var hideTimer = null;
    var pendingSignature = null;
    var activeSignature = null;
    var hoveredAnchor = null;
    var hoveredNode = null;
    var tooltipSuppressedAnchor = null;
    var tooltipSuppressedTitle = null;
    var isCommandKeyActive = false;

    function normalizeImmediateModifierValue(value) {
        var normalized = String(value || '').trim().toLowerCase();
        if (normalized === 'command') {
            return 'command';
        }
        return 'off';
    }

    window.setLinkPreviewImmediateModifier = function (value) {
        window._macwikiLinkPreviewImmediateModifier = normalizeImmediateModifierValue(value);
        return window._macwikiLinkPreviewImmediateModifier;
    };

    function clearHoverTimer() {
        if (!hoverTimer) return;
        clearTimeout(hoverTimer);
        hoverTimer = null;
    }

    function clearHideTimer() {
        if (!hideTimer) return;
        clearTimeout(hideTimer);
        hideTimer = null;
    }

    function postHover(payload) {
        if (!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkHoverChanged)) {
            return;
        }
        window.webkit.messageHandlers.linkHoverChanged.postMessage(payload);
    }

    function clearHoveredTarget() {
        hoveredAnchor = null;
        hoveredNode = null;
        restoreSuppressedTooltip();
    }

    function restoreSuppressedTooltip() {
        if (!tooltipSuppressedAnchor) return;
        if (tooltipSuppressedTitle !== null) {
            tooltipSuppressedAnchor.setAttribute('title', tooltipSuppressedTitle);
        }
        tooltipSuppressedAnchor = null;
        tooltipSuppressedTitle = null;
    }

    function suppressNativeTooltip(anchor) {
        if (tooltipSuppressedAnchor === anchor) return;
        restoreSuppressedTooltip();

        if (!anchor || !anchor.hasAttribute('title')) return;

        tooltipSuppressedAnchor = anchor;
        tooltipSuppressedTitle = anchor.getAttribute('title');
        anchor.removeAttribute('title');
    }

    function hidePreviewNow() {
        clearHoverTimer();
        clearHideTimer();
        clearHoveredTarget();
        pendingSignature = null;
        if (activeSignature === null) return;
        activeSignature = null;
        postHover({ state: 'hide' });
    }

    function scheduleHidePreview() {
        clearHoverTimer();
        clearHideTimer();
        hideTimer = setTimeout(function () {
            pendingSignature = null;
            if (activeSignature !== null) {
                activeSignature = null;
                postHover({ state: 'hide' });
            }
        }, hideDelayMs);
    }

    function closestAnchor(node) {
        var target = elementFromNode(node);
        while (target && target.tagName !== 'A') {
            target = target.parentElement;
        }
        return target;
    }

    function elementFromNode(node) {
        if (!node) return null;
        if (node.nodeType === Node.ELEMENT_NODE) {
            return node;
        }
        return node.parentElement || null;
    }

    function normalizeWikiTitle(rawTitle) {
        if (!rawTitle) return null;
        var cleaned = String(rawTitle).trim();
        if (!cleaned) return null;

        var hashIndex = cleaned.indexOf('#');
        if (hashIndex >= 0) {
            cleaned = cleaned.slice(0, hashIndex);
        }
        if (!cleaned) return null;

        var decoded = cleaned;
        try {
            decoded = decodeURIComponent(cleaned);
        } catch (_) {
            decoded = cleaned;
        }

        decoded = decoded.replace(/\+/g, ' ');
        decoded = decoded.replace(/_/g, ' ').trim();
        return decoded || null;
    }

    function titleFromWikiPath(pathname) {
        if (!pathname) return null;
        var wikiIndex = pathname.lastIndexOf('/wiki/');
        if (wikiIndex < 0) return null;
        var rawTitle = pathname.slice(wikiIndex + 6);
        return rawTitle || null;
    }

    function titleFromIndexQuery(resolvedURL) {
        if (!resolvedURL || !resolvedURL.pathname) return null;

        var loweredPath = resolvedURL.pathname.toLowerCase();
        var isIndexPath =
            loweredPath === '/w/index.php' ||
            loweredPath.indexOf('/w/index.php') === (loweredPath.length - '/w/index.php'.length) ||
            loweredPath === '/wiki/index.php' ||
            loweredPath.indexOf('/wiki/index.php') === (loweredPath.length - '/wiki/index.php'.length);
        if (!isIndexPath) return null;

        var params = resolvedURL.searchParams;
        if (!params) return null;

        var queryTitle = (params.get('title') || '').trim();
        if (!queryTitle) return null;

        var action = (params.get('action') || '').trim().toLowerCase();
        if (action && action !== 'view') {
            var redlink = (params.get('redlink') || '').trim().toLowerCase();
            var isRedlink = redlink === '1' || redlink === 'true';
            if (!(action === 'edit' && isRedlink)) {
                return null;
            }
        }

        return queryTitle;
    }

    function decodeWikiTitle(resolvedURL) {
        if (!resolvedURL) return null;
        var rawTitle = titleFromWikiPath(resolvedURL.pathname);
        if (!rawTitle) {
            rawTitle = titleFromIndexQuery(resolvedURL);
        }
        return normalizeWikiTitle(rawTitle);
    }

    function isMediaNamespaceTitle(title) {
        var lowered = String(title || '').trim().toLowerCase();
        return lowered.indexOf('file:') === 0 ||
            lowered.indexOf('image:') === 0 ||
            lowered.indexOf('media:') === 0;
    }

    function immediateRevealRequested() {
        return normalizeImmediateModifierValue(window._macwikiLinkPreviewImmediateModifier) === 'command' &&
            isCommandKeyActive;
    }

    function payloadForAnchor(anchor, node) {
        if (!anchor) return null;

        var href = (anchor.getAttribute('href') || '').trim();
        if (!href || href.charAt(0) === '#') return null;

        var resolvedURL = null;
        try {
            resolvedURL = new URL(anchor.href, document.baseURI);
        } catch (_) {
            return null;
        }
        if (!resolvedURL) return null;

        if (resolvedURL.protocol !== 'http:' && resolvedURL.protocol !== 'https:') return null;
        if (isCitationLink(anchor, resolvedURL)) return null;
        if (isMediaLinkTarget(anchor, node)) return null;

        var articleTitle = decodeWikiTitle(resolvedURL);
        if (!articleTitle) return null;
        if (isMediaNamespaceTitle(articleTitle)) return null;

        var sameDocumentFragment =
            resolvedURL.origin === window.location.origin &&
            resolvedURL.pathname === window.location.pathname &&
            !!resolvedURL.hash;
        if (sameDocumentFragment) return null;

        var rect = anchor.getBoundingClientRect();
        if (!rect) return null;

        var signature = resolvedURL.origin + resolvedURL.pathname + resolvedURL.search;
        return {
            state: 'show',
            url: resolvedURL.toString(),
            articleTitle: articleTitle,
            signature: signature,
            x: rect.left + Math.min(Math.max(rect.width * 0.5, 14), 52),
            y: rect.bottom + 7
        };
    }

    function commitPreview(payload) {
        hoverTimer = null;
        pendingSignature = null;
        activeSignature = payload.signature;
        postHover(payload);
    }

    function schedulePreviewPayload(payload, immediate) {
        clearHideTimer();
        if (payload.signature === activeSignature) {
            return;
        }
        if (payload.signature === pendingSignature && !immediate) {
            return;
        }

        clearHoverTimer();
        pendingSignature = payload.signature;

        if (immediate) {
            commitPreview(payload);
            return;
        }

        hoverTimer = setTimeout(function () {
            commitPreview(payload);
        }, hoverDelayMs);
    }

    function queuePreview(anchor, node) {
        hoveredAnchor = anchor;
        hoveredNode = node;

        var payload = payloadForAnchor(anchor, node);
        if (!payload) {
            restoreSuppressedTooltip();
            scheduleHidePreview();
            return;
        }

        suppressNativeTooltip(anchor);
        schedulePreviewPayload(payload, immediateRevealRequested());
    }

    function revealHoveredAnchorImmediately() {
        if (!hoveredAnchor) return;
        var payload = payloadForAnchor(hoveredAnchor, hoveredNode);
        if (!payload) return;
        schedulePreviewPayload(payload, true);
    }

    function updateModifierStateFromEvent(event) {
        isCommandKeyActive = !!(event && event.metaKey);
    }

    function isModifierOnlyKeyEvent(event) {
        if (!event) return false;
        return event.key === 'Meta' ||
            event.key === 'Alt' ||
            event.key === 'Shift' ||
            event.key === 'Control';
    }

    window._macwikiHideLinkHoverPreview = hidePreviewNow;

    document.addEventListener('mousemove', function (e) {
        updateModifierStateFromEvent(e);
        var anchor = closestAnchor(e.target);
        if (!anchor) {
            clearHoveredTarget();
            if (activeSignature !== null || pendingSignature !== null) {
                scheduleHidePreview();
            }
            return;
        }
        queuePreview(anchor, e.target);
    }, true);

    document.addEventListener('mouseout', function (e) {
        if (e.relatedTarget) return;
        clearHoveredTarget();
        if (activeSignature !== null || pendingSignature !== null) {
            scheduleHidePreview();
        }
    }, true);

    document.addEventListener('scroll', function () {
        hidePreviewNow();
    }, true);

    document.addEventListener('mousedown', function () {
        hidePreviewNow();
    }, true);

    document.addEventListener('keydown', function (e) {
        var wasCommandKeyActive = isCommandKeyActive;
        updateModifierStateFromEvent(e);
        if (isModifierOnlyKeyEvent(e)) {
            if (!wasCommandKeyActive && isCommandKeyActive && immediateRevealRequested()) {
                revealHoveredAnchorImmediately();
            }
            return;
        }
        hidePreviewNow();
    }, true);

    document.addEventListener('keyup', function (e) {
        updateModifierStateFromEvent(e);
    }, true);

    window.addEventListener('blur', function () {
        isCommandKeyActive = false;
        hidePreviewNow();
    }, true);
    document.addEventListener('visibilitychange', function () {
        if (document.visibilityState !== 'visible') {
            isCommandKeyActive = false;
            hidePreviewNow();
        }
    });
})();

// Scroll telemetry for native persistence/restore reliability.
// Uses page-level scroll state as source of truth and sends throttled updates.
(function () {
    if (window._macwikiScrollTelemetryInstalled) return;
    window._macwikiScrollTelemetryInstalled = true;

    var lastSentAt = 0;
    var lastSentY = -1;
    var throttleMs = 210;
    var lastSectionSentAt = 0;
    var sectionThrottleMs = 250;
    var sectionTrackingEnabled = false;
    var lastPostedSectionId = null;
    var lastUserScrollIntentAt = 0;
    var programmaticScrollModeUntil = 0;
    var programmaticScrollForcePostTimer = null;
    var lastVelocitySampleY = 0;
    var lastVelocitySampleAt = 0;
    var scrollVelocityPxPerMs = 0;
    var perfWindowStart = Date.now();
    var perfPosts = 0;
    var perfVelocityAccum = 0;
    var perfVelocitySamples = 0;
    var perfLongTaskCount = 0;
    var recentPressureScore = 0;
    var restoreTelemetryMode = false;
    var restoreTelemetryMutedUntil = 0;
    var lastScrollEventAt = 0;
    var lastRawScrollY = 0;
    var lastRawScrollAt = 0;
    var scrollDirectionY = 0; // 1 = down, -1 = up, 0 = neutral/unknown.
    var scrollDirectionChangedAt = 0;
    var scrollDirectionToken = 0;
    var trackpadBurstUntil = 0;
    var trackpadBurstFlushTimer = null;
    var keyboardPagingUntil = 0;
    var lastBurstHeartbeatSentAt = 0;
    var lastBurstHeartbeatY = -1;
    var fastScrollVisualUntil = 0;
    var fastScrollVisualTimer = null;
    var scrollPostScheduled = false;
    var scrollPostForce = false;
    var cachedMaxScroll = 0;
    var cachedMaxScrollAt = 0;
    var maxScrollDirty = true;
    var maxScrollRecomputeScheduled = false;
    var smoothScrollSequence = 0;
    var activeSmoothScrollCompletion = null;
    var sectionEndDebounceTimer = null;

    if (window.PerformanceObserver) {
        try {
            var perfObserver = new PerformanceObserver(function (list) {
                perfLongTaskCount += list.getEntries().length;
            });
            perfObserver.observe({ entryTypes: ['longtask'] });
        } catch (_) {
            // Long task observation is best-effort.
        }
    }

    function currentScrollY() {
        return window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0;
    }

    function computeMaxScroll() {
        var docHeight = Math.max(
            document.documentElement ? document.documentElement.scrollHeight : 0,
            document.body ? document.body.scrollHeight : 0
        );
        cachedMaxScroll = Math.max(docHeight - window.innerHeight, 0);
        cachedMaxScrollAt = Date.now();
        maxScrollDirty = false;
        return cachedMaxScroll;
    }

    function getMaxScroll(forceRefresh) {
        var now = Date.now();
        if (forceRefresh || maxScrollDirty || (now - cachedMaxScrollAt) > 1400) {
            return computeMaxScroll();
        }
        return cachedMaxScroll;
    }

    function scheduleMaxScrollRecompute(delayMs) {
        if (maxScrollRecomputeScheduled) return;
        maxScrollRecomputeScheduled = true;

        var run = function () {
            maxScrollRecomputeScheduled = false;
            computeMaxScroll();
        };

        if (delayMs && delayMs > 0) {
            setTimeout(run, delayMs);
            return;
        }

        if (window.requestAnimationFrame) {
            requestAnimationFrame(run);
        } else {
            setTimeout(run, 16);
        }
    }

    function markMaxScrollDirty(deferMs) {
        maxScrollDirty = true;
        var now = Date.now();
        var effectiveDelay = deferMs || 0;
        if (shouldDeferBackgroundWork(now)) {
            // Avoid forcing scrollHeight/layout reads in hot gesture frames.
            effectiveDelay = Math.max(effectiveDelay, 210);
        }
        scheduleMaxScrollRecompute(effectiveDelay);
    }

    function schedulePostScroll(force) {
        if (force) {
            scrollPostForce = true;
        }
        if (scrollPostScheduled) return;
        scrollPostScheduled = true;

        var flush = function () {
            scrollPostScheduled = false;
            var shouldForce = scrollPostForce;
            scrollPostForce = false;
            postScroll(shouldForce);
        };

        if (window.requestAnimationFrame) {
            requestAnimationFrame(flush);
        } else {
            setTimeout(flush, 16);
        }
    }

    function shouldDeferBackgroundWork(now) {
        now = now || Date.now();
        if (isProgrammaticScrollMode(now)) return true;
        if (now < trackpadBurstUntil) return true;
        var isActiveUserScroll = (now - lastScrollEventAt) < 150;
        if (isActiveUserScroll && scrollVelocityPxPerMs > 0.15) return true;
        return false;
    }

    function setFastScrollVisualModeUntil(untilMs) {
        var root = document.documentElement;
        if (!root) return;
        var now = Date.now();

        if (untilMs <= now) {
            if (now >= fastScrollVisualUntil) {
                fastScrollVisualUntil = 0;
                root.classList.remove('macwiki-fast-scroll');
                if (fastScrollVisualTimer) {
                    clearTimeout(fastScrollVisualTimer);
                    fastScrollVisualTimer = null;
                }
            }
            return;
        }

        fastScrollVisualUntil = Math.max(fastScrollVisualUntil, untilMs);
        if (!root.classList.contains('macwiki-fast-scroll')) {
            root.classList.add('macwiki-fast-scroll');
        }

        if (fastScrollVisualTimer) {
            clearTimeout(fastScrollVisualTimer);
            fastScrollVisualTimer = null;
        }

        var waitMs = Math.max(fastScrollVisualUntil - now, 0) + 40;
        fastScrollVisualTimer = setTimeout(function () {
            fastScrollVisualTimer = null;
            setFastScrollVisualModeUntil(0);
        }, waitMs);
    }

    function scheduleTrackpadBurstFlush() {
        if (trackpadBurstFlushTimer) {
            clearTimeout(trackpadBurstFlushTimer);
            trackpadBurstFlushTimer = null;
        }
        var now = Date.now();
        var waitMs = Math.max(trackpadBurstUntil - now, 0) + 32;
        trackpadBurstFlushTimer = setTimeout(function () {
            trackpadBurstFlushTimer = null;
            schedulePostScroll(true);
        }, waitMs);
    }

    function noteWheelIntent(e) {
        noteUserScrollIntent();

        var now = Date.now();
        var deltaY = (e && typeof e.deltaY === 'number') ? e.deltaY : 0;
        var absDeltaY = Math.abs(deltaY);
        var deltaMode = (e && typeof e.deltaMode === 'number') ? e.deltaMode : 0;
        var isPixelMode = deltaMode === 0;
        var isTrackpadLike = isPixelMode && absDeltaY > 0 && absDeltaY <= 120;
        var directionChanged = false;
        var reversedQuickly = false;
        if (absDeltaY > 0.6) {
            var nextDirection = deltaY > 0 ? 1 : -1;
            if (nextDirection !== scrollDirectionY) {
                reversedQuickly =
                    scrollDirectionY !== 0 &&
                    (now - scrollDirectionChangedAt) < 260;
                scrollDirectionY = nextDirection;
                scrollDirectionChangedAt = now;
                scrollDirectionToken += 1;
                directionChanged = true;
            }
        }
        var burstMs = isTrackpadLike ? 240 : 130;
        if (directionChanged) {
            burstMs = Math.min(burstMs, 170);
        }
        if (reversedQuickly) {
            burstMs = Math.min(burstMs, 145);
        }
        trackpadBurstUntil = Math.max(trackpadBurstUntil, now + burstMs);
        setFastScrollVisualModeUntil(trackpadBurstUntil);
        scheduleTrackpadBurstFlush();
        if (reversedQuickly) {
            // Reversal should feel immediate; flush one forced telemetry checkpoint.
            schedulePostScroll(true);
        }
    }

    function isEditableElement(target) {
        if (!target) return false;
        if (target.isContentEditable) return true;
        if (typeof target.closest === 'function') {
            if (target.closest('input, textarea, select, [contenteditable], [contenteditable=\"true\"], [contenteditable=\"plaintext-only\"]')) {
                return true;
            }
        }
        var tagName = typeof target.tagName === 'string' ? target.tagName.toLowerCase() : '';
        return tagName === 'input' || tagName === 'textarea' || tagName === 'select';
    }

    function currentProgress(y) {
        var maxScroll = getMaxScroll(false);
        if (maxScroll <= 0) return 1;
        return Math.min(Math.max(y / maxScroll, 0), 1);
    }

    function clamp(value, minValue, maxValue) {
        return Math.min(Math.max(value, minValue), maxValue);
    }

    function noteUserScrollIntent() {
        lastUserScrollIntentAt = Date.now();
        cancelSmoothScrollAnimation();
        programmaticScrollModeUntil = 0;
        if (programmaticScrollForcePostTimer) {
            clearTimeout(programmaticScrollForcePostTimer);
            programmaticScrollForcePostTimer = null;
        }
    }

    function isProgrammaticScrollMode(now) {
        return now < programmaticScrollModeUntil;
    }

    function setProgrammaticScrollMode(durationMs) {
        var now = Date.now();
        var windowMs = clamp(durationMs || 0, 220, 1800);
        programmaticScrollModeUntil = Math.max(programmaticScrollModeUntil, now + windowMs);
        if (programmaticScrollForcePostTimer) {
            clearTimeout(programmaticScrollForcePostTimer);
            programmaticScrollForcePostTimer = null;
        }
        if (sectionEndDebounceTimer) {
            clearTimeout(sectionEndDebounceTimer);
            sectionEndDebounceTimer = null;
        }
        programmaticScrollForcePostTimer = setTimeout(function () {
            schedulePostScroll(true);
            programmaticScrollForcePostTimer = null;
        }, windowMs + 90);
    }

    function easeInOutSine(t) {
        return -(Math.cos(Math.PI * t) - 1) / 2;
    }

    function completeSmoothScroll(didReachTarget) {
        var completion = activeSmoothScrollCompletion;
        activeSmoothScrollCompletion = null;
        if (completion) {
            completion(!!didReachTarget);
        }
    }

    function cancelSmoothScrollAnimation() {
        smoothScrollSequence += 1;
        if (window._macwikiSmoothScrollRAF) {
            cancelAnimationFrame(window._macwikiSmoothScrollRAF);
            window._macwikiSmoothScrollRAF = null;
        }
        completeSmoothScroll(false);
    }

    function monitorProgrammaticScroll(targetY, durationMs, options) {
        options = options || {};
        var emitPost = options.emitPost !== false;
        var onComplete = typeof options.onComplete === 'function' ? options.onComplete : null;
        var sequenceId = options.sequenceId;
        var deadline = Date.now() + clamp(durationMs + 320, 480, 1680);
        var settledFrames = 0;
        var lastY = currentScrollY();

        function step() {
            if (sequenceId !== undefined && sequenceId !== smoothScrollSequence) {
                window._macwikiSmoothScrollRAF = null;
                return;
            }
            var now = Date.now();
            var y = currentScrollY();
            var remainingDistance = Math.abs(targetY - y);
            var velocity = Math.abs(y - lastY);
            lastY = y;

            if (remainingDistance <= 1.5 && velocity <= 0.6) {
                settledFrames += 1;
            } else {
                settledFrames = 0;
            }

            if (settledFrames >= 2 || now >= deadline) {
                window._macwikiSmoothScrollRAF = null;
                window.scrollTo(0, targetY);
                if (emitPost) {
                    schedulePostScroll(true);
                }
                if (onComplete) {
                    onComplete();
                }
                return;
            }

            var remainingMs = Math.max(deadline - now, 0);
            if (remainingMs > 130) {
                setProgrammaticScrollMode(clamp(remainingMs + 120, 220, 520));
            }

            window._macwikiSmoothScrollRAF = requestAnimationFrame(step);
        }

        window._macwikiSmoothScrollRAF = requestAnimationFrame(step);
    }

    function supportsNativeSmoothScroll() {
        try {
            return (
                typeof window.scrollTo === 'function' &&
                'scrollBehavior' in document.documentElement.style
            );
        } catch (_) {
            return false;
        }
    }

    function smoothScrollToY(targetY, options) {
        options = options || {};
        cancelSmoothScrollAnimation();
        activeSmoothScrollCompletion =
            typeof options.onComplete === 'function' ? options.onComplete : null;
        var sequenceId = smoothScrollSequence;
        var maxScroll = getMaxScroll(true);
        var clampedTarget = clamp(targetY, 0, maxScroll);
        var startY = currentScrollY();
        var distance = clampedTarget - startY;
        if (Math.abs(distance) < 2) {
            window.scrollTo(0, clampedTarget);
            setTimeout(function () {
                if (sequenceId !== smoothScrollSequence) return;
                schedulePostScroll(true);
                completeSmoothScroll(true);
            }, 28);
            return true;
        }

        var prefersReducedMotion = false;
        try {
            prefersReducedMotion =
                !!window.matchMedia &&
                !!window.matchMedia('(prefers-reduced-motion: reduce)').matches;
        } catch (_) {
            prefersReducedMotion = false;
        }

        var requestedDurationMs = Number(options.durationMs);
        var requestedPixelsPerMs = Number(options.pixelsPerMs);
        var minDurationMs = Number(options.minDurationMs);
        var maxDurationMs = Number(options.maxDurationMs);
        var distanceAbs = Math.abs(distance);
        var pixelsPerMs =
            (Number.isFinite(requestedPixelsPerMs) && requestedPixelsPerMs > 0)
                ? requestedPixelsPerMs
                : 2.2;
        minDurationMs =
            (Number.isFinite(minDurationMs) && minDurationMs > 0)
                ? minDurationMs
                : 320;
        maxDurationMs =
            (Number.isFinite(maxDurationMs) && maxDurationMs > minDurationMs)
                ? maxDurationMs
                : 1800;
        var distanceDurationMs = distanceAbs / pixelsPerMs;
        var durationMs = Number.isFinite(requestedDurationMs) ?
            clamp(requestedDurationMs, minDurationMs, maxDurationMs) :
            clamp(distanceDurationMs, minDurationMs, maxDurationMs);
        setProgrammaticScrollMode(durationMs + 340);

        if (prefersReducedMotion) {
            window.scrollTo(0, clampedTarget);
            setTimeout(function () {
                if (sequenceId !== smoothScrollSequence) return;
                schedulePostScroll(true);
                completeSmoothScroll(true);
            }, 28);
            return true;
        }

        var nativeSmoothEnabled = options.nativeSmooth !== false;
        if (nativeSmoothEnabled && supportsNativeSmoothScroll()) {
            window.scrollTo({ top: clampedTarget, behavior: 'smooth' });
            monitorProgrammaticScroll(clampedTarget, durationMs, {
                emitPost: true,
                sequenceId: sequenceId,
                onComplete: function () { completeSmoothScroll(true); }
            });
            return true;
        }

        var startTime = (window.performance && performance.now) ? performance.now() : Date.now();
        function step(nowTs) {
            if (sequenceId !== smoothScrollSequence) {
                window._macwikiSmoothScrollRAF = null;
                return;
            }
            var frameNow =
                typeof nowTs === 'number'
                    ? nowTs
                    : ((window.performance && performance.now) ? performance.now() : Date.now());
            var elapsed = frameNow - startTime;
            var t = clamp(elapsed / durationMs, 0, 1);
            var eased = easeInOutSine(t);
            var nextY = startY + (distance * eased);
            window.scrollTo(0, nextY);

            if (t < 1) {
                window._macwikiSmoothScrollRAF = requestAnimationFrame(step);
                return;
            }

            window._macwikiSmoothScrollRAF = null;
            window.scrollTo(0, clampedTarget);
            schedulePostScroll(true);
            completeSmoothScroll(true);
        }

        window._macwikiSmoothScrollRAF = requestAnimationFrame(step);
        return true;
    }

    // Expose helpers for TOC/anchor jumps.
    window._macwikiSetProgrammaticScrollMode = setProgrammaticScrollMode;
    window._macwikiSmoothScrollToY = smoothScrollToY;
    window._macwikiCancelSmoothScrollAnimation = cancelSmoothScrollAnimation;

    function maybeTuneAndReport(now) {
        var elapsed = now - perfWindowStart;
        if (elapsed < 1800) return;

        var elapsedSeconds = Math.max(elapsed / 1000, 0.001);
        var avgVelocity = perfVelocitySamples > 0 ? (perfVelocityAccum / perfVelocitySamples) : 0;
        var postsPerSecond = perfPosts / elapsedSeconds;
        var inRestoreMode = restoreTelemetryMode || now < restoreTelemetryMutedUntil;
        var instantPressure = 0;
        if (perfLongTaskCount >= 2) instantPressure += 0.65;
        if (avgVelocity > 1.1) instantPressure += 0.2;
        if (postsPerSecond > 9.0) instantPressure += 0.15;
        instantPressure = clamp(instantPressure, 0, 1.2);
        recentPressureScore = (recentPressureScore * 0.72) + (instantPressure * 0.28);

        // Section lookup uses a cached binary search and has its own cadence;
        // it must not increase native bridge traffic when the Inspector is not
        // visible. Keep the reader's baseline telemetry budget independent.
        var baseThrottle = 210;
        var targetThrottle = baseThrottle;
        if (perfLongTaskCount >= 2) targetThrottle += 30;
        if (avgVelocity > 1.2) targetThrottle += 20;
        if (avgVelocity < 0.4 && perfLongTaskCount === 0) targetThrottle -= 15;
        if (inRestoreMode) targetThrottle = Math.max(targetThrottle, 390);
        var maxThrottle = inRestoreMode ? 430 : 280;
        targetThrottle = clamp(targetThrottle, 120, maxThrottle);
        throttleMs = Math.round((throttleMs * 0.7) + (targetThrottle * 0.3));

        if (!inRestoreMode &&
            window.webkit &&
            window.webkit.messageHandlers &&
            window.webkit.messageHandlers.scrollPerfSnapshot) {
            window.webkit.messageHandlers.scrollPerfSnapshot.postMessage({
                throttleMs: throttleMs,
                longTasks: perfLongTaskCount,
                avgVelocity: avgVelocity,
                postsPerSecond: postsPerSecond,
                sectionTrackingEnabled: sectionTrackingEnabled
            });
        }

        perfWindowStart = now;
        perfPosts = 0;
        perfVelocityAccum = 0;
        perfVelocitySamples = 0;
        perfLongTaskCount = 0;
    }

    function postScroll(force) {
        var now = Date.now();
        var y = currentScrollY();
        var inRestoreMode = restoreTelemetryMode || now < restoreTelemetryMutedUntil;
        var inProgrammaticMode = !inRestoreMode && isProgrammaticScrollMode(now);
        var inTrackpadBurst = !inRestoreMode && (now < trackpadBurstUntil);
        var directionChangedRecently = !inProgrammaticMode && (now - scrollDirectionChangedAt) < 170;
        var burstHeartbeat = false;
        if (lastVelocitySampleAt > 0) {
            var dt = Math.max(now - lastVelocitySampleAt, 1);
            var dy = Math.abs(y - lastVelocitySampleY);
            var instantVelocity = dy / dt;
            // Low-pass filter for stable velocity signal.
            scrollVelocityPxPerMs = (scrollVelocityPxPerMs * 0.65) + (instantVelocity * 0.35);
        }
        lastVelocitySampleY = y;
        lastVelocitySampleAt = now;
        var effectiveThrottleMs = inRestoreMode ? Math.max(throttleMs, 420) : throttleMs;
        var effectiveDelta = inRestoreMode ? 24 : 14;
        var inActiveUserScroll =
            !inRestoreMode &&
            !inProgrammaticMode &&
            (now - lastUserScrollIntentAt) < 420;
        if (inProgrammaticMode) {
            // TOC smooth-scroll should prioritize compositor motion over bridge chatter.
            effectiveThrottleMs = Math.max(effectiveThrottleMs, 560);
            effectiveDelta = Math.max(effectiveDelta, 120);
        } else if (inActiveUserScroll) {
            // While user is actively scrolling, prefer visual throughput over telemetry cadence.
            effectiveThrottleMs = Math.max(effectiveThrottleMs, 260);
            effectiveDelta = Math.max(effectiveDelta, 30);
            if (scrollVelocityPxPerMs > 1.2) {
                effectiveThrottleMs = Math.max(effectiveThrottleMs, 320);
                effectiveDelta = Math.max(effectiveDelta, 48);
            }
        }
        if (inTrackpadBurst) {
            effectiveThrottleMs = Math.max(effectiveThrottleMs, directionChangedRecently ? 320 : 420);
            effectiveDelta = Math.max(effectiveDelta, directionChangedRecently ? 56 : 84);
        }
        if (inTrackpadBurst && !force) {
            var burstDelta = Math.abs(y - lastBurstHeartbeatY);
            if ((now - lastBurstHeartbeatSentAt) < 460 && burstDelta < 96) {
                // Send section updates at reduced frequency during burst (300ms)
                if (!inProgrammaticMode &&
                    sectionTrackingEnabled &&
                    window.currentVisibleSectionId &&
                    (now - lastSectionSentAt) >= 300) {
                    lastSectionSentAt = now;
                    var sid = window.currentVisibleSectionId();
                    if (sid !== lastPostedSectionId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollChanged) {
                        lastPostedSectionId = sid;
                        window.webkit.messageHandlers.scrollChanged.postMessage({
                            y: y,
                            progress: currentProgress(y),
                            userInitiated: true,
                            programmatic: false,
                            velocity: scrollVelocityPxPerMs,
                            gestureFast: true,
                            burstHeartbeat: false,
                            directionChanged: directionChangedRecently,
                            sectionId: sid
                        });
                    }
                }
                maybeTuneAndReport(now);
                return;
            }
            // Keep native fallback observer suppressed without reintroducing
            // full per-frame bridge churn.
            burstHeartbeat = true;
            lastBurstHeartbeatSentAt = now;
            lastBurstHeartbeatY = y;
        }
        if (!force && !burstHeartbeat && now - lastSentAt < effectiveThrottleMs && Math.abs(y - lastSentY) < effectiveDelta) {
            // Same - section updates at reduced frequency during throttle
            if (!inProgrammaticMode &&
                sectionTrackingEnabled &&
                window.currentVisibleSectionId &&
                (now - lastSectionSentAt) >= 300) {
                    lastSectionSentAt = now;
                    var sid = window.currentVisibleSectionId();
                    if (sid !== lastPostedSectionId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollChanged) {
                        lastPostedSectionId = sid;
                        window.webkit.messageHandlers.scrollChanged.postMessage({
                        y: y,
                        progress: currentProgress(y),
                        userInitiated: true,
                        programmatic: false,
                        velocity: scrollVelocityPxPerMs,
                        gestureFast: false,
                        burstHeartbeat: false,
                        directionChanged: directionChangedRecently,
                        sectionId: sid
                    });
                }
            }
            maybeTuneAndReport(now);
            return;
        }
        lastSentAt = now;
        lastSentY = y;
        perfPosts += 1;
        perfVelocityAccum += scrollVelocityPxPerMs;
        perfVelocitySamples += 1;
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollChanged) {
            var msg = {
                y: y,
                progress: currentProgress(y),
                userInitiated: !inProgrammaticMode && (now - lastUserScrollIntentAt) < 480,
                programmatic: inProgrammaticMode,
                velocity: scrollVelocityPxPerMs,
                gestureFast: inTrackpadBurst,
                burstHeartbeat: burstHeartbeat,
                directionChanged: directionChangedRecently
            };
            var effectiveSectionThrottleMs = sectionThrottleMs;
            // Include visible section id synchronously — uses cached heading
            // positions (binary search, no DOM queries). Send at a lower
            // cadence than raw scroll telemetry to reduce per-scroll work.
            if (!inRestoreMode &&
                !inProgrammaticMode &&
                sectionTrackingEnabled &&
                scrollVelocityPxPerMs < 2.5 &&
                window.currentVisibleSectionId &&
                (force || (now - lastSectionSentAt) >= effectiveSectionThrottleMs)) {
                lastSectionSentAt = now;
                var sid = window.currentVisibleSectionId();
                if (sid !== lastPostedSectionId) {
                    lastPostedSectionId = sid;
                    msg.sectionId = sid;
                }
            }
            window.webkit.messageHandlers.scrollChanged.postMessage(msg);
            // Schedule a debounced final section update for when scrolling stops.
            // This ensures we always send the sectionId after scroll ends, even
            // if velocity was too high during active scrolling.
            if (!inProgrammaticMode && sectionTrackingEnabled && window.currentVisibleSectionId) {
                if (sectionEndDebounceTimer) {
                    clearTimeout(sectionEndDebounceTimer);
                }
                sectionEndDebounceTimer = setTimeout(function () {
                    sectionEndDebounceTimer = null;
                    var finalSid = window.currentVisibleSectionId();
                    if (finalSid !== lastPostedSectionId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrollChanged) {
                        lastPostedSectionId = finalSid;
                        window.webkit.messageHandlers.scrollChanged.postMessage({
                            y: currentScrollY(),
                            progress: currentProgress(currentScrollY()),
                            userInitiated: false,
                            programmatic: false,
                            velocity: 0,
                            gestureFast: false,
                            burstHeartbeat: false,
                            directionChanged: false,
                            sectionId: finalSid
                        });
                    }
                }, 220);
            }
        }
        maybeTuneAndReport(now);
    }

    window.addEventListener('scroll', function () {
        var now = Date.now();
        var y = currentScrollY();
        if (lastRawScrollAt > 0) {
            var dt = Math.max(now - lastRawScrollAt, 1);
            var signedDeltaY = y - lastRawScrollY;
            var dy = Math.abs(signedDeltaY);
            if (dy > 0.75) {
                var nextDirection = signedDeltaY > 0 ? 1 : -1;
                if (nextDirection !== scrollDirectionY) {
                    scrollDirectionY = nextDirection;
                    scrollDirectionChangedAt = now;
                    scrollDirectionToken += 1;
                }
            }
            var rawVelocity = dy / dt;
            // Keep velocity responsive during dense wheel/trackpad streams.
            scrollVelocityPxPerMs = (scrollVelocityPxPerMs * 0.4) + (rawVelocity * 0.6);
            var directionChangedRecently = (now - scrollDirectionChangedAt) < 180;
            var inKeyboardPaging = now < keyboardPagingUntil;
            if (!inKeyboardPaging && rawVelocity > 0.9) {
                var burstMs = rawVelocity > 1.6 ? 300 : 240;
                if (directionChangedRecently) {
                    burstMs = Math.min(burstMs, 170);
                }
                trackpadBurstUntil = Math.max(trackpadBurstUntil, now + burstMs);
                setFastScrollVisualModeUntil(trackpadBurstUntil);
                scheduleTrackpadBurstFlush();
            }
        }
        lastRawScrollY = y;
        lastRawScrollAt = now;
        lastScrollEventAt = now;
        schedulePostScroll(false);
    }, { passive: true });
    window.addEventListener('wheel', function (e) {
        noteWheelIntent(e);
    }, { passive: true });
    window.addEventListener('touchmove', function () {
        noteUserScrollIntent();
    }, { passive: true });
    window.addEventListener('keydown', function (e) {
        var key = e.key;
        if (
            key === 'ArrowDown' ||
            key === 'ArrowUp' ||
            key === 'PageDown' ||
            key === 'PageUp' ||
            key === 'Home' ||
            key === 'End' ||
            key === ' '
        ) {
            if (
                !e.defaultPrevented &&
                !e.metaKey &&
                !e.ctrlKey &&
                !e.altKey &&
                !isEditableElement(e.target) &&
                (key === 'PageDown' || key === 'PageUp' || key === ' ')
            ) {
                // WebKit owns native keyboard paging. This marker only keeps
                // telemetry from misclassifying its velocity as a trackpad burst.
                keyboardPagingUntil = Date.now() + 500;
            }
            noteUserScrollIntent();
        }
    }, true);
    function refreshScrollMetricsAfterResize() {
        markMaxScrollDirty(30);

        setTimeout(function () {
            getMaxScroll(true);
            schedulePostScroll(true);
        }, 80);
    }

    window.addEventListener('resize', function () {
        refreshScrollMetricsAfterResize();
    });
    window.addEventListener('load', function () {
        markMaxScrollDirty(45);
        setTimeout(function () { schedulePostScroll(true); }, 50);
    });
    document.addEventListener('load', function (e) {
        var target = e && e.target;
        if (!target || target.tagName !== 'IMG') return;
        markMaxScrollDirty(22);
    }, true);

    // WebKit owns image scheduling through the native loading/decoding hints
    // injected before document load. JavaScript only reserves a real aspect
    // ratio when Wikipedia supplied dimensions and adds a bounded visual
    // placeholder for those dimensionally stable images.
    function parsePositiveInt(value) {
        if (value === null || value === undefined) return 0;
        var n = parseInt(String(value), 10);
        return Number.isFinite(n) && n > 0 ? n : 0;
    }

    function shouldUseImageSkeleton(image) {
        if (!image) return false;
        var width =
            parsePositiveInt(image.getAttribute('width')) ||
            parsePositiveInt(image.getAttribute('data-file-width')) ||
            parsePositiveInt(image.getAttribute('data-width'));
        var height =
            parsePositiveInt(image.getAttribute('height')) ||
            parsePositiveInt(image.getAttribute('data-file-height')) ||
            parsePositiveInt(image.getAttribute('data-height'));

        if (width > 0 && height > 0) {
            // Skip tiny utility/media-control images to avoid visual noise.
            return (width * height) >= 12000;
        }
        // Unknown dimensions cannot reserve space, so a synthetic shimmer would
        // still collapse and pop. Let WebKit reveal those images normally.
        return false;
    }

    function reserveImageLayout(image) {
        if (!image || image.dataset.macwikiLayoutReserved === '1') return;
        image.dataset.macwikiLayoutReserved = '1';

        var width = parsePositiveInt(image.getAttribute('width'));
        var height = parsePositiveInt(image.getAttribute('height'));

        // Wikipedia often exposes dimensions via data-file-* attributes.
        if (!width || !height) {
            width = parsePositiveInt(image.getAttribute('data-file-width')) || width;
            height = parsePositiveInt(image.getAttribute('data-file-height')) || height;
        }
        if (!width || !height) {
            width = parsePositiveInt(image.getAttribute('data-width')) || width;
            height = parsePositiveInt(image.getAttribute('data-height')) || height;
        }

        if (width > 0 && height > 0) {
            if (!image.hasAttribute('width')) image.setAttribute('width', String(width));
            if (!image.hasAttribute('height')) image.setAttribute('height', String(height));
            if (!image.style.aspectRatio) {
                image.style.aspectRatio = width + ' / ' + height;
            }
        }
    }

    function prepareImageFade(image) {
        if (!image || image.dataset.macwikiFadePrepared === '1') return;
        if (!shouldUseImageSkeleton(image)) return;
        image.dataset.macwikiFadePrepared = '1';
        image.dataset.macwikiImageTransition = '1';
        image.dataset.macwikiImageSkeleton = '1';

        if (image.complete) {
            image.dataset.macwikiImageState = 'loaded';
            return;
        }

        image.dataset.macwikiImageState = 'loading';

        var cleanup = function () {
            image.removeEventListener('load', markLoaded);
            image.removeEventListener('error', markDone);
        };
        var applyLoadedStateWhenReady = function () {
            if (!image.isConnected) {
                cleanup();
                return;
            }
            if (shouldDeferBackgroundWork(Date.now())) {
                if (image.dataset.macwikiLoadedDeferred !== '1') {
                    image.dataset.macwikiLoadedDeferred = '1';
                    setTimeout(function () {
                        image.dataset.macwikiLoadedDeferred = '0';
                        applyLoadedStateWhenReady();
                    }, 84);
                }
                return;
            }
            image.dataset.macwikiImageState = 'loaded';
            image.dataset.macwikiLoadedDeferred = '0';
            cleanup();
        };
        var markLoaded = function () {
            applyLoadedStateWhenReady();
        };
        var markDone = function () {
            applyLoadedStateWhenReady();
        };

        image.addEventListener('load', markLoaded);
        image.addEventListener('error', markDone);
    }

    function prepareImagesForStableLayout(options) {
        options = options || {};
        var images = document.images;
        if (!images || !images.length) return;

        // Keep the DOM walk bounded. The first useful viewport is prepared
        // immediately; remaining dimension metadata is applied in idle time.
        var maxPrepImages = Math.min(images.length, options.maxPrepImages || 240);
        var maxFadePrepImages = Math.min(
            maxPrepImages,
            options.maxFadePrepImages === undefined ? 72 : options.maxFadePrepImages
        );
        var frameBudgetMs = options.frameBudgetMs || 8;
        var idleTimeout = options.idleTimeout || 280;
        var syncFrontload = Math.min(options.syncFrontload || 3, maxPrepImages);
        var startInIdle = options.startInIdle !== false;
        var index = 0;

        // Always reserve a small up-front set so above-the-fold layout is stable.
        while (index < syncFrontload) {
            var upfrontImage = images[index];
            reserveImageLayout(upfrontImage);
            if (index < maxFadePrepImages) {
                prepareImageFade(upfrontImage);
            }
            index += 1;
        }

        function runChunk(deadline) {
            var start = (window.performance && performance.now) ? performance.now() : 0;
            if (shouldDeferBackgroundWork(Date.now()) && index >= syncFrontload) {
                if (window.requestIdleCallback) {
                    window.requestIdleCallback(runChunk, { timeout: idleTimeout + 160 });
                } else {
                    setTimeout(runChunk, 80);
                }
                return;
            }

            while (index < maxPrepImages) {
                var image = images[index];
                reserveImageLayout(image);
                if (index < maxFadePrepImages) {
                    prepareImageFade(image);
                }
                index += 1;

                if (deadline && typeof deadline.timeRemaining === 'function') {
                    if (deadline.timeRemaining() < 2) break;
                } else if ((window.performance && performance.now) && (performance.now() - start) > frameBudgetMs) {
                    break;
                }
            }

            if (index < maxPrepImages) {
                if (window.requestIdleCallback) {
                    window.requestIdleCallback(runChunk, { timeout: idleTimeout });
                } else {
                    setTimeout(runChunk, 0);
                }
            }
        }

        if (startInIdle && window.requestIdleCallback) {
            window.requestIdleCallback(runChunk, { timeout: idleTimeout });
        } else {
            runChunk();
        }
    }

    var didRunInitialImagePrep = false;
    function runInitialImagePrep() {
        if (didRunInitialImagePrep) return;
        didRunInitialImagePrep = true;
        var imageCount = (document.images && document.images.length) ? document.images.length : 0;
        var largePageImageMode = imageCount > 180;

        if (largePageImageMode) {
            prepareImagesForStableLayout({
                maxPrepImages: 220,
                maxFadePrepImages: 48,
                frameBudgetMs: 4,
                idleTimeout: 160,
                syncFrontload: 3,
                startInIdle: true
            });
        } else {
            prepareImagesForStableLayout({
                maxPrepImages: 240,
                maxFadePrepImages: 72,
                syncFrontload: 3,
                startInIdle: true
            });
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', runInitialImagePrep, { once: true });
    } else {
        setTimeout(runInitialImagePrep, 0);
    }

    window.addEventListener('load', function () {
        runInitialImagePrep();
    });

    var scrollRestoreSequence = 0;
    var scrollRestoreTimers = [];

    function clearScrollRestoreTimers() {
        while (scrollRestoreTimers.length > 0) {
            clearTimeout(scrollRestoreTimers.pop());
        }
    }

    function currentRestoreState() {
        var y = currentScrollY();
        var maxScroll = getMaxScroll(false);
        return {
            y: y,
            progress: currentProgress(y),
            maxScroll: maxScroll
        };
    }

    function postScrollRestoreReady(payload) {
        if (
            window.webkit &&
            window.webkit.messageHandlers &&
            window.webkit.messageHandlers.scrollRestoreReady
        ) {
            window.webkit.messageHandlers.scrollRestoreReady.postMessage(payload);
        }
    }

    function shouldRevealAfterScrollRestore(state, options, isFinalProbe) {
        if (isFinalProbe) return true;
        if ((state.maxScroll || 0) <= 1) return true;

        var desiredY = Number(options.desiredY);
        if (!Number.isFinite(desiredY)) desiredY = 0;
        var fallbackProgress = clamp(Number(options.fallbackProgress) || 0, 0, 1);
        var preferImmediateReveal = !!options.preferImmediateReveal;

        if (desiredY > 6) {
            var positionTolerance = Math.max(44, desiredY * 0.09);
            if (Math.abs(state.y - desiredY) <= positionTolerance) {
                return true;
            }
            if (state.y >= desiredY * (preferImmediateReveal ? 0.64 : 0.78)) {
                return true;
            }
            return false;
        }

        if (fallbackProgress > 0.01) {
            if (Math.abs(state.progress - fallbackProgress) <= 0.07) {
                return true;
            }
            if (state.progress >= fallbackProgress * (preferImmediateReveal ? 0.68 : 0.82)) {
                return true;
            }
            return false;
        }

        return true;
    }

    function performScrollRestoreAttempt(options, programmaticWindowMs) {
        var desiredY = Number(options.desiredY);
        if (!Number.isFinite(desiredY)) desiredY = 0;
        var fallbackProgress = clamp(Number(options.fallbackProgress) || 0, 0, 1);

        if (desiredY > 0) {
            setProgrammaticScrollMode(programmaticWindowMs);
            window.scrollTo(0, desiredY);
            return;
        }

        if (fallbackProgress > 0.01) {
            var maxScroll = getMaxScroll(true);
            if (maxScroll > 0) {
                setProgrammaticScrollMode(programmaticWindowMs);
                window.scrollTo(0, maxScroll * fallbackProgress);
            }
        }
    }

    window.cancelMacWikiScrollRestore = function () {
        scrollRestoreSequence += 1;
        clearScrollRestoreTimers();
    };

    window.beginMacWikiScrollRestore = function (options) {
        options = options || {};
        scrollRestoreSequence += 1;
        var sequenceId = scrollRestoreSequence;
        clearScrollRestoreTimers();
        cancelSmoothScrollAnimation();

        var retryDelaysMs = Array.isArray(options.retryDelaysMs) ? options.retryDelaysMs : [];
        var revealCheckpointsMs = Array.isArray(options.revealCheckpointsMs) ? options.revealCheckpointsMs : [];
        var maxRetryDelayMs = 0;
        var maxRevealDelayMs = 0;

        retryDelaysMs.forEach(function (delayMs) {
            maxRetryDelayMs = Math.max(maxRetryDelayMs, Number(delayMs) || 0);
        });
        revealCheckpointsMs.forEach(function (delayMs) {
            maxRevealDelayMs = Math.max(maxRevealDelayMs, Number(delayMs) || 0);
        });

        var programmaticWindowMs = clamp(
            Math.max(maxRetryDelayMs, maxRevealDelayMs) + 420,
            320,
            3800
        );
        var sessionID = options.sessionID ? String(options.sessionID) : '';

        function schedule(delayMs, work) {
            var clampedDelayMs = Math.max(Number(delayMs) || 0, 0);
            var timer = setTimeout(function () {
                if (sequenceId !== scrollRestoreSequence) return;
                work();
            }, clampedDelayMs);
            scrollRestoreTimers.push(timer);
        }

        function finishRestore(isFinalProbe) {
            if (sequenceId !== scrollRestoreSequence) return;
            clearScrollRestoreTimers();
            var state = currentRestoreState();
            postScrollRestoreReady({
                sessionID: sessionID,
                y: state.y,
                progress: state.progress,
                maxScroll: state.maxScroll,
                final: !!isFinalProbe
            });
        }

        performScrollRestoreAttempt(options, programmaticWindowMs);

        retryDelaysMs.forEach(function (delayMs) {
            schedule(delayMs, function () {
                performScrollRestoreAttempt(options, programmaticWindowMs);
            });
        });

        if (revealCheckpointsMs.length === 0) {
            schedule(0, function () {
                finishRestore(true);
            });
            return true;
        }

        revealCheckpointsMs.forEach(function (delayMs, index) {
            schedule(delayMs, function () {
                var state = currentRestoreState();
                var isFinalProbe = index === revealCheckpointsMs.length - 1;
                if (shouldRevealAfterScrollRestore(state, options, isFinalProbe)) {
                    finishRestore(isFinalProbe);
                }
            });
        });

        return true;
    };

    window.setScrollTelemetrySectionTrackingEnabled = function (enabled) {
        sectionTrackingEnabled = !!enabled;
        throttleMs = 210;
        // Send one immediate update so native state can sync quickly.
        schedulePostScroll(true);
    };

    window.setRestoreTelemetryMode = function (enabled) {
        var now = Date.now();
        restoreTelemetryMode = !!enabled;
        if (restoreTelemetryMode) {
            restoreTelemetryMutedUntil = now + 4600;
            throttleMs = Math.max(throttleMs, 390);
        } else {
            restoreTelemetryMutedUntil = 0;
            throttleMs = 210;
            schedulePostScroll(true);
        }
    };

    window._macwikiInvalidateReaderLayoutMetrics = function () {
        markMaxScrollDirty(0);
        if (window._invalidateHeadingCache) {
            window._invalidateHeadingCache();
        }
        requestAnimationFrame(function () {
            markMaxScrollDirty(0);
            getMaxScroll(true);
            schedulePostScroll(true);
        });
    };
})();

// Text Selection Detection
// Helper: Get XPath-like element path
function getElementPath(element) {
    if (!element || element === document.body) return '';

    var path = [];
    var current = element;

    while (current && current !== document.body) {
        var tagName = current.tagName.toLowerCase();
        var index = 1;
        var sibling = current.previousElementSibling;

        while (sibling) {
            if (sibling.tagName.toLowerCase() === tagName) index++;
            sibling = sibling.previousElementSibling;
        }

        path.unshift(tagName + '[' + index + ']');
        current = current.parentElement;
    }

    return path.join('/');
}

// Helper: Get section title
function getSectionTitle(element) {
    var current = element;
    while (current && current !== document.body) {
        // Look for previous heading
        var prev = current.previousElementSibling;
        while (prev) {
            if (/^H[1-6]$/i.test(prev.tagName)) {
                return prev.textContent.trim();
            }
            prev = prev.previousElementSibling;
        }
        current = current.parentElement;
    }
    return null;
}

// Helper: Get context around selection
function getContext(range, chars) {
    if (!range || chars <= 0) {
        return { before: '', after: '' };
    }

    try {
        var beforeRange = range.cloneRange();
        beforeRange.selectNodeContents(document.body);
        beforeRange.setEnd(range.startContainer, range.startOffset);
        var beforeText = beforeRange.toString() || '';

        var afterRange = range.cloneRange();
        afterRange.selectNodeContents(document.body);
        afterRange.setStart(range.endContainer, range.endOffset);
        var afterText = afterRange.toString() || '';

        return {
            before: beforeText.slice(Math.max(0, beforeText.length - chars)),
            after: afterText.slice(0, chars)
        };
    } catch (_) {
        return { before: '', after: '' };
    }
}

// Track selection changes
var selectionTimeout = null;
if (typeof window._macwikiNativeHighlightingMenuEnabled === 'undefined') {
    window._macwikiNativeHighlightingMenuEnabled = false;
}

window.setNativeHighlightingMenuEnabled = function (enabled) {
    window._macwikiNativeHighlightingMenuEnabled = !!enabled;
    return window._macwikiNativeHighlightingMenuEnabled;
};

function currentSelectionPayload() {
    var selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) return null;

    var selectedText = selection.toString().trim();
    if (selectedText.length === 0) return null;

    var range = selection.getRangeAt(0);
    var rect = range.getBoundingClientRect();
    var container = range.startContainer.parentElement || range.startContainer;
    var context = getContext(range, 50);

    return {
        text: selectedText,
        elementPath: getElementPath(container),
        startOffset: range.startOffset,
        length: selectedText.length,
        contextBefore: context.before,
        contextAfter: context.after,
        sectionTitle: getSectionTitle(container),
        rect: {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        }
    };
}

document.addEventListener('mouseup', function (e) {
    // Debounce to avoid rapid fire
    clearTimeout(selectionTimeout);
    selectionTimeout = setTimeout(function () {
        var payload = currentSelectionPayload();
        if (!payload) return;

        if (window._macwikiNativeHighlightingMenuEnabled &&
            window.webkit &&
            window.webkit.messageHandlers &&
            window.webkit.messageHandlers.textSelectionContextRequested) {
            payload.x = payload.rect.x + (payload.rect.width / 2);
            payload.y = payload.rect.y + payload.rect.height + 4;
            window.webkit.messageHandlers.textSelectionContextRequested.postMessage(payload);
            return;
        }

        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.textSelected) {
            window.webkit.messageHandlers.textSelected.postMessage(payload);
        }
    }, 100);
});

// Detect selection cleared
document.addEventListener('mousedown', function (e) {
    var selection = window.getSelection();
    if (selection.toString().trim().length > 0) {
        // Will likely clear on this click
        setTimeout(function () {
            if (window.getSelection().toString().trim().length === 0) {
                window.webkit.messageHandlers.selectionCleared.postMessage({});
            }
        }, 50);
    }
});

// Keyboard shortcut: Cmd+H to highlight
document.addEventListener('keydown', function (e) {
    if (e.metaKey && e.key === 'h') {
        var selection = window.getSelection();
        var selectedText = selection.toString().trim();
        if (selectedText.length > 0) {
            e.preventDefault();
            window.webkit.messageHandlers.highlightShortcut.postMessage({
                text: selectedText
            });
        }
    }
});

var _macwikiTOCCache = null;
var _macwikiReferencesCache = null;
var _macwikiTOCCacheDirty = true;
var _macwikiReferencesCacheDirty = true;

function invalidateTOCAndHeadingCaches() {
    _macwikiTOCCache = null;
    _macwikiTOCCacheDirty = true;
    if (window._invalidateHeadingCache) window._invalidateHeadingCache();
}

function invalidateReferenceCache() {
    _macwikiReferencesCache = null;
    _macwikiReferencesCacheDirty = true;
}

window._macwikiInvalidateTOCCache = invalidateTOCAndHeadingCaches;
window._macwikiInvalidateReferenceCache = invalidateReferenceCache;

// Reader appearance customization
window.setReaderAppearance = function (options) {
    if (!options) return false;
    var root = document.documentElement;

    function applyOption(optionKey, cssVarName) {
        if (!Object.prototype.hasOwnProperty.call(options, optionKey)) return;
        var value = options[optionKey];
        if (value === undefined || value === null) return;
        root.style.setProperty(cssVarName, String(value));
    }

    applyOption('bodyFontFamily', '--reader-body-font');
    applyOption('headingFontFamily', '--reader-heading-font');
    applyOption('fontSize', '--reader-font-size');
    applyOption('lineHeight', '--reader-line-height');
    applyOption('paragraphSpacing', '--reader-paragraph-spacing');
    applyOption('contentWidth', '--reader-max-width');
    applyOption('inlinePadding', '--reader-inline-padding');
    applyOption('headingScale', '--reader-heading-scale');

    if (window._macwikiInvalidateReaderLayoutMetrics) {
        window._macwikiInvalidateReaderLayoutMetrics();
    }

    return true;
};

// Extract article table of contents from heading nodes
window.extractTableOfContents = function () {
    if (!_macwikiTOCCacheDirty && _macwikiTOCCache) {
        return _macwikiTOCCache;
    }
    // Heading IDs can change while building TOC, so invalidate section-position cache.
    if (window._invalidateHeadingCache) window._invalidateHeadingCache();
    var headings = Array.prototype.slice.call(document.querySelectorAll('h2, h3, h4'));
    var idCounts = {};

    _macwikiTOCCache = headings
        .map(function (node) {
            var title = (node.textContent || '').trim();
            if (!title) return null;
            if (matchReferenceSectionTitle(title)) return null;

            var level = parseInt(node.tagName.substring(1), 10);
            if (!level || level < 1) return null;

            var slug = title
                .toLowerCase()
                .replace(/[^a-z0-9]+/g, '-')
                .replace(/^-+|-+$/g, '')
                .substring(0, 64);

            if (!slug) slug = 'section';
            var baseId = 'mw-section-' + slug;
            var count = idCounts[baseId] || 0;
            idCounts[baseId] = count + 1;
            var id = count === 0 ? baseId : (baseId + '-' + count);
            node.id = id;

            return {
                id: id,
                title: title,
                level: level
            };
        })
        .filter(function (item) { return !!item; });
    _macwikiTOCCacheDirty = false;
    return _macwikiTOCCache;
};

window.scrollToSection = function (id) {
    if (!id) return Promise.resolve(false);
    var target = document.getElementById(id);
    if (!target) return Promise.resolve(false);

    var offset = 84;
    var top = target.getBoundingClientRect().top + window.scrollY - offset;
    if (window._macwikiSmoothScrollToY) {
        return new Promise(function (resolve) {
            var didStart = window._macwikiSmoothScrollToY(top, {
                reason: 'toc',
                nativeSmooth: true,
                pixelsPerMs: 2.0,
                minDurationMs: 320,
                maxDurationMs: 1400,
                onComplete: resolve
            });
            if (!didStart) resolve(false);
        });
    }
    window.scrollTo({ top: top, behavior: 'auto' });
    return Promise.resolve(true);
};

window.scrollToAnchor = function (fragment) {
    if (!fragment) return false;

    var normalized = String(fragment).replace(/^#/, '');
    if (!normalized) return false;

    var decoded = normalized;
    try {
        decoded = decodeURIComponent(normalized);
    } catch (_) {
        decoded = normalized;
    }

    var target = document.getElementById(decoded) || document.getElementById(normalized);
    if (!target) {
        var namedDecoded = document.getElementsByName(decoded);
        if (namedDecoded && namedDecoded.length > 0) {
            target = namedDecoded[0];
        } else {
            var namedRaw = document.getElementsByName(normalized);
            if (namedRaw && namedRaw.length > 0) target = namedRaw[0];
        }
    }
    if (!target) return false;

    var offset = 84;
    var top = target.getBoundingClientRect().top + window.scrollY - offset;
    if (window._macwikiSetProgrammaticScrollMode) {
        window._macwikiSetProgrammaticScrollMode(320);
    }
    window.scrollTo({ top: top, behavior: 'auto' });
    return true;
};

function normalizeReferenceHeading(title) {
    return String(title || '')
        .replace(/\[edit\]/gi, '')
        .replace(/\s+/g, ' ')
        .trim();
}

function matchReferenceSectionTitle(title) {
    var normalized = normalizeReferenceHeading(title).toLowerCase();
    if (!normalized) return null;

    var matches = [
        { key: 'references', aliases: ['references', 'notes', 'citations'] },
        { key: 'further-reading', aliases: ['further reading'] },
        { key: 'bibliography', aliases: ['bibliography', 'works cited', 'sources'] },
        { key: 'external-links', aliases: ['external links', 'external link'] }
    ];

    for (var i = 0; i < matches.length; i += 1) {
        var entry = matches[i];
        for (var j = 0; j < entry.aliases.length; j += 1) {
            if (normalized === entry.aliases[j]) {
                return entry.key;
            }
        }
    }

    return null;
}

function resolveHeadingTitle(node) {
    if (!node) return '';
    var headline = node.querySelector('.mw-headline');
    var text = headline ? headline.textContent : node.textContent;
    return normalizeReferenceHeading(text);
}

window._macwikiCollectReferenceSections = function () {
    var headings = Array.prototype.slice.call(document.querySelectorAll('h2, h3'));
    var sections = [];
    var seen = {};

    headings.forEach(function (heading) {
        var title = resolveHeadingTitle(heading);
        var matchKey = matchReferenceSectionTitle(title);
        if (!matchKey) return;

        var section = heading.closest('section');
        if (!section) return;

        var id = section.getAttribute('data-mw-section-id') || matchKey;
        if (seen[id]) return;
        seen[id] = true;

        sections.push({
            id: String(id),
            key: matchKey,
            title: title || matchKey,
            element: section
        });
    });

    return sections;
};

window._macwikiTagReferenceSections = function () {
    var sections = window._macwikiCollectReferenceSections();
    var hasReferenceWrap = !!document.querySelector('.mw-references-wrap');

    sections.forEach(function (section) {
        if (section.element && section.element.classList) {
            section.element.classList.add('macwiki-reference-section');
            section.element.setAttribute('data-macwiki-reference-section', section.key || '');
        }
    });

    if (sections.length || hasReferenceWrap) {
        document.documentElement.classList.add('macwiki-hide-reference-sections');
    }
    return sections;
};

function normalizeReferenceText(text) {
    return String(text || '')
        .replace(/\s+/g, ' ')
        .trim();
}

function collectReferenceLinks(node) {
    if (!node || !node.querySelectorAll) return [];
    var anchors = node.querySelectorAll('a[href]');
    var links = [];
    var seen = {};

    anchors.forEach(function (anchor) {
        var href = (anchor.getAttribute('href') || '').trim();
        if (!href || href.charAt(0) === '#') return;
        var resolved;
        try {
            resolved = new URL(href, document.baseURI);
        } catch (_) {
            return;
        }
        if (!resolved || (resolved.protocol !== 'http:' && resolved.protocol !== 'https:')) return;
        var urlString = resolved.toString();
        if (seen[urlString]) return;
        seen[urlString] = true;
        links.push(urlString);
    });

    return links;
}

function extractReferenceItemsFromList(list) {
    if (!list) return [];
    var items = [];
    var listItems = list.querySelectorAll('li[id]');
    var group = list.getAttribute('data-mw-group') || null;

    listItems.forEach(function (item) {
        var id = item.getAttribute('id');
        if (!id) return;
        var label = item.getAttribute('data-mw-footnote-number');
        if (!label) {
            var backLink = item.querySelector('.pcs-ref-back-link');
            if (backLink) {
                label = normalizeReferenceText(backLink.textContent);
                label = label.replace(/^\[|\]$/g, '').trim();
            }
        }

        var referenceNode =
            item.querySelector('.mw-reference-text') ||
            item.querySelector('.reference-text') ||
            item;

        var text = normalizeReferenceText(referenceNode.textContent);
        if (!text) return;

        items.push({
            id: id,
            label: label || null,
            text: text,
            html: null,
            links: collectReferenceLinks(referenceNode),
            group: group
        });
    });

    return items;
}

function extractReferenceItemsFromSection(section, sectionKey) {
    if (!section) return [];
    if (sectionKey === 'references') {
        var lists = section.querySelectorAll('ol.references, ol.mw-references');
        var items = [];
        lists.forEach(function (list) {
            items = items.concat(extractReferenceItemsFromList(list));
        });
        return items;
    }

    var items = [];
    var listItems = section.querySelectorAll('ul > li, ol > li');
    var index = 0;

    listItems.forEach(function (item) {
        var text = normalizeReferenceText(item.textContent);
        if (!text) return;
        var id = 'ref-' + sectionKey + '-' + index;
        index += 1;

        items.push({
            id: id,
            label: null,
            text: text,
            html: null,
            links: collectReferenceLinks(item),
            group: null
        });
    });

    return items;
}

window.extractReferences = function () {
    if (!_macwikiReferencesCacheDirty && _macwikiReferencesCache) {
        return _macwikiReferencesCache;
    }
    var sections = window._macwikiCollectReferenceSections();
    var results = [];
    var usedReferenceSection = false;

    sections.forEach(function (section) {
        var items = extractReferenceItemsFromSection(section.element, section.key);
        if (!items.length) return;
        if (section.key === 'references') usedReferenceSection = true;
        results.push({
            id: section.id,
            title: section.title,
            key: section.key,
            items: items
        });
    });

    if (!usedReferenceSection) {
        var fallbackLists = document.querySelectorAll('ol.references, ol.mw-references');
        var fallbackItems = [];
        fallbackLists.forEach(function (list) {
            fallbackItems = fallbackItems.concat(extractReferenceItemsFromList(list));
        });
        if (fallbackItems.length) {
            results.push({
                id: 'references-fallback',
                title: 'References',
                key: 'references',
                items: fallbackItems
            });
        }
    }

    _macwikiReferencesCache = results;
    _macwikiReferencesCacheDirty = false;
    return _macwikiReferencesCache;
};

// Tag and hide reference sections by default to keep reading flow uninterrupted.
window._macwikiTagReferenceSections();

// Cached heading positions for fast visible-section lookup during scroll.
// Rebuilt on demand when invalidated (resize, TOC extract, first scroll).
(function () {
    var _cachedHeadings = null; // [{id, element, offsetTop}]
    var _invalidationScheduled = false;
    var _headingLayoutObserver = null;

    function rebuildHeadingCache() {
        var headings = Array.prototype.slice.call(document.querySelectorAll('h2[id], h3[id], h4[id]'));
        _cachedHeadings = headings.map(function (h) {
            return {
                id: h.id,
                element: h,
                offsetTop: h.getBoundingClientRect().top + window.scrollY
            };
        });
    }

    function invalidateHeadingCache() {
        _cachedHeadings = null;
    }

    function scheduleHeadingInvalidation(delayMs) {
        if (_invalidationScheduled) return;
        _invalidationScheduled = true;
        var run = function () {
            _invalidationScheduled = false;
            invalidateHeadingCache();
        };
        if (delayMs && delayMs > 0) {
            setTimeout(run, delayMs);
            return;
        }
        if (window.requestAnimationFrame) {
            requestAnimationFrame(run);
        } else {
            setTimeout(run, 16);
        }
    }

    window._invalidateHeadingCache = function () {
        invalidateHeadingCache();
    };

    function activeHeadingIndex(scrollTop) {
        var lo = 0, hi = _cachedHeadings.length - 1;
        var activeIndex = -1;
        while (lo <= hi) {
            var mid = (lo + hi) >>> 1;
            if (_cachedHeadings[mid].offsetTop <= scrollTop) {
                activeIndex = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return activeIndex;
    }

    window.currentVisibleSectionId = function () {
        if (!_cachedHeadings) {
            rebuildHeadingCache();
        }
        if (!_cachedHeadings || !_cachedHeadings.length) return null;

        var scrollTop = window.scrollY + 110; // threshold from top
        var activeIndex = activeHeadingIndex(scrollTop);

        // Wikipedia images, tables, and fonts can finish laying out after the
        // initial cache was built. Validate only the current candidate so the
        // normal path stays O(log n) with one live geometry read. A shifted
        // candidate means the whole cache is stale; rebuild once before
        // publishing a section rather than leaving Contents stuck on an old row.
        if (activeIndex >= 0) {
            var candidate = _cachedHeadings[activeIndex];
            var liveOffsetTop = candidate.element.getBoundingClientRect().top + window.scrollY;
            if (Math.abs(liveOffsetTop - candidate.offsetTop) > 2) {
                rebuildHeadingCache();
                activeIndex = activeHeadingIndex(scrollTop);
            }
        }

        return activeIndex >= 0 ? _cachedHeadings[activeIndex].id : null;
    };

    // Invalidate cache on layout events that shift heading offsets.
    window.addEventListener('resize', function () {
        scheduleHeadingInvalidation(24);
    });
    window.addEventListener('load', function () {
        scheduleHeadingInvalidation(24);
    });
    document.addEventListener('load', function (e) {
        var target = e && e.target;
        if (!target || target.tagName !== 'IMG') return;
        scheduleHeadingInvalidation(18);
    });

    if (window.ResizeObserver && document.body) {
        _headingLayoutObserver = new ResizeObserver(function () {
            scheduleHeadingInvalidation(18);
        });
        _headingLayoutObserver.observe(document.body);
        window.addEventListener('pagehide', function () {
            if (_headingLayoutObserver) {
                _headingLayoutObserver.disconnect();
                _headingLayoutObserver = null;
            }
        }, { once: true });
    }
})();

// Highlight Rendering Support using CSS Custom Highlight API
// This is the modern, Apple-native approach that doesn't modify the DOM
(function () {
    // Inject CSS for highlight styling
    var style = document.createElement('style');
    style.textContent = `
        /* CSS Custom Highlight API styles */
        ::highlight(macwiki-yellow) {
            background-color: rgba(255, 219, 77, 0.42);
            color: inherit;
        }
        ::highlight(macwiki-blue) {
            background-color: rgba(132, 205, 255, 0.40);
            color: inherit;
        }
        ::highlight(macwiki-pink) {
            background-color: rgba(255, 154, 190, 0.38);
            color: inherit;
        }
        ::highlight(macwiki-orange) {
            background-color: rgba(255, 184, 102, 0.42);
            color: inherit;
        }
        html.macwiki-differentiate-without-color ::highlight(macwiki-yellow),
        html.macwiki-differentiate-without-color ::highlight(macwiki-blue),
        html.macwiki-differentiate-without-color ::highlight(macwiki-pink),
        html.macwiki-differentiate-without-color ::highlight(macwiki-orange) {
            text-decoration-line: underline;
            text-decoration-thickness: 0.12em;
            text-underline-offset: 0.14em;
        }

        /* Fallback for older browsers using mark elements */
        .macwiki-highlight {
            border-radius: 3px;
            padding: 2px 1px;
            margin: 0 -1px;
            color: inherit;
            -webkit-text-fill-color: currentColor;
            cursor: pointer;
            transition: filter 0.15s ease, box-shadow 0.15s ease;
            box-decoration-break: clone;
            -webkit-box-decoration-break: clone;
        }
        .macwiki-highlight:hover {
            filter: brightness(0.92);
            box-shadow: 0 0 0 2px currentColor;
        }
        html.macwiki-differentiate-without-color .macwiki-highlight {
            text-decoration-line: underline;
            text-decoration-thickness: 0.12em;
            text-underline-offset: 0.14em;
        }
        @media (prefers-color-scheme: dark) {
            .macwiki-highlight:hover {
                filter: brightness(1.15);
            }
        }
    `;
    document.head.appendChild(style);

    // Store ranges for each highlight ID (for click detection and removal)
    window._macwikiHighlightRanges = {};
})();

// Check if CSS Custom Highlight API is available
window.hasCSSHighlights = function () {
    return typeof CSS !== 'undefined' && CSS.highlights;
};

// Map color names to CSS highlight names
function getHighlightName(color) {
    if (color.includes('255, 219, 77') || color.includes('255, 213, 0') || color.includes('yellow')) return 'macwiki-yellow';
    if (color.includes('132, 205, 255') || color.includes('59, 130, 246') || color.includes('blue')) return 'macwiki-blue';
    if (color.includes('255, 154, 190') || color.includes('236, 72, 153') || color.includes('pink')) return 'macwiki-pink';
    if (color.includes('255, 184, 102') || color.includes('249, 115, 22') || color.includes('orange')) return 'macwiki-orange';
    return 'macwiki-yellow'; // default
}

// IMMEDIATE HIGHLIGHT using CSS Custom Highlight API
window.highlightCurrentSelection = function (id, color) {
    var sel = window.getSelection();
    if (!sel || sel.rangeCount === 0 || sel.toString().trim().length === 0) {
        return false;
    }

    var range = sel.getRangeAt(0).cloneRange();
    sel.removeAllRanges();

    if (window.hasCSSHighlights()) {
        // Use CSS Custom Highlight API (modern approach)
        var highlightName = getHighlightName(color);

        // Get or create the Highlight object for this color
        var highlight = CSS.highlights.get(highlightName);
        if (!highlight) {
            highlight = new Highlight();
            CSS.highlights.set(highlightName, highlight);
        }

        // Add the range to the highlight
        highlight.add(range);

        // Store range for later removal/click detection
        window._macwikiHighlightRanges[id] = {
            range: range,
            highlightName: highlightName,
            color: color
        };

        return true;
    } else {
        // Fallback: use mark elements (for older WebKit)
        return highlightWithMarks(id, range, color);
    }
};

// Fallback highlight using mark elements
function highlightWithMarks(id, range, color) {
    try {
        var mark = document.createElement('mark');
        mark.className = 'macwiki-highlight';
        mark.setAttribute('data-highlight-id', id);
        mark.style.backgroundColor = color;

        mark.addEventListener('click', function (e) {
            e.stopPropagation();
            window.webkit.messageHandlers.highlightClicked.postMessage({ id: id });
        });

        range.surroundContents(mark);
        return true;
    } catch (e) {
        // If surroundContents fails (cross-element), use extractContents
        try {
            var contents = range.extractContents();
            var mark = document.createElement('mark');
            mark.className = 'macwiki-highlight';
            mark.setAttribute('data-highlight-id', id);
            mark.style.backgroundColor = color;
            mark.appendChild(contents);

            mark.addEventListener('click', function (e) {
                e.stopPropagation();
                window.webkit.messageHandlers.highlightClicked.postMessage({ id: id });
            });

            range.insertNode(mark);
            return true;
        } catch (e2) {
            return false;
        }
    }
}

// Function to apply highlights from stored data (page reload)
window.applyHighlights = function (highlights) {
    // Clear existing CSS highlights
    if (window.hasCSSHighlights()) {
        CSS.highlights.clear();
    }
    window._macwikiHighlightRanges = {};

    // Remove any existing mark elements
    document.querySelectorAll('.macwiki-highlight').forEach(function (el) {
        var parent = el.parentNode;
        while (el.firstChild) {
            parent.insertBefore(el.firstChild, el);
        }
        parent.removeChild(el);
        parent.normalize();
    });

    var successCount = 0;
    var failedIds = [];
    // Build one text-search cache for the batch to avoid repeated full-document
    // scans per highlight on long articles.
    var searchCache = highlights.length > 1 ? buildTextSearchCache(document.body) : null;
    highlights.forEach(function (h) {
        var success = restoreHighlight(
            h.id,
            h.text,
            h.color,
            h.contextBefore,
            h.contextAfter,
            searchCache,
            false,
            h.elementPath || '',
            Number.isInteger(h.startOffset) ? h.startOffset : 0
        );
        if (success) {
            successCount++;
        } else if (h && h.id) {
            failedIds.push(h.id);
        }
    });

    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.highlightResult) {
        window.webkit.messageHandlers.highlightResult.postMessage({
            total: highlights.length,
            success: successCount,
            actualInDOM: successCount,
            failedIds: failedIds
        });
    }
};

// Retry a single highlight rehydrate without clearing existing highlights
window.retryHighlight = function (payload) {
    if (!payload) return false;
    var searchCache = buildTextSearchCache(document.body);
    return restoreHighlight(
        payload.id,
        payload.text,
        payload.color,
        payload.contextBefore,
        payload.contextAfter,
        searchCache,
        true,
        payload.elementPath || '',
        Number.isInteger(payload.startOffset) ? payload.startOffset : 0
    );
};

// Smoothly scroll to a highlight by id
window.scrollToHighlight = function (id) {
    if (!id || !window._macwikiHighlightRanges) return false;
    var entry = window._macwikiHighlightRanges[id];
    if (!entry || !entry.range) return false;

    var rect = entry.range.getBoundingClientRect();
    if (!rect) return false;

    var target = rect.top + window.scrollY - 120;
    if (window._macwikiSmoothScrollToY) {
        return window._macwikiSmoothScrollToY(target, {
            reason: 'highlight',
            nativeSmooth: true,
            pixelsPerMs: 2.4,
            minDurationMs: 240,
            maxDurationMs: 900
        });
    }

    var prefersReducedMotion = false;
    try {
        prefersReducedMotion =
            !!window.matchMedia &&
            !!window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    } catch (_) {
        prefersReducedMotion = false;
    }
    window.scrollTo({ top: target, behavior: prefersReducedMotion ? 'auto' : 'smooth' });
    return true;
};

// Restore a single highlight by finding text in document
function restoreHighlight(
    id,
    text,
    color,
    contextBefore,
    contextAfter,
    searchCache,
    allowNormalizedFallback,
    elementPath,
    startOffset
) {
    if (!text || text.length === 0) return false;

    // Prefer the stored DOM path. It is both faster and less ambiguous when the
    // same quote occurs several times, while the document-wide context search
    // remains the resilience fallback when Wikipedia changes its structure.
    var range = findTextRangeInAnchoredElement(
        text,
        elementPath,
        startOffset,
        allowNormalizedFallback
    );
    if (!range) {
        range = findTextRange(text, contextBefore, contextAfter, searchCache, document.body);
    }
    if (!range && allowNormalizedFallback) {
        range = findTextRangeNormalized(text, searchCache, document.body);
    }
    if (!range) {
        return false;
    }

    if (window.hasCSSHighlights()) {
        var highlightName = getHighlightName(color);
        var highlight = CSS.highlights.get(highlightName);
        if (!highlight) {
            highlight = new Highlight();
            CSS.highlights.set(highlightName, highlight);
        }
        highlight.add(range);

        window._macwikiHighlightRanges[id] = {
            range: range,
            highlightName: highlightName,
            color: color
        };
        return true;
    } else {
        return highlightWithMarks(id, range, color);
    }
}

function elementForStoredPath(elementPath) {
    if (!elementPath || typeof elementPath !== 'string') return null;

    var current = document.body;
    var segments = elementPath.split('/').filter(Boolean);
    for (var i = 0; i < segments.length; i++) {
        var match = /^([A-Za-z][A-Za-z0-9-]*)\[(\d+)\]$/.exec(segments[i]);
        if (!match) return null;

        var expectedTag = match[1].toLowerCase();
        var expectedIndex = Number(match[2]);
        if (!Number.isInteger(expectedIndex) || expectedIndex < 1) return null;

        var matchingIndex = 0;
        var resolvedChild = null;
        for (var childIndex = 0; childIndex < current.children.length; childIndex++) {
            var child = current.children[childIndex];
            if (child.tagName.toLowerCase() !== expectedTag) continue;
            matchingIndex++;
            if (matchingIndex === expectedIndex) {
                resolvedChild = child;
                break;
            }
        }

        if (!resolvedChild) return null;
        current = resolvedChild;
    }

    return current === document.body ? null : current;
}

function findTextRangeInAnchoredElement(text, elementPath, startOffset, allowNormalizedFallback) {
    var element = elementForStoredPath(elementPath);
    if (!element) return null;

    var searchText = text.trim();
    if (!searchText) return null;

    var elementCache = buildTextSearchCache(element);
    var offset = Number.isInteger(startOffset) ? startOffset : -1;
    if (offset >= 0 && elementCache.bodyText.slice(offset, offset + searchText.length) === searchText) {
        return createRangeFromOffsets(element, offset, offset + searchText.length, elementCache);
    }

    var range = findTextRange(text, '', '', elementCache, element);
    if (!range && allowNormalizedFallback) {
        range = findTextRangeNormalized(text, elementCache, element);
    }
    return range;
}

function buildTextSearchCache(root) {
    if (!root) return null;

    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
    var textNodes = [];
    var textChunks = [];
    var charCount = 0;
    var node;

    while (node = walker.nextNode()) {
        var value = node.textContent || '';
        var length = value.length;
        if (length === 0) continue;
        textNodes.push({
            node: node,
            start: charCount,
            end: charCount + length
        });
        textChunks.push(value);
        charCount += length;
    }

    return {
        bodyText: textChunks.join(''),
        textNodes: textNodes
    };
}

function findTextNodeEntryForOffset(textNodes, offset) {
    var low = 0;
    var high = textNodes.length - 1;

    while (low <= high) {
        var mid = (low + high) >> 1;
        var entry = textNodes[mid];
        if (offset < entry.start) {
            high = mid - 1;
        } else if (offset >= entry.end) {
            low = mid + 1;
        } else {
            return entry;
        }
    }

    return null;
}

// Find text and create a Range object
function findTextRange(text, contextBefore, contextAfter, searchCache, root) {
    var bodyText =
        (searchCache && typeof searchCache.bodyText === 'string')
            ? searchCache.bodyText
            : (document.body.textContent || '');
    var searchText = text.trim();

    // Try to find with context first for better accuracy
    var startIndex = -1;
    if (contextBefore && contextBefore.length > 0 && contextAfter && contextAfter.length > 0) {
        var combined = contextBefore + searchText + contextAfter;
        var combinedIndex = bodyText.indexOf(combined);
        if (combinedIndex !== -1) {
            startIndex = combinedIndex + contextBefore.length;
        }
    }

    if (startIndex === -1 && contextBefore && contextBefore.length > 0) {
        var contextIndex = bodyText.indexOf(contextBefore);
        if (contextIndex !== -1) {
            startIndex = bodyText.indexOf(searchText, contextIndex);
        }
    }

    if (startIndex === -1 && contextAfter && contextAfter.length > 0) {
        var afterIndex = bodyText.indexOf(contextAfter);
        if (afterIndex !== -1) {
            var beforeIndex = bodyText.lastIndexOf(searchText, afterIndex);
            if (beforeIndex !== -1) {
                startIndex = beforeIndex;
            }
        }
    }

    // Fallback to simple search
    if (startIndex === -1) {
        startIndex = bodyText.indexOf(searchText);
    }

    if (startIndex === -1) return null;

    var endIndex = startIndex + searchText.length;

    // Convert character offsets to Range
    return createRangeFromOffsets(root || document.body, startIndex, endIndex, searchCache);
}

function normalizeTextForSearch(text) {
    var normalized = '';
    var indexMap = [];
    var lastWasSpace = false;

    for (var i = 0; i < text.length; i++) {
        var ch = text[i];
        var isSpace = (ch === '\u00A0') || /\s/.test(ch);

        if (isSpace) {
            if (!lastWasSpace) {
                normalized += ' ';
                indexMap.push(i);
                lastWasSpace = true;
            }
            continue;
        }

        normalized += ch;
        indexMap.push(i);
        lastWasSpace = false;
    }

    return { text: normalized, indexMap: indexMap };
}

function normalizeSearchText(text) {
    var normalized = '';
    var lastWasSpace = false;

    for (var i = 0; i < text.length; i++) {
        var ch = text[i];
        var isSpace = (ch === '\u00A0') || /\s/.test(ch);
        if (isSpace) {
            if (!lastWasSpace) {
                normalized += ' ';
                lastWasSpace = true;
            }
            continue;
        }
        normalized += ch;
        lastWasSpace = false;
    }

    return normalized.trim();
}

function findTextRangeNormalized(text, searchCache, root) {
    var bodyText =
        (searchCache && typeof searchCache.bodyText === 'string')
            ? searchCache.bodyText
            : (document.body.textContent || '');
    var normalizedSearch = normalizeSearchText(text);
    if (!normalizedSearch || normalizedSearch.length === 0) return null;

    var normalizedBody = normalizeTextForSearch(bodyText);
    var index = normalizedBody.text.indexOf(normalizedSearch);
    if (index === -1) return null;

    var startOffset = normalizedBody.indexMap[index];
    var endIndex = index + normalizedSearch.length - 1;
    if (endIndex < 0 || endIndex >= normalizedBody.indexMap.length) return null;
    var endOffset = normalizedBody.indexMap[endIndex] + 1;

    return createRangeFromOffsets(root || document.body, startOffset, endOffset, searchCache);
}

// Create Range from character offsets
function createRangeFromOffsets(root, startOffset, endOffset, searchCache) {
    if (searchCache && searchCache.textNodes && searchCache.textNodes.length > 0) {
        var textNodes = searchCache.textNodes;
        var startEntry = findTextNodeEntryForOffset(textNodes, startOffset);
        var safeEndLookupOffset = Math.max(endOffset - 1, startOffset);
        var endEntry = findTextNodeEntryForOffset(textNodes, safeEndLookupOffset);

        if (startEntry && endEntry) {
            var cachedRange = document.createRange();
            cachedRange.setStart(startEntry.node, startOffset - startEntry.start);
            cachedRange.setEnd(endEntry.node, endOffset - endEntry.start);
            return cachedRange;
        }
    }

    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null, false);
    var charCount = 0;
    var startNode = null, startNodeOffset = 0;
    var endNode = null, endNodeOffset = 0;
    var node;

    while (node = walker.nextNode()) {
        var nodeLength = node.textContent.length;

        if (!startNode && charCount + nodeLength > startOffset) {
            startNode = node;
            startNodeOffset = startOffset - charCount;
        }

        if (charCount + nodeLength >= endOffset) {
            endNode = node;
            endNodeOffset = endOffset - charCount;
            break;
        }

        charCount += nodeLength;
    }

    if (startNode && endNode) {
        var range = document.createRange();
        range.setStart(startNode, startNodeOffset);
        range.setEnd(endNode, endNodeOffset);
        return range;
    }

    return null;
}

// Remove a specific highlight
window.removeHighlight = function (id) {
    // Remove from CSS highlights
    var stored = window._macwikiHighlightRanges[id];
    if (stored && window.hasCSSHighlights()) {
        var highlight = CSS.highlights.get(stored.highlightName);
        if (highlight) {
            highlight.delete(stored.range);
        }
        delete window._macwikiHighlightRanges[id];
    }

    // Also remove any mark elements (fallback)
    var elements = document.querySelectorAll('[data-highlight-id="' + id + '"]');
    elements.forEach(function (el) {
        var parent = el.parentNode;
        while (el.firstChild) {
            parent.insertBefore(el.firstChild, el);
        }
        parent.removeChild(el);
        parent.normalize();
    });
};

// Update highlight color
window.updateHighlightColor = function (id, newColor) {
    var stored = window._macwikiHighlightRanges[id];
    if (!stored) return false;

    if (window.hasCSSHighlights()) {
        // Remove from old highlight group
        var oldHighlight = CSS.highlights.get(stored.highlightName);
        if (oldHighlight) {
            oldHighlight.delete(stored.range);
        }

        // Add to new highlight group
        var newHighlightName = getHighlightName(newColor);
        var newHighlight = CSS.highlights.get(newHighlightName);
        if (!newHighlight) {
            newHighlight = new Highlight();
            CSS.highlights.set(newHighlightName, newHighlight);
        }
        newHighlight.add(stored.range);

        // Update stored info
        stored.highlightName = newHighlightName;
        stored.color = newColor;
        return true;
    }

    // Fallback for mark elements
    var el = document.querySelector('[data-highlight-id="' + id + '"]');
    if (el) {
        el.style.backgroundColor = newColor;
        return true;
    }
    return false;
};

// Detect clicks on highlights (for CSS highlights)
document.addEventListener('click', function (e) {
    if (!window.hasCSSHighlights()) return;

    // Check if click is within any stored highlight range
    var sel = window.getSelection();
    // Allow clicking even without selection (caret from point handles it)

    // Create a collapsed range at click point
    var range = document.caretRangeFromPoint(e.clientX, e.clientY);
    if (!range) return;

    // Check against all stored ranges
    for (var id in window._macwikiHighlightRanges) {
        var stored = window._macwikiHighlightRanges[id];
        if (stored.range.isPointInRange(range.startContainer, range.startOffset)) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.highlightClicked) {
                window.webkit.messageHandlers.highlightClicked.postMessage({ id: id });
            }
            break;
        }
    }
});

// Detect Right-Clicks on Highlights
document.addEventListener('contextmenu', function (e) {
    if (e.defaultPrevented) return; // Let link handler or other handlers take precedence

    // 1. Check for CSS Highlight
    if (window.hasCSSHighlights()) {
        var range = document.caretRangeFromPoint(e.clientX, e.clientY);
        if (range) {
            for (var id in window._macwikiHighlightRanges) {
                var stored = window._macwikiHighlightRanges[id];
                if (stored.range.isPointInRange(range.startContainer, range.startOffset)) {
                    e.preventDefault();
                    e.stopPropagation();
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.highlightRightClicked) {
                        window.webkit.messageHandlers.highlightRightClicked.postMessage({
                            id: id,
                            x: e.clientX,
                            y: e.clientY
                        });
                    }
                    return;
                }
            }
        }
    } else {
        // 2. Fallback: Check for mark element
        var target = e.target;
        var mark = target.closest('.macwiki-highlight');
        if (mark) {
            e.preventDefault();
            e.stopPropagation();
            var id = mark.getAttribute('data-highlight-id');
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.highlightRightClicked) {
                window.webkit.messageHandlers.highlightRightClicked.postMessage({
                    id: id,
                    x: e.clientX,
                    y: e.clientY
                });
            }
        }
    }
});

// Detect right-click on active text selection for native highlight creation menu.
document.addEventListener('contextmenu', function (e) {
    if (e.defaultPrevented) return;
    if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.textSelectionContextRequested) {
        return;
    }

    var payload = currentSelectionPayload();
    if (!payload) return;

    e.preventDefault();
    e.stopPropagation();
    payload.x = e.clientX;
    payload.y = e.clientY;
    window.webkit.messageHandlers.textSelectionContextRequested.postMessage(payload);
});
