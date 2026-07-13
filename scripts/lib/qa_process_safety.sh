#!/usr/bin/env bash

# Shared safety boundary for UI/benchmark harnesses.
# The caller must set APP_BIN, APP_NAME, and QA_HOME before launching MacWiki.

qa_canonical_path() {
  local path="$1"
  local directory
  directory="$(cd "$(dirname "$path")" && pwd -P)"
  printf '%s/%s\n' "$directory" "$(basename "$path")"
}

qa_assert_trusted_defaults_suite() {
  local suite_name="$1"
  if [[ ! "$suite_name" =~ ^com\.tombunting\.MacWiki\.qa\.[A-Za-z0-9.-]+$ ]]; then
    echo "Refusing untrusted QA defaults suite: $suite_name" >&2
    return 1
  fi
}

qa_assert_supported_network_mode() {
  local mode="${MACWIKI_QA_NETWORK_MODE:-}"
  if [[ -n "$mode" && "$mode" != "offline" ]]; then
    echo "Refusing unsupported QA network mode: $mode" >&2
    return 1
  fi
}

qa_defaults_suite_name() {
  if [[ -n "${QA_DEFAULTS_SUITE:-}" ]]; then
    qa_assert_trusted_defaults_suite "$QA_DEFAULTS_SUITE" || return 1
    printf '%s\n' "$QA_DEFAULTS_SUITE"
    return 0
  fi

  local canonical_root
  local digest
  canonical_root="$(qa_canonical_path "${QA_HOME:?}")"
  digest="$(printf '%s' "$canonical_root" | shasum -a 256 | awk '{ print substr($1, 1, 16) }')"
  printf 'com.tombunting.MacWiki.qa.%s\n' "$digest"
}

qa_delete_defaults_suite() {
  local suite_name="$1"
  qa_assert_trusted_defaults_suite "$suite_name" || return 1
  /usr/bin/defaults delete "$suite_name" >/dev/null 2>&1 || true
  rm -f "$HOME/Library/Preferences/$suite_name.plist"
}

qa_run_command_with_timeout() {
  local timeout_seconds="$1"
  shift
  local input_path
  input_path="$(mktemp "${TMPDIR:-/tmp}/macwiki-qa-command-input.XXXXXX")"
  if [[ -t 0 ]]; then
    : >"$input_path"
  else
    cat >"$input_path"
  fi
  "$@" <"$input_path" &
  local command_pid=$!
  local elapsed_ticks=0
  local maximum_ticks=$((timeout_seconds * 10))
  while kill -0 "$command_pid" 2>/dev/null; do
    if (( elapsed_ticks >= maximum_ticks )); then
      kill "$command_pid" 2>/dev/null || true
      wait "$command_pid" 2>/dev/null || true
      rm -f "$input_path"
      return 124
    fi
    sleep 0.1
    elapsed_ticks=$((elapsed_ticks + 1))
  done
  local command_status=0
  wait "$command_pid" || command_status=$?
  rm -f "$input_path"
  return "$command_status"
}

qa_assert_isolated_path() {
  local candidate="$1"
  local root="$2"
  local canonical_candidate
  local canonical_root

  mkdir -p "$root"
  canonical_root="$(qa_canonical_path "$root")"
  canonical_candidate="$(qa_canonical_path "$candidate")"

  case "$canonical_root" in
    /tmp/macwiki-qa/*|/private/tmp/macwiki-qa/*|"${REPO_ROOT:?}"/.qa/*)
      ;;
    *)
      echo "ERROR: QA_HOME must be under /tmp/macwiki-qa or $REPO_ROOT/.qa: $canonical_root" >&2
      return 1
      ;;
  esac

  case "$canonical_candidate" in
    "$canonical_root"|"$canonical_root"/*)
      ;;
    *)
      echo "ERROR: Refusing path outside isolated QA_HOME: $canonical_candidate" >&2
      return 1
      ;;
  esac
}

qa_prepare_isolated_home() {
  qa_assert_isolated_path "$QA_HOME" "$QA_HOME"
  mkdir -p "$QA_HOME/Library/Application Support" "$QA_HOME/Library/Caches"
  QA_DEFAULTS_SUITE="$(qa_defaults_suite_name)"
  export QA_DEFAULTS_SUITE
  qa_delete_defaults_suite "$QA_DEFAULTS_SUITE"
}

qa_exact_binary_pids() {
  [[ -x "$APP_BIN" ]] || return 0
  local canonical_binary
  local pid
  local executable_path
  canonical_binary="$(qa_canonical_path "$APP_BIN")"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    executable_path="$(qa_pid_executable_path "$pid")"
    [[ -n "$executable_path" ]] || continue
    if [[ "$(qa_canonical_path "$executable_path")" == "$canonical_binary" ]]; then
      printf '%s\n' "$pid"
    fi
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

qa_pid_executable_path() {
  local pid="$1"
  /usr/sbin/lsof -a -p "$pid" -d txt -Fn 2>/dev/null \
    | awk '/^n/ { print substr($0, 2); exit }'
}

qa_assert_no_conflicting_processes() {
  local pid
  local command_path
  local found=0

  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    found=1
    command_path="$(ps -p "$pid" -o comm= | sed 's/^[[:space:]]*//')"
    echo "ERROR: Refusing to run while $APP_NAME PID $pid is active ($command_path)." >&2
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)

  [[ "$found" -eq 0 ]]
}

