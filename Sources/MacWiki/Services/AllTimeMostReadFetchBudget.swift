import Foundation

struct AllTimeMostReadFetchBudget: Equatable, Sendable {
    static let standard = AllTimeMostReadFetchBudget(
        monthlyRequestBatchSize: 6,
        perMonthArticleLimit: 180,
        summaryRequestBatchSize: 6,
        summaryTargetMultiplier: 3,
        minimumSummaryTargetCount: 80
    )

    let monthlyRequestBatchSize: Int
    let perMonthArticleLimit: Int
    let summaryRequestBatchSize: Int
    let summaryTargetMultiplier: Int
    let minimumSummaryTargetCount: Int

    init(
        monthlyRequestBatchSize: Int,
        perMonthArticleLimit: Int,
        summaryRequestBatchSize: Int,
        summaryTargetMultiplier: Int,
        minimumSummaryTargetCount: Int
    ) {
        self.monthlyRequestBatchSize = max(1, monthlyRequestBatchSize)
        self.perMonthArticleLimit = max(1, perMonthArticleLimit)
        self.summaryRequestBatchSize = max(1, summaryRequestBatchSize)
        self.summaryTargetMultiplier = max(1, summaryTargetMultiplier)
        self.minimumSummaryTargetCount = max(1, minimumSummaryTargetCount)
    }

    func summaryTargetCount(requestedLimit: Int, availableCandidateCount: Int) -> Int {
        min(
            max(requestedLimit * summaryTargetMultiplier, minimumSummaryTargetCount),
            max(0, availableCandidateCount)
        )
    }
}
