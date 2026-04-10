#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable


TEXT_FILE_SUFFIXES = {
    ".json",
    ".md",
    ".plist",
    ".sh",
    ".swift",
    ".toml",
    ".txt",
    ".xml",
    ".yaml",
    ".yml",
}
PLACEHOLDER_SCAN_ROOTS = [
    ".github",
    "Sources",
    "Tests",
    "scripts",
]
PLACEHOLDER_SCAN_FILES = [
    "Package.swift",
    "README.md",
]

APPSTORAGE_LITERAL_RE = re.compile(r'@AppStorage\(\s*"([^"]+)"')
FUNCTION_RE_TEMPLATE = r"\bfunc\s+{name}\s*\("


@dataclass
class Finding:
    kind: str
    path: str
    line: int | None
    message: str


@dataclass
class Report:
    errors: list[Finding]
    warnings: list[Finding]
    metadata: dict

    @property
    def passed(self) -> bool:
        return not self.errors


def load_baseline(path: Path) -> dict:
    return json.loads(path.read_text())


def iter_text_files(root: Path) -> Iterable[Path]:
    for entry in root.rglob("*"):
        if not entry.is_file():
            continue
        if any(part.startswith(".") and part not in {".github"} for part in entry.parts):
            continue
        if entry.suffix.lower() in TEXT_FILE_SUFFIXES or entry.name == "Package.swift":
            yield entry


def iter_swift_files(root: Path, relative_prefix: str) -> Iterable[Path]:
    base = root / relative_prefix
    if not base.exists():
        return []
    return sorted(base.rglob("*.swift"))


def relative_to_root(root: Path, path: Path) -> str:
    return path.relative_to(root).as_posix()


def count_lines(path: Path) -> int:
    return len(path.read_text().splitlines())


def find_placeholder_residue(root: Path, patterns: list[str], ignored_paths: set[str]) -> list[Finding]:
    findings: list[Finding] = []
    lowered_patterns = [pattern.lower() for pattern in patterns]
    candidates: list[Path] = []
    for relative_root in PLACEHOLDER_SCAN_ROOTS:
        candidate_root = root / relative_root
        if candidate_root.exists():
            candidates.extend(iter_text_files(candidate_root))
    for relative_file in PLACEHOLDER_SCAN_FILES:
        candidate_file = root / relative_file
        if candidate_file.exists():
            candidates.append(candidate_file)

    for file_path in candidates:
        relative_path = relative_to_root(root, file_path)
        if relative_path in ignored_paths:
            continue
        for line_number, line in enumerate(file_path.read_text().splitlines(), start=1):
            lowered_line = line.lower()
            for pattern in lowered_patterns:
                if pattern in lowered_line:
                    findings.append(
                        Finding(
                            kind="placeholder_residue",
                            path=relative_path,
                            line=line_number,
                            message=f'Placeholder residue "{pattern}" found.',
                        )
                    )
    return findings


def warn_on_large_files(root: Path, baseline: dict) -> list[Finding]:
    findings: list[Finding] = []
    thresholds = baseline["thresholds"]

    for file_path in iter_swift_files(root, "Sources/MacWiki/Views"):
        line_count = count_lines(file_path)
        if line_count > thresholds["swiftui_view_lines"]:
            findings.append(
                Finding(
                    kind="oversized_swiftui_view",
                    path=relative_to_root(root, file_path),
                    line=None,
                    message=(
                        f"SwiftUI view exceeds {thresholds['swiftui_view_lines']} lines "
                        f"({line_count} lines)."
                    ),
                )
            )

    for file_path in iter_swift_files(root, "Sources/MacWiki/Services"):
        line_count = count_lines(file_path)
        if line_count > thresholds["service_lines"]:
            findings.append(
                Finding(
                    kind="oversized_service",
                    path=relative_to_root(root, file_path),
                    line=None,
                    message=(
                        f"Service exceeds {thresholds['service_lines']} lines "
                        f"({line_count} lines)."
                    ),
                )
            )

    return findings


def find_raw_appstorage_literals(root: Path, approved_files: set[str]) -> list[Finding]:
    findings: list[Finding] = []
    for file_path in iter_swift_files(root, "Sources/MacWiki"):
        relative_path = relative_to_root(root, file_path)
        if relative_path in approved_files:
            continue
        for line_number, line in enumerate(file_path.read_text().splitlines(), start=1):
            match = APPSTORAGE_LITERAL_RE.search(line)
            if not match:
                continue
            findings.append(
                Finding(
                    kind="raw_appstorage_literal",
                    path=relative_path,
                    line=line_number,
                    message=f'Raw @AppStorage literal "{match.group(1)}" should use a typed key owner.',
                )
            )
    return findings


