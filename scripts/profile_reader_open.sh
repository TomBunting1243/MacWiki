#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/profile_reader_open.sh [options]

Repeatable reader-open benchmark harness for MacWiki.
It seeds app state to a single target article, runs cold/warm launches,
collects `article-open` timing logs, optionally records one Time Profiler trace,
and writes a markdown report.

Options:
  --article-title TEXT         Target article title (default: "Nintendo Wii")
  --article-id TEXT            Target article id (default: "Nintendo Wii")
  --app-binary PATH            App executable to benchmark (default: APP_BINARY or .build/debug/MacWiki)
  --cold-runs N               Number of cold runs (default: 1)
  --warm-runs N               Number of warm runs (default: 3)
  --timeout-seconds N         Max wait per run for article-open log (default: 45)
  --output-dir PATH           Output directory (default: /tmp/macwiki_profiles/bench_YYYYmmdd_HHMMSS)
  --trace-seconds N           Time Profiler duration in seconds (default: 12)
  --post-reveal-window-ms N   Trace marker window after reveal in ms (default: 3000)
  --scroll-pulses N           Space key presses during trace run (default: 12)
  --scroll-interval S         Delay between key presses (default: 0.35)
  --scroll-start-delay S      Delay before key presses start (default: 6)
  --skip-build                Skip `swift build`
  --no-trace                  Skip Time Profiler capture
  --keep-seeded-state         Preserve the isolated QA home on exit for inspection
  --help                      Show this message
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/qa_process_safety.sh"
APP_NAME="${APP_NAME:-MacWiki}"
APP_BINARY="${APP_BINARY:-$REPO_ROOT/.build/debug/MacWiki}"
APP_BIN="$APP_BINARY"
QA_HOME="${QA_HOME:-/tmp/macwiki-qa/profile-reader-$(date +%Y%m%d_%H%M%S)-$RANDOM}"
STATE_FILE="$QA_HOME/Library/Application Support/MacWiki/state.json"
STATE_DIR="$(dirname "$STATE_FILE")"
CACHE_ROOT="$QA_HOME/Library/Caches/MacWiki"
URLCACHE_HOME="$QA_HOME/Library/Caches/MacWikiURLCache"

article_title="Nintendo Wii"
article_id="Nintendo Wii"
cold_runs=1
warm_runs=3
timeout_seconds=45
trace_seconds=12
post_reveal_window_ms=3000
scroll_pulses=12
scroll_interval=0.35
scroll_start_delay=6
skip_build=0
do_trace=1
keep_seeded_state=0
output_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --article-title)
      article_title="$2"
      shift 2
      ;;
    --article-id)
      article_id="$2"
      shift 2
      ;;
    --app-binary)
      APP_BINARY="$2"
      shift 2
      ;;
    --cold-runs)
      cold_runs="$2"
      shift 2
      ;;
    --warm-runs)
      warm_runs="$2"
      shift 2
      ;;
    --timeout-seconds)
      timeout_seconds="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --trace-seconds)
      trace_seconds="$2"
      shift 2
      ;;
    --post-reveal-window-ms)
      post_reveal_window_ms="$2"
      shift 2
      ;;
    --scroll-pulses)
      scroll_pulses="$2"
      shift 2
      ;;
    --scroll-interval)
      scroll_interval="$2"
      shift 2
      ;;
    --scroll-start-delay)
      scroll_start_delay="$2"
      shift 2
      ;;
    --skip-build)
      skip_build=1
      shift
      ;;
    --no-trace)
      do_trace=0
      shift
      ;;
    --keep-seeded-state)
      keep_seeded_state=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

APP_BIN="$APP_BINARY"

if [[ -z "$output_dir" ]]; then
  output_dir="/tmp/macwiki_profiles/bench_$(date +%Y%m%d_%H%M%S)"
fi

log_dir="$output_dir/logs"
mkdir -p "$log_dir"
mkdir -p "$STATE_DIR"

raw_runs_tsv="$output_dir/runs_raw.tsv"
runs_tsv="$output_dir/runs.tsv"
report_md="$output_dir/report.md"
trace_path="$output_dir/time_profile.trace"
trace_xml="$output_dir/time_profile.xml"
state_backup="$output_dir/state_backup.json"
state_had_original=0

echo -e "label\tmode\tlog_line" >"$raw_runs_tsv"

kill_macwiki() {
  qa_stop_exact
  qa_stop_matching_exact
  sleep 0.6
}

