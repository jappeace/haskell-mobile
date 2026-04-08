#!/usr/bin/env bash
# watchOS image test: install image app, launch, assert all 3 ImageSource paths are exercised.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, IMAGE_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$IMAGE_APP"
echo "Image app installed."

IMAGE_START=$(date "+%Y-%m-%d %H:%M:%S")

STREAM_LOG="$WORK_DIR/image_stream.txt"
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

FULL_LOG="$WORK_DIR/image_full.txt"
get_full_log "$IMAGE_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

# All 3 Image nodes created (type=6)
assert_log "$FULL_LOG" "createNode\(type=6\)" "createNode(type=6) — Image node created"

# Test case 1: ImageResource
assert_log "$FULL_LOG" "setStrProp.*imageResource.*ic_launcher" "ImageResource path set"

# Test case 2: ImageData
assert_log "$FULL_LOG" "setImageData" "ImageData called"

# Test case 3: ImageFile
assert_log "$FULL_LOG" "setStrProp.*imageFile.*/nonexistent" "ImageFile path set"

assert_log "$FULL_LOG" "setRoot" "setRoot"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
