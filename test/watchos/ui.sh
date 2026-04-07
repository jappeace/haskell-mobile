#!/usr/bin/env bash
# watchOS UI test: install counter app, launch with --autotest, assert Counter: 1.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$COUNTER_APP"
echo "Counter app installed."

LOG_FILE="$WORK_DIR/ui_log.txt"
> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest

ui_done=0
wait_for_log "$LOG_FILE" "setStrProp.*Counter: 1" 60 && ui_done=1 || true

if [ $ui_done -eq 0 ]; then
    echo "WARNING: Counter: 1 not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$LOG_FILE"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest
    wait_for_log "$LOG_FILE" "setStrProp.*Counter: 1" 60 || true
fi

assert_log "$LOG_FILE" "setStrProp.*Counter: 1" "Counter: 1 after --autotest tap"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
kill "$LOG_STREAM_PID" 2>/dev/null || true
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
