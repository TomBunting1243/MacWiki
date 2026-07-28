import Foundation
import Testing

/// Narrow, explicitly labeled source lints for release and QA shell safety.
///
/// Unlike app source-shape assertions, these protect boundaries that cannot be imported into the
/// test process: package provenance, isolated state, exact process targeting, and safe report
/// generation. They intentionally avoid pinning incidental script layout.
struct ReleaseScriptContractTests {
    @Test func packagingRecordsCommitBinaryAndBundleProvenance() throws {
        let script = try scriptSource("scripts/package_beta_app.sh")

        for contract in [
            "BuildInfo.plist",
            "rev-parse HEAD",
            "SourceExecutableSHA256",
            "PackagedExecutableSHA256",
            "AppTreeSHA256",
            "PackageTimestampUTC"
        ] {
            #expect(script.contains(contract), "Missing package provenance contract: \(contract)")
        }
        #expect(script.contains("Packaging requires a clean, committed source tree"))
        #expect(script.contains("--skip-build requires --expected-executable-sha256"))
    }

    @Test func internalPackagingRequiresAnExplicitSigningDecision() throws {
        let script = try scriptSource("scripts/package_beta_app.sh")

        #expect(script.contains("--ad-hoc-sign"))
        #expect(script.contains("Signing now requires an explicit choice"))
        #expect(script.contains("codesign --verify --deep --strict"))
    }

    @Test func internalPreflightPinsTheOnePointZeroXcode27MacOS26Boundary() throws {
        let preflight = try scriptSource("scripts/internal_beta_preflight.sh")
        let infoURL = repositoryRoot().appending(path: "Sources/MacWiki/Info.plist")
        let info = try #require(NSDictionary(contentsOf: infoURL) as? [String: Any])

        #expect(info["CFBundleShortVersionString"] as? String == "1.0")
        #expect(preflight.contains("Internal-beta preflight requires Xcode 27"))
        #expect(preflight.contains("macwiki_release_build_args \"26.0\""))
        #expect(preflight.contains("MACWIKI_SKIP_NETWORK_TESTS=1 swift test"))
        #expect(preflight.contains("swift run SettingsIndexTool --validate-sources Sources/MacWiki"))
        #expect(preflight.contains("BinaryMinimumOS"))
        #expect(preflight.contains("ExecutableSHA256"))
    }

    @Test func publicReleaseAutomationAndChecklistsRemainExplicitlyRetired() throws {
        let releaseScript = try scriptSource("scripts/release_beta.sh")
        let publicPreflight = try scriptSource("scripts/preflight_beta_release.sh")
        let readme = try textSource("README.md")
        let checklist = try textSource("RELEASE_BETA_CHECKLIST.md")
        let matrix = try textSource("PUBLIC_BETA_QA_MATRIX.md")

        #expect(releaseScript.hasPrefix(
            "#!/usr/bin/env bash\nset -euo pipefail\n\necho \"RETIRED:"
        ))
        #expect(publicPreflight.hasPrefix(
            "#!/usr/bin/env bash\nset -euo pipefail\n\necho \"RETIRED:"
        ))
        #expect(releaseScript.contains("exit 2"))
        #expect(publicPreflight.contains("exit 2"))

        for document in [readme, checklist, matrix] {
            #expect(document.contains("INTERNAL_BETA_QUALITY_PROGRAM.md"))
            #expect(document.contains("scripts/internal_beta_preflight.sh"))
        }
        #expect(checklist.contains("RETIRED — historical reference only"))
        #expect(matrix.contains("RETIRED — historical reference only"))
    }

    @Test func launchHarnessesShareTheIsolatedExactProcessBoundary() throws {
        let safetyLibrary = try scriptSource("scripts/lib/qa_process_safety.sh")
        let scripts = try shellScriptURLs().filter { url in
            guard !url.path.contains("/scripts/lib/") else { return false }
            return try String(contentsOf: url, encoding: .utf8).contains("qa_launch_candidate")
        }

        #expect(!scripts.isEmpty)
        for contract in [
            "\"HOME=$QA_HOME\"",
            "\"CFFIXED_USER_HOME=$QA_HOME\"",
            "qa_assert_no_conflicting_processes",
            "qa_pid_executable_path",
            "qa_exact_binary_pids",
            "qa_assert_candidate_manifest_matches_executable"
        ] {
            #expect(safetyLibrary.contains(contract), "Missing QA safety contract: \(contract)")
        }

        for scriptURL in scripts {
            let script = try String(contentsOf: scriptURL, encoding: .utf8)
            #expect(script.contains("qa_process_safety.sh"), "\(scriptURL.lastPathComponent) bypasses QA safety")
            #expect(script.contains("qa_prepare_isolated_home"), "\(scriptURL.lastPathComponent) does not isolate state")
            #expect(!script.contains("pkill -x"), "\(scriptURL.lastPathComponent) uses name-based termination")
        }
    }

    @Test func shellScriptsAvoidKnownMachineSpecificRepoAndDerivedDataPaths() throws {
        for scriptURL in try shellScriptURLs() {
            let script = try String(contentsOf: scriptURL, encoding: .utf8)
            #expect(
                !script.contains("/Users/tombunting/Developer/MacWiki"),
                "\(scriptURL.lastPathComponent) hardcodes the original repository path"
            )
            #expect(
                !script.contains("DerivedData/MacWiki-hgaamxiclllsfufsrrsbkmjdjcle"),
                "\(scriptURL.lastPathComponent) hardcodes a machine-specific DerivedData fingerprint"
            )
        }
    }

    @Test func unquotedHeredocsCannotExecuteMarkdownBackticks() throws {
        let opener = try NSRegularExpression(pattern: #"<<-?\s*([A-Za-z_][A-Za-z0-9_]*)"#)

        for scriptURL in try shellScriptURLs() {
            let lines = try String(contentsOf: scriptURL, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            var unquotedDelimiter: String?

            for (offset, line) in lines.enumerated() {
                if let delimiter = unquotedDelimiter {
                    if line.trimmingCharacters(in: .whitespaces) == delimiter {
                        unquotedDelimiter = nil
                    } else if containsUnescapedBacktick(line) {
                        Issue.record(
                            "Unescaped backtick in unquoted heredoc at \(scriptURL.lastPathComponent):\(offset + 1)"
                        )
                    }
                    continue
                }

                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = opener.firstMatch(in: line, range: range),
                      let delimiterRange = Range(match.range(at: 1), in: line) else {
                    continue
                }
                unquotedDelimiter = String(line[delimiterRange])
            }
        }
    }

    private func containsUnescapedBacktick(_ line: String) -> Bool {
        for index in line.indices where line[index] == "`" {
            var slashCount = 0
            var cursor = index
            while cursor > line.startIndex {
                cursor = line.index(before: cursor)
                guard line[cursor] == "\\" else { break }
                slashCount += 1
            }
            if slashCount.isMultiple(of: 2) { return true }
        }
        return false
    }

    private func scriptSource(_ relativePath: String) throws -> String {
        try textSource(relativePath)
    }

    private func textSource(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appending(path: relativePath), encoding: .utf8)
    }

    private func shellScriptURLs() throws -> [URL] {
        let scriptsDirectory = repositoryRoot().appending(path: "scripts")
        guard let enumerator = FileManager.default.enumerator(
            at: scriptsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "sh" }
            .sorted { $0.path < $1.path }
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
