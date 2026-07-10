import Foundation

extension AppState {
    /// Request a state save (debounced).
    func requestSave() {
        guard persistenceMode.isEnabled else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }

    /// Flush pending state to disk immediately, used for lifecycle transitions.
    func flushSaveNow() {
        guard persistenceMode.isEnabled else { return }
        saveTask?.cancel()
        tabSessionStore.flushSaveNow()
        performSave(sync: true)
    }

    @MainActor
    private func performSave() {
        save()
    }

    @MainActor
    private func performSave(sync: Bool) {
        save(sync: sync)
    }

    func save() {
        save(sync: false)
    }

    func save(sync: Bool) {
        guard persistenceMode.isEnabled else { return }
        let state = SavedState(
            recentArticles: recentArticles,
            wikiHopSession: wikiHopSession
        )

        let targetURL = persistenceURL

        if sync {
            if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
                Self.writeState(state, to: targetURL)
            } else {
                persistenceQueue.sync {
                    Self.writeState(state, to: targetURL)
                }
            }
        } else {
            persistenceQueue.async { [state] in
                Self.writeState(state, to: targetURL)
            }
        }
    }

    func load() {
        guard persistenceMode.isEnabled else { return }
        guard let url = persistenceURL else { return }
        let loadStartedAt = CFAbsoluteTimeGetCurrent()

        let loadResult: SavedStateLoadResult
        if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
            loadResult = Self.readSavedState(from: url)
        } else {
            loadResult = persistenceQueue.sync {
                Self.readSavedState(from: url)
            }
        }

        switch loadResult {
        case .missing:
            migrateLegacyStateIfNeeded()
            return
        case .success(let state, let byteCount):
            recentArticles = state.recentArticles

            if var session = state.wikiHopSession {
                if session.mode == .rush && session.status == .active {
                    session.status = .failed
                    session.failureReason = "Run canceled (app closed during Rush)"
                    session.completedAt = Date()
                }
                wikiHopSession = session
            }

            PerformanceMetricsStore.shared.record(
                kind: .sessionRestore,
                durationMs: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
                detail: "tabs=\(openTabs.count) recents=\(recentArticles.count) bytes=\(byteCount)"
            )
        case .failure(let error, let byteCount):
            appStateLogger.error("Failed to decode state; starting fresh: \(error.localizedDescription, privacy: .public)")
            let backup = url.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            PerformanceMetricsStore.shared.record(
                kind: .sessionRestore,
                durationMs: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
                detail: "failed bytes=\(byteCount ?? 0)"
            )
        }
    }

    func migrateLegacyStateIfNeeded() {
        guard persistenceMode.isEnabled else { return }
        guard let legacyURL = legacyStateURL else { return }

        let loadResult: SavedStateLoadResult
        if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
            loadResult = Self.readLegacySavedState(from: legacyURL)
        } else {
            loadResult = persistenceQueue.sync {
                Self.readLegacySavedState(from: legacyURL)
            }
        }

        guard case .success(let state, _) = loadResult else { return }
        recentArticles = state.recentArticles

        if var session = state.wikiHopSession {
            if session.mode == .rush && session.status == .active {
                session.status = .failed
                session.failureReason = "Run canceled (app closed during Rush)"
                session.completedAt = Date()
            }
            wikiHopSession = session
        }

        flushSaveNow()
    }

    /// Reset app-level runtime and persisted navigation/state to defaults.
    /// SwiftData model deletion and cache clears are handled by the caller.
    func resetForFactoryDefaults() {
        saveTask?.cancel()
        recentUpdateWorkItem?.cancel()
        saveTask = nil
        recentUpdateWorkItem = nil
        pendingRecentArticles.removeAll()

        resetOpenArticleMutationState()
        tabSessionStore.resetForFactoryDefaults()
        recentArticles.removeAll()
        wikiHopSession = nil

        setNavigationColumnsVisible(true)
        inspectorVisible = true
        inspectorMode = .info
        showSearch = false
        resetFindOnPageState()
        showAddToList = false
        searchContext = .navigation

        resetArticlePresentationState()
        resetHighlightWorkflowState()
        resetReaderCacheState()

        if persistenceMode.isEnabled, let url = persistenceURL {
            try? FileManager.default.removeItem(at: url)
            let backup = url.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.removeItem(at: backup)
        }

        if persistenceMode.isEnabled {
            performSave(sync: true)
        }
    }

    private var persistenceURL: URL? {
        guard persistenceMode.isEnabled else { return nil }
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let appDir = supportDir.appendingPathComponent("MacWiki")

        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }

        return appDir.appendingPathComponent("app-state.json")
    }

    private var legacyStateURL: URL? {
        guard persistenceMode.isEnabled else { return nil }
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return supportDir.appendingPathComponent("MacWiki").appendingPathComponent("state.json")
    }

    nonisolated private static func writeState(_ state: SavedState, to url: URL?) {
        guard let url else { return }
        do {
            let text = try JSONEncoder().encode(state)
            try text.write(to: url, options: [.atomic])
        } catch {
            appStateLogger.error("Failed to save state: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func readSavedState(from url: URL) -> SavedStateLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            do {
                let state = try JSONDecoder().decode(SavedState.self, from: data)
                return .success(state, byteCount: data.count)
            } catch {
                return .failure(error, byteCount: data.count)
            }
        } catch {
            return .failure(error, byteCount: nil)
        }
    }

    nonisolated private static func readLegacySavedState(from url: URL) -> SavedStateLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            do {
                let state = try JSONDecoder().decode(LegacySavedState.self, from: data)
                return .success(
                    SavedState(
                        recentArticles: state.recentArticles,
                        wikiHopSession: state.wikiHopSession
                    ),
                    byteCount: data.count
                )
            } catch {
                return .failure(error, byteCount: data.count)
            }
        } catch {
            return .failure(error, byteCount: nil)
        }
    }

    private struct LegacySavedState: Codable {
        let recentArticles: [Article]
        let wikiHopSession: WikiHopSession?
    }

    private enum SavedStateLoadResult {
        case missing
        case success(SavedState, byteCount: Int)
        case failure(Error, byteCount: Int?)
    }

    private struct SavedState: Codable {
        let recentArticles: [Article]
        let wikiHopSession: WikiHopSession?
    }
}
