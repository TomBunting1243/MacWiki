import Foundation
import SwiftUI
import SwiftData
import MacWikiSettingsCatalog

struct SettingsAdvancedPane: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var cacheMetrics: WikipediaService.CacheMetrics?
    @State private var performanceMetrics = PerformanceMetricsStore.shared
    @State private var isCacheActionRunning = false
    @State private var cacheStatusMessage: String?
    @State private var pendingCacheAction: SettingsStorageAction?

    var body: some View {
        let section = SettingsCatalog.section(.advanced)

        SettingsPaneContainer(
            title: section.title,
            summary: section.summary,
            systemImage: section.systemImage
        ) {
            SettingsGroup("Storage", systemImage: "internaldrive") {
                storageMetrics
                storageActions
            }

            SettingsGroup("Performance", systemImage: "speedometer") {
                if performanceMetrics.hasSamples {
                    performanceMetricsCard(performanceMetrics.summaries)
                } else {
                    SettingsHelpText("Performance samples appear here after session restore, search, sidebar hydration, and reader opens run at least once.")
                }

                HStack {
                    Spacer()
                    AccessibleActionButton(
                        "Clear Performance Samples",
                        isEnabled: performanceMetrics.hasSamples
                    ) {
                        performanceMetrics.clear()
                    }
                }
            }
        }
        .task {
            await refreshCacheMetrics()
        }
        .alert(
            pendingCacheAction?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingCacheAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCacheAction = nil
                    }
                }
            ),
            presenting: pendingCacheAction
        ) { action in
            Button("Cancel", role: .cancel) {
                pendingCacheAction = nil
            }
            Button(action.confirmationButtonLabel, role: .destructive) {
                performCacheAction(action)
            }
        } message: { action in
            Text(action.confirmationMessage)
        }
    }

    @ViewBuilder
    private var storageMetrics: some View {
        if let cacheMetrics {
            cacheMetricsCard(cacheMetrics)
        } else {
            AppLoadingInlineLabel(
                text: "Loading cache stats...",
                tone: .accent,
                font: .footnote.weight(.medium)
            )
        }

        if let cacheStatusMessage {
            SettingsHelpText(cacheStatusMessage)
        }
    }

    private var storageActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AccessibleActionButton(
                    "Refresh Stats",
                    isEnabled: !isCacheActionRunning
                ) {
                    Task {
                        await refreshCacheMetrics()
                    }
                }

                if isCacheActionRunning {
                    AppLoadingActivityMark(tone: .accent)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                AccessibleActionButton(
                    "Clear Memory Cache",
                    isEnabled: !isCacheActionRunning
                ) {
                    queueCacheAction(.clearMemory)
                }

                AccessibleActionButton(
                    "Clear Temporary Disk Cache",
                    isEnabled: !isCacheActionRunning
                ) {
                    queueCacheAction(.clearTemporaryDisk)
                }
            }

            HStack(spacing: 8) {
                AccessibleActionButton(
                    "Clear All Article Cache",
                    isDestructive: true,
                    isEnabled: !isCacheActionRunning
                ) {
                    queueCacheAction(.clearAllArticleCache)
                }

                AccessibleActionButton(
                    "Reset All App Data",
                    isDestructive: true,
                    isEnabled: !isCacheActionRunning
                ) {
                    queueCacheAction(.resetAllAppData)
                }
            }

            SettingsHelpText("Temporary clear preserves saved, highlighted, and tagged article cache. Full article clear removes pinned cache too. App reset removes local app data and preferences.")
        }
    }

    private func cacheMetricsCard(_ metrics: WikipediaService.CacheMetrics) -> some View {
        let inMemoryEntries = metrics.fullArticleEntries + metrics.fastArticleEntries
        let inMemoryBytes = metrics.fullArticleBytes + metrics.fastArticleBytes

        return VStack(alignment: .leading, spacing: 8) {
            cacheMetricRow(
                title: "In-Memory",
                value: "\(formatByteCount(inMemoryBytes)) - \(entryCountLabel(inMemoryEntries))"
            )
            cacheMetricRow(
                title: "Disk",
                value: "\(formatByteCount(metrics.diskArticleBytes)) - \(entryCountLabel(metrics.diskArticleEntries))"
            )
            cacheMetricRow(
                title: "Pinned on Disk",
                value: articleCountLabel(metrics.pinnedArticleEntries)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func performanceMetricsCard(_ summaries: [PerformanceMetricsStore.Summary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                performanceMetricSummaryRow(summary)
                if index < summaries.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func performanceMetricSummaryRow(_ summary: PerformanceMetricsStore.Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SwiftUI.Label(summary.kind.title, systemImage: summary.kind.symbolName)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(PerformanceMetricsStore.formatDuration(summary.lastDurationMs)) last")
                    .font(.caption.monospacedDigit())
            }

            Text(
                "avg \(PerformanceMetricsStore.formatDuration(summary.averageDurationMs)) - best \(PerformanceMetricsStore.formatDuration(summary.bestDurationMs)) - worst \(PerformanceMetricsStore.formatDuration(summary.worstDurationMs)) - \(entryCountLabel(summary.sampleCount))"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(summary.lastDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cacheMetricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func queueCacheAction(_ action: SettingsStorageAction) {
        if action.requiresConfirmation {
            pendingCacheAction = action
        } else {
            performCacheAction(action)
        }
    }

    private func performCacheAction(_ action: SettingsStorageAction) {
        pendingCacheAction = nil
        guard !isCacheActionRunning else { return }

        isCacheActionRunning = true
        cacheStatusMessage = nil

        Task {
            let result = await SettingsStorageMaintenanceCoordinator.perform(
                action,
                clearInMemoryArticleCache: {
                    await WikipediaService.shared.clearInMemoryArticleCache()
                },
                clearDiskArticleCache: { includePinned in
                    await WikipediaService.shared.clearDiskArticleCache(includePinned: includePinned)
                },
                clearCache: {
                    await WikipediaService.shared.clearCache()
                },
                cacheMetrics: {
                    await WikipediaService.shared.cacheMetrics()
                },
                resetPersistedData: {
                    try await MainActor.run {
                        try deleteAllPersistedModels()
                        resetUserDefaultsDomain()
                        performanceMetrics.clear()
                        appState.resetForFactoryDefaults()
                    }
                }
            )

            await MainActor.run {
                cacheMetrics = result.metrics
                isCacheActionRunning = false
                cacheStatusMessage = result.statusMessage
            }
        }
    }

    private func deleteAllPersistedModels() throws {
        do {
            try deleteAllModels(of: ArticleNote.self)
            try deleteAllModels(of: Highlight.self)
            try deleteAllModels(of: ArticleState.self)
            try deleteAllModels(of: SavedArticle.self)
            try deleteAllModels(of: ReadingList.self)
            try deleteAllModels(of: Area.self)
            try deleteAllModels(of: Label.self)
            try deleteAllModels(of: Tag.self)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deleteAllModels<ModelType: PersistentModel>(of type: ModelType.Type) throws {
        let descriptor = FetchDescriptor<ModelType>()
        let models = try modelContext.fetch(descriptor)
        for model in models {
            modelContext.delete(model)
        }
    }

    private func resetUserDefaultsDomain() {
        _ = MacWikiDefaults.clearCurrentDomain()
    }

    private func refreshCacheMetrics() async {
        let metrics = await WikipediaService.shared.cacheMetrics()
        await MainActor.run {
            cacheMetrics = metrics
        }
    }

    private func formatByteCount(_ bytes: Int) -> String {
        AppPresentationFormatting.storageByteCount(bytes)
    }

    private func entryCountLabel(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    private func articleCountLabel(_ count: Int) -> String {
        count == 1 ? "1 article" : "\(count) articles"
    }
}
