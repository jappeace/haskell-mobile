#!/usr/bin/env bash
# watchOS lifecycle test: install counter app, launch, assert lifecycle events.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$COUNTER_APP"
echo "Counter app installed."

LOG_FILE="$WORK_DIR/lifecycle_log.txt"
> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

# Poll for lifecycle events
lifecycle_done=0
if wait_for_log "$LOG_FILE" "Lifecycle: Create" 60 && wait_for_log "$LOG_FILE" "Lifecycle: Resume" 5; then
    lifecycle_done=1
fi

if [ $lifecycle_done -eq 0 ]; then
    echo "WARNING: Lifecycle events not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$LOG_FILE"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    wait_for_log "$LOG_FILE" "Lifecycle: Create" 30 || true
fi

assert_log "$LOG_FILE" "Lifecycle: Create" "Lifecycle: Create"
assert_log "$LOG_FILE" "Lifecycle: Resume" "Lifecycle: Resume"
assert_log "$LOG_FILE" "setRoot" "setRoot"
assert_log "$LOG_FILE" "setStrProp.*Counter:" "setStrProp Counter label"
assert_log "$LOG_FILE" "setHandler.*click" "setHandler click"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
kill "$LOG_STREAM_PID" 2>/dev/null || true
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
