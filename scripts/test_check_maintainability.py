#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from check_maintainability import build_report


BASELINE = {
    "thresholds": {
        "swiftui_view_lines": 3,
        "service_lines": 3,
    },
    "placeholder_patterns": ["remains same"],
    "approved_appstorage_key_definition_files": [
        "Sources/MacWiki/Utilities/AppStorageKey.swift",
    ],
    "duplicate_helper_functions": [
        "copyToClipboard",
        "wikipediaURLString",
    ],
    "hotspots": {
        "Sources/MacWiki/Views/Home/HugeView.swift": 2,
    },
}


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)


class MaintainabilityCheckerTests(unittest.TestCase):
    def test_checker_reports_expected_stage_one_findings(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline_path = root / "maintainability-baseline.json"
            baseline_path.write_text(json.dumps(BASELINE))

            write(
                root / "Sources/MacWiki/Views/Home/HugeView.swift",
                "\n".join(
                    [
                        "import SwiftUI",
                        '@AppStorage("rawKey") var value = false',
                        "func copyToClipboard(_ value: String) {}",
                        "func wikipediaURLString(for title: String) -> String { title }",
                    ]
                ),
            )
            write(
                root / "Sources/MacWiki/Views/Sidebar/AnotherView.swift",
                "\n".join(
                    [
                        "import SwiftUI",
                        "func copyToClipboard(_ value: String) {}",
                        "func wikipediaURLString(for title: String) -> String { title }",
                    ]
                ),
            )
            write(
                root / "Sources/MacWiki/Services/HugeService.swift",
                "\n".join(["actor HugeService {}", "let a = 1", "let b = 2", "let c = 3"]),
            )
            write(
                root / "README.md",
                "This remains same until someone fixes it.",
            )
            write(
                root / "Sources/MacWiki/Utilities/AppStorageKey.swift",
                '@AppStorage("allowed.raw.key") var allowed = false',
            )

            report = build_report(root, baseline_path)

            self.assertFalse(report.passed)
            self.assertEqual(len(report.errors), 1)
            self.assertTrue(any(f.kind == "oversized_swiftui_view" for f in report.warnings))
            self.assertTrue(any(f.kind == "oversized_service" for f in report.warnings))
            self.assertTrue(any(f.kind == "raw_appstorage_literal" for f in report.warnings))
            self.assertTrue(any(f.kind == "duplicate_helper_function" for f in report.warnings))
            self.assertTrue(any(f.kind == "hotspot_growth" for f in report.warnings))


if __name__ == "__main__":
    unittest.main()