restore_state() {
  if [[ "$keep_seeded_state" -eq 1 ]]; then
    return 0
  fi
  if [[ "$state_had_original" -eq 1 && -f "$state_backup" ]]; then
    cp "$state_backup" "$STATE_FILE"
  elif [[ "$state_had_original" -eq 0 ]]; then
    rm -f "$STATE_FILE"
  fi
}

cleanup() {
  kill_macwiki
  restore_state
  if [[ "$keep_seeded_state" -eq 0 ]]; then
    qa_remove_isolated_home
  else
    echo "Preserved isolated QA home: $QA_HOME"
  fi
}
trap cleanup EXIT INT TERM

qa_prepare_isolated_home
qa_assert_no_conflicting_processes

if [[ -f "$STATE_FILE" ]]; then
  cp "$STATE_FILE" "$state_backup"
  state_had_original=1
fi

if [[ "$skip_build" -eq 0 ]]; then
  echo "Building MacWiki..."
  (cd "$REPO_ROOT" && swift build)
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "App binary not found: $APP_BINARY" >&2
  exit 1
fi

seed_state() {
  local tab_id
  local history_id
  tab_id="$(uuidgen)"
  history_id="$(uuidgen)"
  jq -n \
    --arg tab_id "$tab_id" \
    --arg history_id "$history_id" \
    --arg article_id "$article_id" \
    --arg article_title "$article_title" \
    '{
      openTabs: [
        {
          id: $tab_id,
          history: [
            {
              id: $history_id,
              article: {
                id: $article_id,
                title: $article_title,
                description: null,
                extract: null,
                thumbnailURL: null,
                htmlContent: null,
                lastOpened: null,
                isRead: false,
                wordCount: null
              },
              scrollPosition: 0
            }
          ],
          currentIndex: 0,
          isNewTab: false
        }
      ],
      activeTabId: $tab_id,
      recentArticles: [
        {
          id: $article_id,
          title: $article_title,
          description: null,
          extract: null,
          thumbnailURL: null,
          htmlContent: null,
          lastOpened: null,
          isRead: false,
          wordCount: null
        }
      ]
    }' >"$STATE_FILE"
}

clear_caches_for_cold() {
  qa_assert_isolated_path "$CACHE_ROOT" "$QA_HOME"
  qa_assert_isolated_path "$URLCACHE_HOME" "$QA_HOME"
  rm -rf "$CACHE_ROOT"
  rm -rf "$URLCACHE_HOME"
}

start_article_open_stream() {
  local output_file="$1"
  : >"$output_file"
  /usr/bin/log stream \
    --style compact \
    --predicate 'subsystem == "com.macwiki" && category == "article-open" && eventMessage CONTAINS "article-open"' \
    --info >"$output_file" 2>/dev/null &
  local stream_pid=$!
  sleep 0.5
  echo "$stream_pid"
}

