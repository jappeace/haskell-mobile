#!/usr/bin/env bash
# iOS UI test: install counter app, launch with --autotest, assert Counter: 1.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APP" "ui" --autotest

ui_done=0
wait_for_log "$STREAM_LOG" "setStrProp.*Counter: 1" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_ios_log "$STREAM_LOG" "ui"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
if [ $WAIT_RC -eq 0 ]; then
    ui_done=1
fi

if [ $ui_done -eq 0 ]; then
    echo "WARNING: Counter: 1 not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    : > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest
    wait_for_log "$STREAM_LOG" "setStrProp.*Counter: 1" 60 || true
fi

assert_log "$STREAM_LOG" "setStrProp.*Counter: 1" "Counter: 1 after --autotest tap"

cleanup_app

exit $EXIT_CODE
