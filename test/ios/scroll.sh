#!/usr/bin/env bash
# iOS scroll test: install scroll app, launch with --autotest, assert scroll + click events.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, SCROLL_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$SCROLL_APP"
echo "Scroll app installed."

SCROLL_START=$(date "+%Y-%m-%d %H:%M:%S")

STREAM_LOG="$WORK_DIR/scroll_stream.txt"
> "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$BUNDLE_ID\"" \
    --style compact \
    > "$STREAM_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest

render_done=0
wait_for_log "$STREAM_LOG" "setRoot" 60 && render_done=1 || true

if [ $render_done -eq 0 ]; then
    echo "WARNING: setRoot not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest
    wait_for_log "$STREAM_LOG" "setRoot" 60 || true
fi

# Auto-tap fires 3s after render; poll stream log until click appears or 30s timeout
wait_for_log "$STREAM_LOG" "Click dispatched" 30 || true
# Extra buffer so the persistent log store catches up before log show
sleep 5

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

# Retrieve full log from persistent store; fall back to stream log if empty
FULL_LOG="$WORK_DIR/scroll_full.txt"
get_full_log "$SCROLL_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

assert_log "$FULL_LOG" 'createNode\(type=5\)' "createNode(type=5)"
assert_log "$FULL_LOG" "setRoot" "setRoot"
assert_log "$FULL_LOG" "Click dispatched: callbackId=0" "Click dispatched: callbackId=0"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
