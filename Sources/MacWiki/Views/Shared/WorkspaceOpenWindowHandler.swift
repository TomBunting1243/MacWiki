import SwiftUI

/// Carries SwiftUI's scene-scoped `OpenWindowAction` across the AppKit hosting
/// boundary without placing a closure value in the environment. The reference
/// stays stable while its framework action is refreshed by the owning scene.
@MainActor
final class WorkspaceOpenWindowHandler {
    private var action: OpenWindowAction?

    func update(action: OpenWindowAction) {
        self.action = action
    }

    @discardableResult
    func open(_ article: Article) -> Bool {
        guard let action else { return false }
        action(value: article)
        return true
    }
}

extension EnvironmentValues {
    @Entry var workspaceOpenWindowHandler: WorkspaceOpenWindowHandler?
}
