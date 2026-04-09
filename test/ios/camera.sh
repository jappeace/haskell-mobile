#!/usr/bin/env bash
# iOS simulator integration test for the camera bridge.
# Installs the camera demo app, launches it, and verifies
# the app registers and renders without crash.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

# Install app
xcrun simctl install "$SIM_UDID" "$CAMERA_APP"

CAM_START=$(date "+%Y-%m-%d %H:%M:%S")

# Stream logs in background
STREAM_LOG="$WORK_DIR/camera_stream.txt"
> "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$BUNDLE_ID\"" \
    --style compact \
    > "$STREAM_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

# Launch app
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest

# Wait for render
render_done=0
wait_for_log "$STREAM_LOG" "setRoot" 60 && render_done=1 || true

# Retry if setRoot not found
if [ $render_done -eq 0 ]; then
    echo "WARNING: setRoot not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest
    wait_for_log "$STREAM_LOG" "setRoot" 60 || true
fi

sleep 10

# Stop background log streaming
kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

# Get persistent logs
FULL_LOG="$WORK_DIR/camera_full.txt"
get_full_log "$CAM_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

# Verify expected logs
assert_log "$FULL_LOG" "Camera demo app registered" "Camera demo app started"
assert_log "$FULL_LOG" "createNode" "createNode called (app renders)"
assert_log "$FULL_LOG" "setRoot" "setRoot"

# Clean up
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