wait_for_article_open() {
  local stream_file="$1"
  local timeout="$2"
  local elapsed=0
  local line
  while (( elapsed < timeout )); do
    line="$(grep 'article-open \[' "$stream_file" | tail -n 1 || true)"
    if [[ -n "$line" ]]; then
      printf '%s' "$line"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

run_direct_open() {
  local label="$1"
  local mode="$2"
  local clear_cold="$3"
  local stdout_log="$log_dir/${label}.stdout.log"
  local stream_log="$log_dir/${label}.article_open.log"
  local line=""
  local stream_pid=""

  kill_macwiki
  seed_state
  if [[ "$clear_cold" -eq 1 ]]; then
    clear_caches_for_cold
  fi

  stream_pid="$(start_article_open_stream "$stream_log")"
  qa_launch_candidate "$stdout_log"
  local app_pid="$QA_APP_PID"

  if line="$(wait_for_article_open "$stream_log" "$timeout_seconds")"; then
    :
  else
    line="$(grep 'article-open \[' "$stream_log" | tail -n 1 || true)"
  fi

  kill "$stream_pid" >/dev/null 2>&1 || true
  wait "$stream_pid" 2>/dev/null || true
  qa_stop_exact
  kill_macwiki

  printf '%s\t%s\t%s\n' "$label" "$mode" "$line" >>"$raw_runs_tsv"
  if [[ -n "$line" ]]; then
    echo "[$label] $line"
  else
    echo "[$label] no article-open log captured"
  fi
}

drive_scroll_input() {
  local pulses="$1"
  local interval="$2"
  local delay="$3"
  (
    sleep "$delay"
    exact_pid=""
    for _ in $(seq 1 80); do
      candidate_pids="$(qa_exact_binary_pids)"
      pid_count="$(printf '%s\n' "$candidate_pids" | awk 'NF { count += 1 } END { print count + 0 }')"
      if [[ "$pid_count" -eq 1 ]]; then
        exact_pid="$candidate_pids"
        break
      fi
      sleep 0.1
    done
    [[ -n "$exact_pid" ]] || exit 0

    osascript - "$exact_pid" <<'APPLESCRIPT' || exit 0
on run argv
  set targetPID to item 1 of argv as integer
  tell application "System Events"
    set frontmost of first process whose unix id is targetPID to true
  end tell
end run
APPLESCRIPT
    for ((i = 0; i < pulses; i++)); do
      osascript -e 'tell application "System Events" to key code 49' || true
      sleep "$interval"
    done
  ) >/dev/null 2>&1 &
  echo $!
}

run_trace_capture() {
  local label="$1"
  local mode="$2"
  local trace_log="$log_dir/${label}_trace.log"
  local stream_log="$log_dir/${label}.article_open.log"
  local line=""
  local input_pid=""
  local stream_pid=""

  kill_macwiki
  seed_state

  stream_pid="$(start_article_open_stream "$stream_log")"
  input_pid="$(drive_scroll_input "$scroll_pulses" "$scroll_interval" "$scroll_start_delay")"

  rm -rf "$trace_path"
  set +e
  qa_run_command_with_timeout "$((trace_seconds + 30))" xcrun xctrace record \
    --template 'Time Profiler' \
    --time-limit "${trace_seconds}s" \
    --output "$trace_path" \
    --launch -- /usr/bin/env \
      "HOME=$QA_HOME" \
      "CFFIXED_USER_HOME=$QA_HOME" \
      "MACWIKI_QA_DEFAULTS_SUITE=$QA_DEFAULTS_SUITE" \
      "$APP_BINARY" >"$trace_log" 2>&1
  local trace_status=$?
  set -e
  if [[ "$trace_status" -ne 0 && ! -d "$trace_path" ]]; then
    echo "Trace capture failed; see $trace_log" >&2
  fi

  kill "$input_pid" >/dev/null 2>&1 || true
  kill "$stream_pid" >/dev/null 2>&1 || true
  wait "$stream_pid" 2>/dev/null || true
  sleep 1

  line="$(grep 'article-open \[' "$stream_log" | tail -n 1 || true)"
  printf '%s\t%s\t%s\n' "$label" "$mode" "$line" >>"$raw_runs_tsv"
  if [[ -n "$line" ]]; then
    echo "[$label] $line"
  else
    echo "[$label] no article-open log captured"
  fi

  if [[ -d "$trace_path" ]]; then
    if ! qa_run_command_with_timeout 90 xcrun xctrace export \
      --input "$trace_path" \
      --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
      >"$trace_xml" 2>"$log_dir/${label}_trace_export.log"; then
      echo "Trace export failed; see $log_dir/${label}_trace_export.log" >&2
      rm -f "$trace_xml"
    fi
  fi

  kill_macwiki
}

for ((i = 1; i <= cold_runs; i++)); do
  run_direct_open "cold_${i}" "cold" 1
done

for ((i = 1; i <= warm_runs; i++)); do
  run_direct_open "warm_${i}" "warm" 0
done

if [[ "$do_trace" -eq 1 ]]; then
  run_trace_capture "trace_warm_1" "trace_warm"
fi

python3 - "$raw_runs_tsv" "$runs_tsv" "$report_md" "$trace_xml" "$post_reveal_window_ms" <<'PY'
import csv
import os
import re
import statistics
import sys
from datetime import datetime

raw_tsv = sys.argv[1]
runs_tsv = sys.argv[2]
report_md = sys.argv[3]
trace_xml = sys.argv[4]
post_window_ms = int(sys.argv[5])

line_re = re.compile(
    r"article-open \[(?P<kind>[^\]]+)\] (?P<title>.*?): (?P<phases>.*)$"
)
phase_re = re.compile(r"([a-zA-Z]+)=([0-9]+)ms")

def parse_log_line(line: str):
    m = line_re.search(line or "")
    if not m:
        return None
    phases = {}
    for key, value in phase_re.findall(m.group("phases")):
        phases[key] = int(value)
    return {
        "kind": m.group("kind"),
        "title": m.group("title"),
        "fetch_ms": phases.get("fetch"),
        "bind_ms": phases.get("bind"),
        "didFinish_ms": phases.get("didFinish"),
        "highlights_ms": phases.get("highlights"),
        "reveal_ms": phases.get("reveal"),
    }

rows = []
with open(raw_tsv, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f, delimiter="\t")
    for item in reader:
        parsed = parse_log_line(item["log_line"])
        if parsed is None:
            rows.append(
                {
                    "label": item["label"],
                    "mode": item["mode"],
                    "kind": "",
                    "title": "",
                    "fetch_ms": None,
                    "bind_ms": None,
                    "didFinish_ms": None,
                    "highlights_ms": None,
                    "reveal_ms": None,
                    "log_line": item["log_line"],
                }
            )
            continue
        rows.append(
            {
                "label": item["label"],
                "mode": item["mode"],
                "kind": parsed["kind"],
                "title": parsed["title"],
                "fetch_ms": parsed["fetch_ms"],
                "bind_ms": parsed["bind_ms"],
                "didFinish_ms": parsed["didFinish_ms"],
                "highlights_ms": parsed["highlights_ms"],
                "reveal_ms": parsed["reveal_ms"],
                "log_line": item["log_line"],
            }
        )

with open(runs_tsv, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f, delimiter="\t")
    writer.writerow(
        [
            "label",
            "mode",
            "kind",
            "title",
            "fetch_ms",
            "bind_ms",
            "didFinish_ms",
            "highlights_ms",
            "reveal_ms",
            "log_line",
        ]
    )
    for row in rows:
        writer.writerow(
            [
                row["label"],
                row["mode"],
                row["kind"],
                row["title"],
                row["fetch_ms"] if row["fetch_ms"] is not None else "",
                row["bind_ms"] if row["bind_ms"] is not None else "",
                row["didFinish_ms"] if row["didFinish_ms"] is not None else "",
                row["highlights_ms"] if row["highlights_ms"] is not None else "",
                row["reveal_ms"] if row["reveal_ms"] is not None else "",
                row["log_line"],
            ]
        )

def percentile(values, pct):
    if not values:
        return None
    if len(values) == 1:
        return float(values[0])
    values = sorted(values)
    rank = (pct / 100) * (len(values) - 1)
    low = int(rank)
    high = min(low + 1, len(values) - 1)
    frac = rank - low
    return values[low] + (values[high] - values[low]) * frac

def summarize_observed_cohort(cohort_name):
    if cohort_name == "cold":
        selected = [r for r in rows if r["kind"] == "cold" and r["reveal_ms"] is not None]
    else:
        selected = [
            r for r in rows
            if r["mode"] == "warm" and r["kind"] != "cold" and r["reveal_ms"] is not None
        ]
    reveal = [r["reveal_ms"] for r in selected if r["reveal_ms"] is not None]
    did_finish = [r["didFinish_ms"] for r in selected if r["didFinish_ms"] is not None]
    return {
        "n": len(selected),
        "reveal_p50": percentile(reveal, 50),
        "reveal_p95": percentile(reveal, 95),
        "did_finish_p50": percentile(did_finish, 50),
        "did_finish_p95": percentile(did_finish, 95),
    }

cold_summary = summarize_observed_cohort("cold")
warm_summary = summarize_observed_cohort("warm")

trace_markers = None
trace_row = next((r for r in rows if r["mode"].startswith("trace") and r["reveal_ms"] is not None), None)
if trace_row and os.path.exists(trace_xml):
    reveal_ns = int(trace_row["reveal_ms"] * 1_000_000)
    window_ns = int(post_window_ms * 1_000_000)
    end_ns = reveal_ns + window_ns
    thread_names = {}
    total_rows = 0
    main_thread_rows = 0
    webkit_rows = 0
    swiftui_rows = 0

    sample_re = re.compile(r"<sample-time[^>]*>(\d+)</sample-time>")
    thread_id_re = re.compile(r'<thread id="([^"]+)" fmt="([^"]+)"')
    thread_ref_re = re.compile(r'<thread ref="([^"]+)"')

    with open(trace_xml, encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "<row><sample-time" not in line:
                continue
            thread_id_match = thread_id_re.search(line)
            if thread_id_match:
                thread_names[thread_id_match.group(1)] = thread_id_match.group(2)
            sample_match = sample_re.search(line)
            if not sample_match:
                continue
            sample_ns = int(sample_match.group(1))
            if sample_ns < reveal_ns or sample_ns > end_ns:
                continue

            total_rows += 1

            thread_name = ""
            if thread_id_match:
                thread_name = thread_id_match.group(2)
            else:
                thread_ref_match = thread_ref_re.search(line)
                if thread_ref_match:
                    thread_name = thread_names.get(thread_ref_match.group(1), "")

            if "Main Thread" in thread_name:
                main_thread_rows += 1
            if "WebKit" in line or "JavaScriptCore" in line:
                webkit_rows += 1
            if "SwiftUI" in line or "SwiftUICore" in line:
                swiftui_rows += 1

    def pct(part, whole):
        return (100.0 * part / whole) if whole else 0.0

    trace_markers = {
        "trace_label": trace_row["label"],
        "reveal_ms": trace_row["reveal_ms"],
        "window_ms": post_window_ms,
        "total_rows": total_rows,
        "main_thread_rows": main_thread_rows,
        "main_thread_pct": pct(main_thread_rows, total_rows),
        "webkit_rows": webkit_rows,
        "webkit_pct": pct(webkit_rows, total_rows),
        "swiftui_rows": swiftui_rows,
        "swiftui_pct": pct(swiftui_rows, total_rows),
    }

def fmt_ms(value):
    if value is None:
        return "n/a"
    return f"{value:.1f}"

def fmt_int(value):
    if value is None:
        return "n/a"
    return str(value)

timestamp = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")

with open(report_md, "w", encoding="utf-8") as out:
    out.write("# MacWiki Reader Open Benchmark\n\n")
    out.write(f"Generated: {timestamp}\n\n")
    out.write("## Run Configuration\n\n")
    sample_title = next((r["title"] for r in rows if r["title"]), "n/a")
    out.write(f"- Article: `{sample_title}`\n")
    out.write(f"- Total runs captured: `{len(rows)}`\n")
    out.write(f"- Observed cold runs: `{cold_summary['n']}`\n")
    out.write(f"- Observed warm-disk runs: `{warm_summary['n']}`\n\n")

    out.write("## Per-Run Timings\n\n")
    out.write("| Run | Mode | Kind | Fetch (ms) | didFinish (ms) | Reveal (ms) |\n")
    out.write("|---|---|---|---:|---:|---:|\n")
    for row in rows:
        out.write(
            f"| {row['label']} | {row['mode']} | {row['kind'] or 'n/a'} | "
            f"{fmt_int(row['fetch_ms'])} | {fmt_int(row['didFinish_ms'])} | {fmt_int(row['reveal_ms'])} |\n"
        )
    out.write("\n")

    out.write("## Cohort Summary\n\n")
    out.write("| Cohort | n | Reveal p50 (ms) | Reveal p95 (ms) | didFinish p50 (ms) | didFinish p95 (ms) |\n")
    out.write("|---|---:|---:|---:|---:|---:|\n")
    out.write(
        f"| cold | {cold_summary['n']} | {fmt_ms(cold_summary['reveal_p50'])} | {fmt_ms(cold_summary['reveal_p95'])} | "
        f"{fmt_ms(cold_summary['did_finish_p50'])} | {fmt_ms(cold_summary['did_finish_p95'])} |\n"
    )
    out.write(
        f"| warm-disk | {warm_summary['n']} | {fmt_ms(warm_summary['reveal_p50'])} | {fmt_ms(warm_summary['reveal_p95'])} | "
        f"{fmt_ms(warm_summary['did_finish_p50'])} | {fmt_ms(warm_summary['did_finish_p95'])} |\n"
    )
    out.write("\n")

    out.write("## Post-Reveal Trace Markers\n\n")
    if trace_markers is None:
        out.write("No post-reveal trace markers available (trace missing or reveal log missing).\n\n")
    else:
        out.write(f"- Trace run: `{trace_markers['trace_label']}`\n")
        out.write(f"- Reveal at: `{trace_markers['reveal_ms']} ms`\n")
        out.write(f"- Window: `+0` to `+{trace_markers['window_ms']} ms` after reveal\n")
        out.write(f"- Time-profile sample rows in window: `{trace_markers['total_rows']}`\n")
        out.write(
            f"- Rows with Main Thread attribution: `{trace_markers['main_thread_rows']}` "
            f"(`{trace_markers['main_thread_pct']:.1f}%`)\n"
        )
        out.write(
            f"- Rows containing WebKit/JavaScriptCore frames: `{trace_markers['webkit_rows']}` "
            f"(`{trace_markers['webkit_pct']:.1f}%`)\n"
        )
        out.write(
            f"- Rows containing SwiftUI/SwiftUICore frames: `{trace_markers['swiftui_rows']}` "
            f"(`{trace_markers['swiftui_pct']:.1f}%`)\n\n"
        )

    out.write("## Artifacts\n\n")
    out.write(f"- Parsed runs TSV: `{runs_tsv}`\n")
    out.write(f"- Raw runs TSV: `{raw_tsv}`\n")
    out.write(f"- Trace XML: `{trace_xml}`\n")
    out.write("\n")
PY

echo
echo "Benchmark complete."
echo "Report: $report_md"
echo "Runs TSV: $runs_tsv"
if [[ -f "$trace_xml" ]]; then
  echo "Trace XML: $trace_xml"
fi
