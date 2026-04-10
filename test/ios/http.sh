#!/usr/bin/env bash
# iOS HTTP test: install HTTP demo app, launch with --autotest-buttons,
# assert the autotest stub returns success with status 200.
#
# In autotest mode, the iOS HTTP bridge returns a stub 200 response
# without making a real network request (matching the pattern used
# by AuthSession and other bridges).
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, HTTP_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$HTTP_APP"
echo "HTTP app installed."

HTTP_START=$(date "+%Y-%m-%d %H:%M:%S")

STREAM_LOG="$WORK_DIR/http_stream.txt"
> "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$BUNDLE_ID\"" \
    --style compact \
    > "$STREAM_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest-buttons

render_done=0
wait_for_log "$STREAM_LOG" "setRoot" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_ios_log "$STREAM_LOG" "http"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
if [ $WAIT_RC -eq 0 ]; then
    render_done=1
fi

if [ $render_done -eq 0 ]; then
    echo "WARNING: setRoot not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest-buttons
    wait_for_log "$STREAM_LOG" "setRoot" 60 || true
fi

sleep 5

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

FULL_LOG="$WORK_DIR/http_full.txt"
get_full_log "$HTTP_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

assert_log "$FULL_LOG" "setRoot" "setRoot"

# Demo app registered
assert_log "$FULL_LOG" "HTTP demo app registered" "demo app registered"

# HTTP response via autotest stub
assert_log "$FULL_LOG" "HTTP response: 200" "HTTP response 200"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
