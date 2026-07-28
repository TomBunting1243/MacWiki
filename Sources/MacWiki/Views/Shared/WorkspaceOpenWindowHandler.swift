import SwiftUI

@MainActor
protocol WorkspaceOpenWindowActionAdapter {
    func openWindow(with article: Article)
}

@MainActor
private struct SwiftUIWorkspaceOpenWindowActionAdapter: WorkspaceOpenWindowActionAdapter {
    let action: OpenWindowAction

    func openWindow(with article: Article) {
        action(value: article)
    }
}

/// Carries SwiftUI's scene-scoped `OpenWindowAction` across the AppKit hosting
/// boundary without placing a closure value in the environment. The handler's
/// reference stays stable while its framework action adapter is refreshed by
/// the owning scene.
@MainActor
final class WorkspaceOpenWindowHandler {
    private var actionAdapter: (any WorkspaceOpenWindowActionAdapter)?

    init(actionAdapter: (any WorkspaceOpenWindowActionAdapter)? = nil) {
        self.actionAdapter = actionAdapter
    }

    func update(action: OpenWindowAction) {
        update(actionAdapter: SwiftUIWorkspaceOpenWindowActionAdapter(action: action))
    }

    func update(actionAdapter: any WorkspaceOpenWindowActionAdapter) {
        self.actionAdapter = actionAdapter
    }

    @discardableResult
    func open(_ article: Article) -> Bool {
        guard let actionAdapter else { return false }
        actionAdapter.openWindow(with: article)
        return true
    }
}

extension EnvironmentValues {
    @Entry var workspaceOpenWindowHandler: WorkspaceOpenWindowHandler?
}
