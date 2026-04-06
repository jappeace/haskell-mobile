#!/usr/bin/env bash
# Common helper functions for iOS simulator test scripts.
# Source this file; do not run directly.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID    — simulator UUID
#   BUNDLE_ID   — me.jappie.haskellmobile
#   WORK_DIR    — temp dir for log files

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
        EXIT_CODE=1
    fi
}

# get_full_log START_TIME OUTFILE
# Retrieves persistent log entries since START_TIME for BUNDLE_ID into OUTFILE.
get_full_log() {
    local start_time="$1"
    local outfile="$2"
    xcrun simctl spawn "$SIM_UDID" log show \
        --start "$start_time" \
        --predicate "subsystem == \"$BUNDLE_ID\"" \
        --style compact \
        --info \
        > "$outfile" 2>&1 || true
}
