import Foundation
import SwiftData

struct MacWikiQAHighlightFixtureRequest: Equatable {
    let articleTitle: String
    let text: String
}

@MainActor
enum MacWikiQAFixtureSeeder {
    static let highlightArticleTitleKey = "qa.fixture.highlight.articleTitle"
    static let highlightTextKey = "qa.fixture.highlight.text"

    static func requestedHighlightFixture(
        defaults: UserDefaults,
        environment: [String: String]
    ) -> MacWikiQAHighlightFixtureRequest? {
        guard MacWikiQAEnvironment.trustedSuiteName(in: environment) != nil,
              let rawTitle = defaults.string(forKey: highlightArticleTitleKey),
              let rawText = defaults.string(forKey: highlightTextKey) else {
            return nil
        }

        let articleTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !articleTitle.isEmpty, !text.isEmpty else { return nil }
        return MacWikiQAHighlightFixtureRequest(articleTitle: articleTitle, text: text)
    }

    static func seedRequestedFixtures(
        in modelContainer: ModelContainer,
        defaults: UserDefaults = MacWikiDefaults.current,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let request = requestedHighlightFixture(
            defaults: defaults,
            environment: environment
        ) else {
            return
        }

        let articleTitle = request.articleTitle
        let text = request.text
        let descriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate { highlight in
                highlight.articleTitle == articleTitle && highlight.text == text
            }
        )
        let context = modelContainer.mainContext
        guard (try? context.fetchCount(descriptor)) == 0 else { return }

        let highlight = Highlight(
            text: text,
            articleTitle: articleTitle,
            elementPath: "section[1]/p[1]",
            startOffset: 0,
            length: text.count,
            sectionTitle: "QA Fixture"
        )
        context.insert(highlight)
        context.saveReportingFailure(operation: #function)
    }
}
