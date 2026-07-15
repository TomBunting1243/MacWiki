import Foundation
import Testing

@Suite(.serialized)
@MainActor
struct QAProcessSafetyShellTests {
    @Test func rejectsSymlinkedQAHomeBeforeWritingThroughIt() throws {
        let identifier = UUID().uuidString
        let allowedParent = URL(filePath: "/tmp/macwiki-qa/symlink-test-\(identifier)")
        let qaHome = allowedParent.appending(path: "home")
        let outside = URL(filePath: "/private/tmp/macwiki-qa-outside-\(identifier)")
        defer {
            try? FileManager.default.removeItem(at: allowedParent)
            try? FileManager.default.removeItem(at: outside)
        }

        try FileManager.default.createDirectory(
            at: allowedParent,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: qaHome,
            withDestinationURL: outside
        )

        let result = try runBash(
            """
            set -euo pipefail
            REPO_ROOT="$1"
            source "$REPO_ROOT/scripts/lib/qa_process_safety.sh"
            qa_assert_isolated_path "$2" "$2"
            """,
            arguments: [repositoryRoot.path(), qaHome.path()]
        )

        #expect(result.status != 0)
        #expect(result.stderr.contains("Refusing symlinked QA path"))
        let outsideContents = try FileManager.default.contentsOfDirectory(
            atPath: outside.path()
        )
        #expect(outsideContents.isEmpty)
    }

    @Test func timeoutEscalatesPastATermIgnoringCommand() throws {
        let clock = ContinuousClock()
        let started = clock.now
        let result = try runBash(
            """
            set -euo pipefail
            REPO_ROOT="$1"
            source "$REPO_ROOT/scripts/lib/qa_process_safety.sh"
            set +e
            qa_run_command_with_timeout 1 /bin/bash -c 'trap "" TERM; sleep 30'
            status=$?
            set -e
            exit "$status"
            """,
            arguments: [repositoryRoot.path()]
        )
        let elapsed = started.duration(to: clock.now)

        #expect(result.status == 124)
        #expect(elapsed < .seconds(6))
    }

    @Test func readerAXDriverTargetsEscapeAtTheCandidateProcess() throws {
        let source = try String(
            contentsOf: repositoryRoot
                .appending(path: "scripts/ax_reader_inspector_journey.swift"),
            encoding: .utf8
        )

        #expect(source.contains("private func postEscape(to pid: pid_t) throws"))
        #expect(source.contains("keyDown.postToPid(pid)"))
        #expect(source.contains("keyUp.postToPid(pid)"))
        #expect(!source.contains("virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)"))
    }

    private func runBash(
        _ script: String,
        arguments: [String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(filePath: "/bin/bash")
        process.arguments = ["-c", script, "qa-process-safety-test"] + arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
