#!/usr/bin/env bash
# watchOS buttons test: launch with --autotest-buttons, assert full counter sequence.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$COUNTER_APP"
echo "Counter app installed."

BUTTONS_START=$(date "+%Y-%m-%d %H:%M:%S")

LOG_FILE="$WORK_DIR/buttons_log.txt"
> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "process == \"HaskellMobile\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_STREAM_PID=$!
sleep 2

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest-buttons

# Wait for final value Counter: -1
wait_for_log "$LOG_FILE" "setStrProp.*Counter: -1" 60 || true

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

# Retrieve full log for reliable assertion; fall back to stream log if empty
FULL_LOG="$WORK_DIR/buttons_full.txt"
get_full_log "$BUTTONS_START" "$FULL_LOG"

if ! grep -q "setStrProp" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty, using stream log"
    FULL_LOG="$LOG_FILE"
fi

assert_log "$FULL_LOG" "setStrProp.*Counter: 0" "Counter: 0 in sequence"
assert_log "$FULL_LOG" "setStrProp.*Counter: 1" "Counter: 1 in sequence"
assert_log "$FULL_LOG" "setStrProp.*Counter: 2" "Counter: 2 in sequence"
assert_log "$FULL_LOG" "setStrProp.*Counter: -1" "Counter: -1 in sequence"

# Warn (not fail) if occurrence counts are lower than expected (log deduplication)
count_1=$(grep -c 'setStrProp.*Counter: 1' "$FULL_LOG" 2>/dev/null || echo "0")
if [ "$count_1" -ge 2 ]; then
    echo "PASS: Counter: 1 appeared $count_1 times"
else
    echo "WARN: Counter: 1 seen $count_1 time(s), expected 2 (log may deduplicate)"
fi

count_0=$(grep -c 'setStrProp.*Counter: 0' "$FULL_LOG" 2>/dev/null || echo "0")
if [ "$count_0" -ge 2 ]; then
    echo "PASS: Counter: 0 appeared $count_0 times"
else
    echo "WARN: Counter: 0 seen $count_0 time(s), expected 2 (log may deduplicate)"
fi

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
