import Foundation
import os

/// Lightweight timer for article open-path phase instrumentation.
///
/// Tracks timestamps at key phases of the article open flow and logs
/// a compact summary when the reveal completes. Designed to have near-zero
/// overhead on the critical path (only `CFAbsoluteTimeGetCurrent` calls).
@MainActor
struct ArticleOpenTimer {
    private static let logger = Logger(subsystem: "com.macwiki", category: "article-open")

    enum OpenKind: String {
        case cold       // network fetch
        case warmMemory // in-session HTML cache hit
        case warmDisk   // disk/memory service cache hit
    }

    private(set) var kind: OpenKind = .cold
    private var taskStart: CFAbsoluteTime = 0
    private var fetchComplete: CFAbsoluteTime = 0
    private var htmlBound: CFAbsoluteTime = 0
    private var didFinish: CFAbsoluteTime = 0
    private var revealComplete: CFAbsoluteTime = 0
    private var highlightsApplied: CFAbsoluteTime = 0
    private(set) var isActive = false
    private var articleTitle = ""

    mutating func begin(title: String, preloaded: Bool) {
        taskStart = CFAbsoluteTimeGetCurrent()
        fetchComplete = 0
        htmlBound = 0
        didFinish = 0
        revealComplete = 0
        highlightsApplied = 0
        kind = preloaded ? .warmMemory : .cold
        isActive = true
        articleTitle = title
    }

    mutating func markFetchComplete(source: WikipediaService.FastArticleSource) {
        fetchComplete = CFAbsoluteTimeGetCurrent()
        switch source {
        case .memoryFull, .memoryFast:
            if kind != .warmMemory { kind = .warmMemory }
        case .disk:
            if kind == .cold { kind = .warmDisk }
        case .network:
            kind = .cold
        }
    }

    mutating func markHTMLBound() {
        htmlBound = CFAbsoluteTimeGetCurrent()
    }

    mutating func markWebViewDidFinish() {
        didFinish = CFAbsoluteTimeGetCurrent()
    }

    mutating func markHighlightsApplied() {
        highlightsApplied = CFAbsoluteTimeGetCurrent()
    }

    mutating func markRevealComplete() {
        guard isActive else { return }
        revealComplete = CFAbsoluteTimeGetCurrent()
        log()
        isActive = false
    }

    private func log() {
        guard taskStart > 0, revealComplete > 0 else { return }
        let totalMs = milliseconds(from: taskStart, to: revealComplete)
        let fetchMs = fetchComplete > 0 ? milliseconds(from: taskStart, to: fetchComplete) : nil
        let bindMs = htmlBound > 0 ? milliseconds(from: taskStart, to: htmlBound) : nil
        let finishMs = didFinish > 0 ? milliseconds(from: taskStart, to: didFinish) : nil
        let highlightMs = highlightsApplied > 0 ? milliseconds(from: taskStart, to: highlightsApplied) : nil

        var phases: [String] = []
        if let f = fetchMs { phases.append("fetch=\(msLabel(f))") }
        if let b = bindMs { phases.append("bind=\(msLabel(b))") }
        if let f = finishMs { phases.append("didFinish=\(msLabel(f))") }
        if let h = highlightMs { phases.append("highlights=\(msLabel(h))") }
        phases.append("reveal=\(msLabel(totalMs))")

        let summary = "[\(kind.rawValue)] \(articleTitle.prefix(40)): \(phases.joined(separator: " "))"
        Self.logger.info("article-open \(summary, privacy: .public)")
        PerformanceMetricsStore.shared.record(
            kind: .readerOpen,
            durationMs: totalMs,
            detail: "kind=\(kind.rawValue) \(phases.joined(separator: " "))"
        )
    }

    private func milliseconds(from start: CFAbsoluteTime, to end: CFAbsoluteTime) -> Double {
        (end - start) * 1_000
    }

    private func msLabel(_ millis: Double) -> String {
        String(format: "%.0fms", millis)
    }
}
