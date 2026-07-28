import Foundation
import Testing

@testable import MacWiki

@MainActor
struct DebouncedActionSchedulerTests {
    @Test func scheduleCoalescesRepeatedActions() async {
        let scheduler = DebouncedActionScheduler(delay: .milliseconds(25))
        var runCount = 0
        let clock = ContinuousClock()
        // The complete suite runs many MainActor integration tests concurrently.
        // Keep this deadline tolerant of executor contention while polling at the
        // same short cadence, so an unloaded run remains just as fast.
        let deadline = clock.now + .seconds(10)

        scheduler.schedule {
            runCount += 1
        }
        scheduler.schedule {
            runCount += 1
        }

        while clock.now < deadline && runCount == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(runCount == 1)

        try? await Task.sleep(for: .milliseconds(75))

        #expect(runCount == 1)
    }

    @Test func flushRunsImmediatelyAndCancelsPendingAction() async {
        let scheduler = DebouncedActionScheduler(delay: .milliseconds(25))
        var runCount = 0

        scheduler.schedule {
            runCount += 1
        }

        scheduler.flush {
            runCount += 1
        }

        #expect(runCount == 1)

        try? await Task.sleep(for: .milliseconds(50))

        #expect(runCount == 1)
    }

    @Test func zeroDelaySchedulingDefersPastTheCurrentTurn() async {
        let scheduler = DebouncedActionScheduler(delay: .zero)
        var runCount = 0

        scheduler.schedule {
            runCount += 1
        }

        #expect(runCount == 0)

        await waitUntil { runCount > 0 }

        #expect(runCount == 1)
    }

    @Test func zeroDelaySchedulingCoalescesAndHonorsCancellation() async {
        let scheduler = DebouncedActionScheduler(delay: .zero)
        var runCount = 0

        scheduler.schedule { runCount += 1 }
        scheduler.schedule { runCount += 1 }
        scheduler.schedule { runCount += 1 }

        await waitUntil { runCount > 0 }
        #expect(runCount == 1)

        scheduler.schedule { runCount += 1 }
        scheduler.cancel()

        try? await Task.sleep(for: .milliseconds(50))
        #expect(runCount == 1)
    }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline && !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
