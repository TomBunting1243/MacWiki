import Foundation

@MainActor
final class DebouncedActionScheduler {
    private let delay: Duration
    private var task: Task<Void, Never>?

    init(delay: Duration = .milliseconds(120)) {
        self.delay = delay
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        let delay = self.delay
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.task = nil
            action()
        }
    }

    func flush(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = nil
        action()
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
