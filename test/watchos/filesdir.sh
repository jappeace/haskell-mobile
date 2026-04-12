#!/usr/bin/env bash
# watchOS files directory test: install files-dir app, launch,
# verify app boots with files directory code present without crashing.
#
# watchOS uses desktop stub behavior (returns ".").
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, LOG_SUBSYSTEM, FILES_DIR_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$FILES_DIR_APP"
echo "FilesDir app installed."

FD_START=$(date "+%Y-%m-%d %H:%M:%S")

STREAM_LOG="$WORK_DIR/filesdir_stream.txt"
true > "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
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
    true > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest
    wait_for_log "$STREAM_LOG" "setRoot" 60 || true
fi

sleep 10

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

FULL_LOG="$WORK_DIR/filesdir_full.txt"
get_full_log "$FD_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

assert_log "$FULL_LOG" "setRoot" "setRoot"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
