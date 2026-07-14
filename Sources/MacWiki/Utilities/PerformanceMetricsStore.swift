import Foundation
import Observation
import os

@Observable @MainActor
final class PerformanceMetricsStore {
    enum MetricKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
        case sessionRestore
        case search
        case sidebarHydration
        case readerOpen

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sessionRestore:
                return "Session Restore"
            case .search:
                return "Search"
            case .sidebarHydration:
                return "Sidebar Hydration"
            case .readerOpen:
                return "Reader Reveal"
            }
        }

        var symbolName: String {
            switch self {
            case .sessionRestore:
                return "bolt.horizontal.circle"
            case .search:
                return "magnifyingglass"
            case .sidebarHydration:
                return "list.bullet.rectangle"
            case .readerOpen:
                return "book.pages"
            }
        }
    }

    struct Sample: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        let kind: MetricKind
        let durationMs: Double
        let detail: String
        let timestamp: Date
    }

    struct Summary: Identifiable, Equatable, Sendable {
        let kind: MetricKind
        let sampleCount: Int
        let lastDurationMs: Double
        let averageDurationMs: Double
        let bestDurationMs: Double
        let worstDurationMs: Double
        let lastDetail: String
        let updatedAt: Date

        var id: MetricKind { kind }
    }

    static let shared = PerformanceMetricsStore(userDefaults: MacWikiDefaults.current)

    private static let logger = Logger(subsystem: "com.macwiki", category: "performance-metrics")
    private static let defaultStorageKeyPrefix = "com.macwiki.performance-metrics.samples.v2"

    private(set) var samplesByKind: [MetricKind: [Sample]]

    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let storageKeyPrefix: String
    @ObservationIgnored private let maxSamplesPerKind: Int
    @ObservationIgnored private var loadedKinds: Set<MetricKind> = []

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = defaultStorageKeyPrefix,
        maxSamplesPerKind: Int = 30
    ) {
        self.userDefaults = userDefaults
        self.storageKeyPrefix = storageKey
        self.maxSamplesPerKind = max(1, maxSamplesPerKind)
        self.samplesByKind = Dictionary(
            uniqueKeysWithValues: MetricKind.allCases.map { kind in
                (
                    kind,
                    Self.loadSamples(
                        for: kind,
                        from: userDefaults,
                        storageKey: "\(storageKey).\(kind.rawValue)"
                    )
                )
            }
        )
        self.loadedKinds = Set(MetricKind.allCases)
    }

    var summaries: [Summary] {
        ensureLoadedAllKinds()
        return MetricKind.allCases.compactMap(summary(for:))
    }

    var hasSamples: Bool {
        ensureLoadedAllKinds()
        return samplesByKind.values.contains { !$0.isEmpty }
    }

    func summary(for kind: MetricKind) -> Summary? {
        ensureLoaded(kind)
        guard let samples = samplesByKind[kind], !samples.isEmpty else { return nil }
        let durations = samples.map(\.durationMs)
        guard let last = samples.last,
              let best = durations.min(),
              let worst = durations.max() else {
            return nil
        }

        let total = durations.reduce(0, +)
        return Summary(
            kind: kind,
            sampleCount: samples.count,
            lastDurationMs: last.durationMs,
            averageDurationMs: total / Double(samples.count),
            bestDurationMs: best,
            worstDurationMs: worst,
            lastDetail: last.detail,
            updatedAt: last.timestamp
        )
    }

    func record(kind: MetricKind, durationMs: Double, detail: String) {
        ensureLoaded(kind)
        let sanitizedDurationMs = max(durationMs, 0)
        let sample = Sample(
            kind: kind,
            durationMs: sanitizedDurationMs,
            detail: detail,
            timestamp: Date()
        )

        var samples = samplesByKind[kind] ?? []
        samples.append(sample)
        if samples.count > maxSamplesPerKind {
            samples.removeFirst(samples.count - maxSamplesPerKind)
        }
        samplesByKind[kind] = samples
        persist(samples, for: kind)

        Self.logger.info(
            "metric \(kind.title, privacy: .public) \(Self.formatDuration(sanitizedDurationMs), privacy: .public) \(detail, privacy: .public)"
        )
    }

    func clear() {
        samplesByKind.removeAll()
        loadedKinds = Set(MetricKind.allCases)
        for kind in MetricKind.allCases {
            userDefaults.removeObject(forKey: storageKey(for: kind))
        }
    }

    static func formatDuration(_ durationMs: Double) -> String {
        if durationMs >= 1_000 {
            return String(format: "%.2fs", durationMs / 1_000)
        }
        return String(format: "%.0fms", durationMs)
    }

    private func persist(_ samples: [Sample], for kind: MetricKind) {
        do {
            let data = try JSONEncoder().encode(samples)
            userDefaults.set(data, forKey: storageKey(for: kind))
        } catch {
            Self.logger.error("Failed to persist performance metrics: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func ensureLoadedAllKinds() {
        for kind in MetricKind.allCases {
            ensureLoaded(kind)
        }
    }

    private func ensureLoaded(_ kind: MetricKind) {
        guard !loadedKinds.contains(kind) else { return }
        samplesByKind[kind] = Self.loadSamples(
            for: kind,
            from: userDefaults,
            storageKey: storageKey(for: kind)
        )
        loadedKinds.insert(kind)
    }

    private func storageKey(for kind: MetricKind) -> String {
        "\(storageKeyPrefix).\(kind.rawValue)"
    }

    private static func loadSamples(
        for kind: MetricKind,
        from userDefaults: UserDefaults,
        storageKey: String
    ) -> [Sample] {
        guard let data = userDefaults.data(forKey: storageKey) else { return [] }

        do {
            let decoded = try JSONDecoder().decode([Sample].self, from: data)
            return decoded
                .filter { $0.kind == kind }
                .sorted { $0.timestamp < $1.timestamp }
        } catch {
            logger.error("Failed to load persisted performance metrics: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