def find_duplicate_helpers(root: Path, helper_names: list[str], scoped_files: set[str]) -> list[Finding]:
    indexed: dict[str, list[Finding]] = {name: [] for name in helper_names}
    candidate_paths: list[Path]
    if scoped_files:
        candidate_paths = [root / relative_path for relative_path in sorted(scoped_files)]
    else:
        candidate_paths = list(iter_swift_files(root, "Sources/MacWiki"))

    for file_path in candidate_paths:
        if not file_path.exists():
            continue
        relative_path = relative_to_root(root, file_path)
        lines = file_path.read_text().splitlines()
        for helper_name in helper_names:
            helper_re = re.compile(FUNCTION_RE_TEMPLATE.format(name=re.escape(helper_name)))
            for line_number, line in enumerate(lines, start=1):
                if helper_re.search(line):
                    indexed[helper_name].append(
                        Finding(
                            kind="duplicate_helper_function",
                            path=relative_path,
                            line=line_number,
                            message=f'Local helper "{helper_name}" defined here.',
                        )
                    )

    findings: list[Finding] = []
    for helper_name, helper_findings in indexed.items():
        if len(helper_findings) <= 1:
            continue
        summary = f'Local helper "{helper_name}" is duplicated across {len(helper_findings)} definitions.'
        for finding in helper_findings:
            findings.append(
                Finding(
                    kind=finding.kind,
                    path=finding.path,
                    line=finding.line,
                    message=summary,
                )
            )
    return findings


def find_hotspot_growth(root: Path, hotspot_baseline: dict[str, int]) -> tuple[list[Finding], dict[str, int]]:
    findings: list[Finding] = []
    current_counts: dict[str, int] = {}

    for relative_path, baseline_count in hotspot_baseline.items():
        absolute_path = root / relative_path
        if not absolute_path.exists():
            continue
        current_count = count_lines(absolute_path)
        current_counts[relative_path] = current_count
        if current_count > baseline_count:
            findings.append(
                Finding(
                    kind="hotspot_growth",
                    path=relative_path,
                    line=None,
                    message=f"Hotspot grew from baseline {baseline_count} to {current_count} lines.",
                )
            )

    return findings, current_counts


def build_report(root: Path, baseline_path: Path) -> Report:
    baseline = load_baseline(baseline_path)

    errors = find_placeholder_residue(
        root,
        baseline["placeholder_patterns"],
        {relative_to_root(root, baseline_path)},
    )
    warnings: list[Finding] = []
    warnings.extend(warn_on_large_files(root, baseline))
    warnings.extend(
        find_raw_appstorage_literals(
            root,
            set(baseline["approved_appstorage_key_definition_files"]),
        )
    )
    warnings.extend(
        find_duplicate_helpers(
            root,
            baseline["duplicate_helper_functions"],
            set(baseline.get("duplicate_helper_scope_files", [])),
        )
    )
    hotspot_findings, hotspot_counts = find_hotspot_growth(root, baseline["hotspots"])
    warnings.extend(hotspot_findings)

    metadata = {
        "baseline_path": baseline_path.name,
        "hotspot_counts": hotspot_counts,
        "warning_count": len(warnings),
        "error_count": len(errors),
    }
    return Report(errors=errors, warnings=warnings, metadata=metadata)


def render_human(report: Report) -> str:
    lines = ["== Project Dolus Maintainability Report ==", ""]
    if report.errors:
        lines.append(f"Errors: {len(report.errors)}")
        for finding in report.errors:
            lines.append(format_human_finding(finding))
    else:
        lines.append("Errors: 0")

    lines.append("")
    lines.append(f"Warnings: {len(report.warnings)}")
    for finding in report.warnings:
        lines.append(format_human_finding(finding))

    lines.append("")
    lines.append("Hotspot baseline comparison:")
    hotspot_counts = report.metadata["hotspot_counts"]
    for path in sorted(hotspot_counts):
        lines.append(f"  - {path}: {hotspot_counts[path]} lines")

    lines.append("")
    lines.append("Result: FAIL" if not report.passed else "Result: PASS")
    if report.warnings and report.passed:
        lines.append("Note: warnings are advisory today; the ratchet is visible before it becomes strict.")

    return "\n".join(lines)


def format_human_finding(finding: Finding) -> str:
    location = f"{finding.path}:{finding.line}" if finding.line else finding.path
    return f"  - [{finding.kind}] {location} — {finding.message}"


def render_json(report: Report) -> str:
    payload = {
        "passed": report.passed,
        "errors": [asdict(finding) for finding in report.errors],
        "warnings": [asdict(finding) for finding in report.warnings],
        "metadata": report.metadata,
    }
    return json.dumps(payload, indent=2, sort_keys=True)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Project Dolus maintainability checker.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument(
        "--baseline",
        default=str(Path(__file__).resolve().with_name("maintainability-baseline.json")),
    )
    parser.add_argument("--format", choices=["human", "json"], default="human")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    baseline_path = Path(args.baseline).resolve()
    report = build_report(root, baseline_path)

    if args.format == "json":
        print(render_json(report))
    else:
        print(render_human(report))

    return 1 if not report.passed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
