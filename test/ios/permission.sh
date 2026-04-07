#!/usr/bin/env bash
# iOS permission test: install permission app, pre-grant camera, launch with
# --autotest, assert that the permission result callback fires.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, PERMISSION_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$PERMISSION_APP"
echo "Permission app installed."

# Pre-grant camera permission so the system dialog does not appear
xcrun simctl privacy "$SIM_UDID" grant camera "$BUNDLE_ID"

PERMISSION_START=$(date "+%Y-%m-%d %H:%M:%S")

STREAM_LOG="$WORK_DIR/permission_stream.txt"
> "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$BUNDLE_ID\"" \
    --style compact \
    > "$STREAM_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

# Launch with --autotest to auto-tap button 0 after 3s
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

# Wait for autotest tap + permission result
sleep 10

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

FULL_LOG="$WORK_DIR/permission_full.txt"
get_full_log "$PERMISSION_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

assert_log "$FULL_LOG" "Permission result: PermissionGranted" "permission callback fires with PermissionGranted"
assert_log "$FULL_LOG" "createNode" "createNode called (app renders)"
assert_log "$FULL_LOG" "setRoot" "setRoot"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
