#!/usr/bin/env bash
# watchOS lifecycle test: install counter app, launch, assert lifecycle events.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APP" "lifecycle"

# Poll for lifecycle events
lifecycle_done=0
if wait_for_log "$STREAM_LOG" "Lifecycle: Create" 60 && wait_for_log "$STREAM_LOG" "Lifecycle: Resume" 5; then
    lifecycle_done=1
fi

if [ $lifecycle_done -eq 0 ]; then
    echo "WARNING: Lifecycle events not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    : > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    wait_for_log "$STREAM_LOG" "Lifecycle: Create" 30 || true
fi

assert_log "$STREAM_LOG" "Lifecycle: Create" "Lifecycle: Create"
assert_log "$STREAM_LOG" "Lifecycle: Resume" "Lifecycle: Resume"
assert_log "$STREAM_LOG" "setRoot" "setRoot"
assert_log "$STREAM_LOG" "setStrProp.*Counter:" "setStrProp Counter label"
assert_log "$STREAM_LOG" "setHandler.*click" "setHandler click"

cleanup_app

exit $EXIT_CODE
