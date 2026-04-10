import Foundation
import Testing

@testable import MacWiki

@MainActor
struct DebouncedActionSchedulerTests {
    @Test func scheduleCoalescesRepeatedActions() async {
        let scheduler = DebouncedActionScheduler(delay: .milliseconds(25))
        var runCount = 0
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)

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
}
