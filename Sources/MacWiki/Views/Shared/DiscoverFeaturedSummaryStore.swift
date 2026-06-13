import Foundation
import Observation

/// Loads a teaser excerpt for Discover's featured article.
@Observable @MainActor
final class DiscoverFeaturedSummaryStore {
    private(set) var teaserByTitleKey: [String: String] = [:]
    private(set) var isLoading = false

    private var loadTask: Task<Void, Never>?
    private let wikipediaService: WikipediaService

    init(wikipediaService: WikipediaService = .shared) {
        self.wikipediaService = wikipediaService
    }

    func queueLoad(featuredTitle: String?) {
        loadTask?.cancel()

        guard let featuredTitle, !featuredTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isLoading = false
            return
        }

        let key = titleMatchKey(featuredTitle)
        guard !key.isEmpty else {
            isLoading = false
            return
        }

        if teaserByTitleKey[key] != nil {
            isLoading = false
            return
        }

        isLoading = true
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(title: featuredTitle, key: key)
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func teaser(for title: String) -> String? {
        teaserByTitleKey[titleMatchKey(title)]
    }

    private func load(title: String, key: String) async {
        defer {
            if !Task.isCancelled {
                isLoading = false
            }
        }

        do {
            let summary = try await wikipediaService.fetchSummary(title)
            guard !Task.isCancelled else { return }

            let candidate = summary.extract ?? summary.description
            guard let candidate else { return }

            let normalized = normalize(candidate)
            guard !normalized.isEmpty else { return }
            teaserByTitleKey[key] = truncatedTeaser(normalized)
        } catch {
            // Keep empty teaser state; caller will render fallback.
        }
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func truncatedTeaser(_ text: String, maxCharacters: Int = 420) -> String {
        guard text.count > maxCharacters else { return text }
        let capped = String(text.prefix(maxCharacters))

        if let punctuationIndex = capped.lastIndex(where: { ".!?".contains($0) }),
           capped.distance(from: capped.startIndex, to: punctuationIndex) >= 120 {
            return String(capped[...punctuationIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return capped.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
