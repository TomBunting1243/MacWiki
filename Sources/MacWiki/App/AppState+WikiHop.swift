import Foundation

extension AppState {
    var isWikiHopNavigationLocked: Bool {
        wikiHopSession?.status == .active
    }

    private var isWikiHopPostV1FeatureEnabled: Bool {
        MacWikiDefaults.current.bool(forKey: wikiHopPostV1FeatureKey)
    }

    private var isWikiHopExperimentEnabled: Bool {
        MacWikiDefaults.current.bool(forKey: ExperimentFlag.wikiHopPOCEnabled.key)
    }

    private var isWikiHopRuntimeEnabled: Bool {
        isWikiHopPostV1FeatureEnabled && isWikiHopExperimentEnabled
    }

    func startWikiHop(mode: WikiHopSession.Mode, start: Article, target: Article) {
        wikiHopSession = WikiHopSession(mode: mode, startArticle: start, targetArticle: target)
    }

    func failWikiHop(reason: String) {
        guard var session = wikiHopSession, session.status == .active else { return }
        session.status = .failed
        session.failureReason = reason
        session.completedAt = Date()
        wikiHopSession = session
        save()
    }

    func completeWikiHop() {
        guard var session = wikiHopSession, session.status == .active else { return }
        session.status = .completed
        session.completedAt = Date()
        wikiHopSession = session
        save()
    }

    func incrementWikiHopClicks(currentTitle: String) {
        guard var session = wikiHopSession, session.status == .active else { return }

        let normalizedCurrent = ReadStateSync.normalizedTitle(session.currentTitle)
        let normalizedNew = ReadStateSync.normalizedTitle(currentTitle)

        if normalizedCurrent != normalizedNew {
            session.clickCount += 1
            session.currentTitle = currentTitle
            wikiHopSession = session
            save()
        }
    }

    func updateWikiHopCurrentTitle(_ title: String) {
        guard var session = wikiHopSession else { return }
        session.currentTitle = title
        wikiHopSession = session
    }

    /// Check if the title matches the target. Redirect resolution can layer on this later.
    func checkWikiHopWin(title: String) -> Bool {
        guard let session = wikiHopSession, session.status == .active else { return false }
        return ReadStateSync.normalizedTitle(title) == ReadStateSync.normalizedTitle(session.targetArticle.title)
    }

    /// Dismisses any active/completed Wiki-Hop session and removes lock/overlay state.
    func dismissWikiHopSession() {
        guard wikiHopSession != nil else { return }
        wikiHopSession = nil
        save()
    }

    /// Centralized settings entry point for Wiki-Hop experiment state changes.
    func setWikiHopExperimentEnabled(_ isEnabled: Bool) {
        let resolvedEnabled = isEnabled && isWikiHopPostV1FeatureEnabled
        MacWikiDefaults.current.set(resolvedEnabled, forKey: ExperimentFlag.wikiHopPOCEnabled.key)
        applyWikiHopExperimentState(isEnabled: resolvedEnabled)
    }

    /// Applies experiment gates to runtime state using current persisted defaults.
    func synchronizeExperimentStateFromDefaults() {
        if !isWikiHopPostV1FeatureEnabled, isWikiHopExperimentEnabled {
            MacWikiDefaults.current.set(false, forKey: ExperimentFlag.wikiHopPOCEnabled.key)
        }
        applyWikiHopExperimentState(isEnabled: isWikiHopRuntimeEnabled)
    }

    private func applyWikiHopExperimentState(isEnabled: Bool) {
        guard !isEnabled else { return }
        dismissWikiHopSession()
        enforceDiscoverStartModeFallbackIfNeeded()
    }

    private func enforceDiscoverStartModeFallbackIfNeeded() {
        let defaults = MacWikiDefaults.current
        guard defaults.string(forKey: DiscoverStartMode.storageKey) == DiscoverStartMode.wikiHop.rawValue else {
            return
        }
        defaults.set(DiscoverStartMode.discoverFeed.rawValue, forKey: DiscoverStartMode.storageKey)
    }
}