qa_launch_exact() {
  local log_path="$1"
  qa_assert_isolated_path "$QA_HOME" "$QA_HOME"
  qa_assert_no_conflicting_processes

  qa_assert_supported_network_mode
  local environment=(
    "HOME=$QA_HOME"
    "CFFIXED_USER_HOME=$QA_HOME"
    "MACWIKI_QA_DEFAULTS_SUITE=${QA_DEFAULTS_SUITE:?}"
  )
  if [[ -n "${MACWIKI_QA_NETWORK_MODE:-}" ]]; then
    environment+=("MACWIKI_QA_NETWORK_MODE=$MACWIKI_QA_NETWORK_MODE")
  fi
  /usr/bin/env "${environment[@]}" "$APP_BIN" >"$log_path" 2>&1 &
  QA_APP_PID=$!
  export QA_APP_PID

  local expected
  local actual
  expected="$(qa_canonical_path "$APP_BIN")"
  for _ in $(seq 1 50); do
    if kill -0 "$QA_APP_PID" 2>/dev/null; then
      actual="$(qa_pid_executable_path "$QA_APP_PID")"
      if [[ "$actual" == "$expected" ]]; then
        return 0
      fi
    fi
    sleep 0.1
  done

  echo "ERROR: Launched PID $QA_APP_PID did not resolve to $expected." >&2
  qa_stop_exact
  return 1
}

qa_launch_exact_bundle() {
  local log_path="$1"
  local bundle_path="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
  local expected_binary

  qa_assert_isolated_path "$QA_HOME" "$QA_HOME"
  qa_assert_no_conflicting_processes
  qa_assert_supported_network_mode

  expected_binary="$(qa_canonical_path "$APP_BIN")"
  if [[ "$bundle_path" == "$APP_BIN" || ! -d "$bundle_path/Contents/MacOS" ]]; then
    echo "ERROR: APP_BIN is not inside an app bundle: $APP_BIN" >&2
    return 1
  fi

  local open_arguments=(
    -n
    --stdout "$log_path"
    --stderr "$log_path"
    --env "HOME=$QA_HOME"
    --env "CFFIXED_USER_HOME=$QA_HOME"
    --env "MACWIKI_QA_DEFAULTS_SUITE=${QA_DEFAULTS_SUITE:?}"
  )
  if [[ -n "${MACWIKI_QA_NETWORK_MODE:-}" ]]; then
    open_arguments+=(--env "MACWIKI_QA_NETWORK_MODE=$MACWIKI_QA_NETWORK_MODE")
  fi
  open "${open_arguments[@]}" -a "$bundle_path"

  for _ in $(seq 1 50); do
    local matching_pids=()
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && matching_pids+=("$pid")
    done < <(qa_exact_binary_pids)

    if [[ "${#matching_pids[@]}" -eq 1 ]]; then
      QA_APP_PID="${matching_pids[0]}"
      export QA_APP_PID
      local actual
      actual="$(qa_pid_executable_path "$QA_APP_PID")"
      if [[ "$actual" == "$expected_binary" ]]; then
        return 0
      fi
    fi
    sleep 0.1
  done

  echo "ERROR: App bundle launch did not resolve to exactly one $expected_binary process." >&2
  qa_stop_matching_exact
  return 1
}

qa_launch_candidate() {
  local log_path="$1"
  local bundle_path="${APP_BUNDLE_PATH:-${APP_BIN%/Contents/MacOS/*}}"
  if [[ "$bundle_path" != "$APP_BIN" && -d "$bundle_path/Contents/MacOS" ]]; then
    qa_launch_exact_bundle "$log_path"
  else
    qa_launch_exact "$log_path"
  fi
}

qa_stop_exact() {
  local pid="${QA_APP_PID:-}"
  [[ -n "$pid" ]] || return 0

  local expected
  local actual
  expected="$(qa_canonical_path "$APP_BIN")"
  actual="$(qa_pid_executable_path "$pid")"
  if [[ -n "$actual" && "$actual" == "$expected" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  QA_APP_PID=""
  export QA_APP_PID
}

qa_stop_matching_exact() {
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done < <(qa_exact_binary_pids)
}

qa_remove_isolated_home() {
  [[ -n "${QA_HOME:-}" ]] || return 0
  qa_assert_isolated_path "$QA_HOME" "$QA_HOME"
  if [[ "${QA_DEFAULTS_SUITE:-}" == com.tombunting.MacWiki.qa.* ]]; then
    qa_delete_defaults_suite "$QA_DEFAULTS_SUITE"
  fi
  QA_DEFAULTS_SUITE=""
  export QA_DEFAULTS_SUITE
  rm -rf "$QA_HOME"
}
