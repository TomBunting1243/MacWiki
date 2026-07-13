#!/usr/bin/env python3

import argparse
import csv
import json
import math
from pathlib import Path


def percentile(values: list[float], percentile_value: float) -> float:
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * percentile_value
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] + (ordered[upper] - ordered[lower]) * fraction


def load_metric_csv(paths: list[Path]) -> dict[str, list[float]]:
    samples: dict[str, list[float]] = {}
    for path in paths:
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                samples.setdefault(row["kind"], []).append(float(row["duration_ms"]))
    return samples


def load_reader_tsv(path: Path) -> tuple[list[float], list[float]]:
    cold: list[float] = []
    warm: list[float] = []
    with path.open(newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle, delimiter="\t"):
            if not row.get("reveal_ms"):
                continue
            duration = float(row["reveal_ms"])
            if row.get("kind") == "cold":
                cold.append(duration)
            elif row.get("kind") == "warmDisk":
                warm.append(duration)
    return cold, warm


def measured_value(values: list[float], statistic: str) -> float:
    if statistic == "p95":
        return percentile(values, 0.95)
    if statistic == "maximum":
        return max(values)
    raise ValueError(f"Unsupported statistic: {statistic}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify MacWiki internal-beta performance budgets.")
    parser.add_argument("--budgets", type=Path, required=True)
    parser.add_argument("--metrics-csv", type=Path, action="append", default=[])
    parser.add_argument("--reader-runs", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    budgets = json.loads(args.budgets.read_text(encoding="utf-8"))["metrics"]
    metrics = load_metric_csv(args.metrics_csv)
    reader_cold, reader_warm = load_reader_tsv(args.reader_runs)
    samples = {
        "search": metrics.get("search", []),
        "sidebarHydration": metrics.get("sidebarHydration", []),
        "sessionRestore": metrics.get("sessionRestore", []),
        "readerColdReveal": reader_cold,
        "readerWarmReveal": reader_warm,
    }

    lines = ["# Internal Beta Performance Budget Report", ""]
    failures: list[str] = []
    for name, budget in budgets.items():
        values = samples.get(name, [])
        minimum_samples = int(budget["minimumSamples"])
        maximum = float(budget["maximumMilliseconds"])
        statistic = budget["statistic"]
        if len(values) < minimum_samples:
            failures.append(f"{name}: expected at least {minimum_samples} samples, found {len(values)}")
            lines.append(f"- FAIL `{name}`: {len(values)}/{minimum_samples} required samples")
            continue
        measured = measured_value(values, statistic)
        passed = measured <= maximum
        lines.append(
            f"- {'PASS' if passed else 'FAIL'} `{name}`: {statistic} {measured:.1f} ms "
            f"<= {maximum:.1f} ms (n={len(values)})"
        )
        if not passed:
            failures.append(f"{name}: {measured:.1f} ms exceeds {maximum:.1f} ms")

    lines.extend(["", f"Overall: **{'FAIL' if failures else 'PASS'}**"])
    report = "\n".join(lines) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding="utf-8")
    print(report, end="")
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
