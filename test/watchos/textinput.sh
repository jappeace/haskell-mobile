#!/usr/bin/env bash
# watchOS textinput test: install textinput app, launch, assert it renders without crashing.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, TEXTINPUT_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$TEXTINPUT_APP"
echo "TextInput app installed."

TEXTINPUT_START=$(date "+%Y-%m-%d %H:%M:%S")

STREAM_LOG="$WORK_DIR/textinput_stream.txt"
> "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
    --style compact \
    > "$STREAM_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

render_done=0
wait_for_log "$STREAM_LOG" "setRoot" 60 && render_done=1 || true

if [ $render_done -eq 0 ]; then
    echo "WARNING: setRoot not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    wait_for_log "$STREAM_LOG" "setRoot" 60 || true
fi

sleep 5

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

FULL_LOG="$WORK_DIR/textinput_full.txt"
get_full_log "$TEXTINPUT_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

assert_log "$FULL_LOG" "createNode" "createNode called (app renders without crashing)"
assert_log "$FULL_LOG" "setRoot" "setRoot"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
