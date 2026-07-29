import Foundation

enum WebViewInspectorProjectionSchedulePolicy {
    enum Target: Equatable, Sendable {
        case tableOfContents
        case references
    }

    enum Requirement: Equatable, Sendable {
        case always
        case missingResult
    }

    struct Request: Equatable, Sendable {
        let target: Target
        let requirement: Requirement
    }

    struct Step: Equatable, Sendable {
        let delay: TimeInterval
        let requests: [Request]
    }

    struct ProjectionState: Equatable, Sendable {
        let hasTableOfContentsResult: Bool
        let hasReferencesResult: Bool
    }

    enum ResultDecision: Equatable, Sendable {
        case retry
        case publishTableOfContentsAndVisibleSection
        case publishReferences
    }

    static let steps: [Step] = [
        Step(
            delay: 0.06,
            requests: [Request(target: .tableOfContents, requirement: .always)]
        ),
        Step(
            delay: 0.24,
            requests: [Request(target: .references, requirement: .always)]
        ),
        Step(
            delay: 0.36,
            requests: [Request(target: .tableOfContents, requirement: .missingResult)]
        ),
        Step(
            delay: 0.55,
            requests: [Request(target: .references, requirement: .missingResult)]
        ),
        Step(
            delay: 0.90,
            requests: [
                Request(target: .tableOfContents, requirement: .missingResult),
                Request(target: .references, requirement: .missingResult)
            ]
        )
    ]

    static func requests(
        for step: Step,
        projection: ProjectionState,
        isCurrentProjection: Bool
    ) -> [Target] {
        guard isCurrentProjection else { return [] }

        return step.requests.compactMap { request in
            switch request.requirement {
            case .always:
                return request.target
            case .missingResult:
                return hasResult(for: request.target, in: projection) ? nil : request.target
            }
        }
    }

    static func resultDecision(
        for target: Target,
        hasValidRows: Bool
    ) -> ResultDecision {
        guard hasValidRows else { return .retry }

        switch target {
        case .tableOfContents:
            return .publishTableOfContentsAndVisibleSection
        case .references:
            return .publishReferences
        }
    }

    private static func hasResult(
        for target: Target,
        in projection: ProjectionState
    ) -> Bool {
        switch target {
        case .tableOfContents:
            return projection.hasTableOfContentsResult
        case .references:
            return projection.hasReferencesResult
        }
    }
}
