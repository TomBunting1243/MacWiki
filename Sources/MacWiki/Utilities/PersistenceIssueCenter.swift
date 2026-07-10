import Observation
import os
import SwiftData
import SwiftUI

private let persistenceIssueLogger = Logger(subsystem: "com.macwiki", category: "persistence")

struct PersistenceIssue: Identifiable, Equatable {
    let id = UUID()
    let operation: String
    let detail: String
}

@Observable @MainActor
final class PersistenceIssueCenter {
    static let shared = PersistenceIssueCenter()

    var activeIssue: PersistenceIssue?

    func report(operation: String, error: Error) {
        let detail = error.localizedDescription
        persistenceIssueLogger.error(
            "SwiftData save failed during \(operation, privacy: .public): \(detail, privacy: .public)"
        )
        activeIssue = PersistenceIssue(operation: operation, detail: detail)
    }

    func dismiss() {
        activeIssue = nil
    }
}

extension ModelContext {
    /// Saves pending SwiftData mutations or rolls them back and reports the failure.
    @MainActor @discardableResult
    func saveReportingFailure(operation: String) -> Bool {
        do {
            try save()
            return true
        } catch {
            rollback()
            PersistenceIssueCenter.shared.report(operation: operation, error: error)
            return false
        }
    }
}

private struct PersistenceIssueAlertModifier: ViewModifier {
    @State private var issueCenter = PersistenceIssueCenter.shared

    func body(content: Content) -> some View {
        @Bindable var issueCenter = issueCenter

        content.alert(item: $issueCenter.activeIssue) { issue in
            Alert(
                title: Text("Couldn’t Save Changes"),
                message: Text(
                    "MacWiki couldn’t complete \(issue.operation). "
                    + "The unsaved changes were rolled back.\n\n\(issue.detail)"
                ),
                dismissButton: .default(Text("OK")) {
                    issueCenter.dismiss()
                }
            )
        }
    }
}

extension View {
    func persistenceIssueAlert() -> some View {
        modifier(PersistenceIssueAlertModifier())
    }
}
