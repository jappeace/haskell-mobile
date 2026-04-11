#!/usr/bin/env bash
# Common helper functions for watchOS simulator test scripts.
# Source this file; do not run directly.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID       — simulator UUID
#   BUNDLE_ID      — me.jappie.haskellmobile.watchkitapp (for simctl commands)
#   LOG_SUBSYSTEM  — me.jappie.haskellmobile (for os_log predicates)
#   WORK_DIR       — temp dir for log files

# wait_for_log LOGFILE PATTERN TIMEOUT_SECONDS
# Polls LOGFILE for PATTERN every 2s.
# Returns 0 on success, 1 on timeout.
wait_for_log() {
    local logfile="$1"
    local pattern="$2"
    local timeout_seconds="$3"
    local elapsed=0
    while [ $elapsed -lt "$timeout_seconds" ]; do
        if grep -q "$pattern" "$logfile" 2>/dev/null; then
            echo "Found '$pattern' after ~${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "WARNING: '$pattern' not found after ${timeout_seconds}s"
    return 1
}

# assert_log LOGFILE PATTERN LABEL
# Greps LOGFILE for PATTERN, prints PASS/FAIL with LABEL.
# Sets EXIT_CODE=1 on failure (EXIT_CODE must be declared in caller).
assert_log() {
    local logfile="$1"
    local pattern="$2"
    local label="$3"
    if grep -qE "$pattern" "$logfile" 2>/dev/null; then
        echo "PASS: $label"
    else
        echo "FAIL: $label"
        # shellcheck disable=SC2034  # set for caller
        EXIT_CODE=1
    fi
}

# get_full_log START_TIME OUTFILE
# Retrieves persistent log entries since START_TIME for LOG_SUBSYSTEM into OUTFILE.
get_full_log() {
    local start_time="$1"
    local outfile="$2"
    xcrun simctl spawn "$SIM_UDID" log show \
        --start "$start_time" \
        --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
        --style compact \
        --info \
        > "$outfile" 2>&1 || true
}

# start_app APP_PATH LABEL [LAUNCH_ARGS...]
# Installs app, starts log stream, launches.
# Sets: APP_START_TIME, STREAM_LOG, LOG_STREAM_PID.
start_app() {
    local app_path="$1"
    local label="$2"
    shift 2

    xcrun simctl install "$SIM_UDID" "$app_path"
    echo "App installed ($label)."

    APP_START_TIME=$(date "+%Y-%m-%d %H:%M:%S")

    STREAM_LOG="$WORK_DIR/${label}_stream.txt"
    : > "$STREAM_LOG"
    xcrun simctl spawn "$SIM_UDID" log stream \
        --level info \
        --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
        --style compact \
        > "$STREAM_LOG" 2>&1 &
    LOG_STREAM_PID=$!
    sleep 5

    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" "$@"
}

# wait_for_render LABEL [LAUNCH_ARGS...]
# Waits for "setRoot" with retry+relaunch.
# Uses STREAM_LOG set by start_app.
wait_for_render() {
    local label="$1"
    shift

    local render_done=0
    wait_for_log "$STREAM_LOG" "setRoot" 60 && render_done=1 || true

    if [ $render_done -eq 0 ]; then
        echo "WARNING: setRoot not found — retrying with relaunch"
        xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
        sleep 3
        : > "$STREAM_LOG"
        xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" "$@"
        wait_for_log "$STREAM_LOG" "setRoot" 60 || true
    fi
}

# collect_logs LABEL
# Kills log stream, retrieves persistent log with fallback to stream log.
# Sets: FULL_LOG.
collect_logs() {
    local label="$1"

    kill "$LOG_STREAM_PID" 2>/dev/null || true
    sleep 1

    FULL_LOG="$WORK_DIR/${label}_full.txt"
    get_full_log "$APP_START_TIME" "$FULL_LOG"

    if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
        echo "  'log show' empty/incomplete, using stream log"
        FULL_LOG="$STREAM_LOG"
    fi
}

# cleanup_app
# Terminates app, kills log stream, uninstalls.
cleanup_app() {
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    kill "$LOG_STREAM_PID" 2>/dev/null || true
    xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
}
