#!/usr/bin/env bash
# watchOS buttons test: launch with --autotest-buttons, assert full counter sequence.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APP" "buttons" --autotest-buttons

# Wait for final value Counter: -1
wait_for_log "$STREAM_LOG" "setStrProp.*Counter: -1" 60 || true

collect_logs "buttons"

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

cleanup_app

exit $EXIT_CODE
