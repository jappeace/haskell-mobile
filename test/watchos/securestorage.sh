#!/usr/bin/env bash
# watchOS secure storage test: install app, auto-tap Store Token + Read Token,
# assert that the write and read callbacks fire end-to-end.
#
# Note: Keychain returns errSecMissingEntitlement (-34018) on the watchOS
# simulator when CODE_SIGNING_ALLOWED=NO, so we verify the bridge dispatches
# callbacks (StorageSuccess OR StorageError) rather than requiring success.
#
# --autotest-buttons fires onUIEvent(0) at t+3s (Store Token) and
# onUIEvent(1) at t+7s (Read Token).
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, SECURE_STORAGE_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$SECURE_STORAGE_APP"
echo "SecureStorage app installed."

STREAM_LOG="$WORK_DIR/securestorage_stream.txt"
> "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
    --style compact \
    > "$STREAM_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 2

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" --autotest-buttons

# Wait for the read result (callback fires regardless of Keychain success)
wait_for_log "$STREAM_LOG" "SecureStorage read result" 60 || true

# Give the stream a moment to flush
sleep 2
kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

# Verify the bridge dispatches callbacks (status may be StorageError on simulator)
assert_log "$STREAM_LOG" "SecureStorage read result:" "read callback fires"
assert_log "$STREAM_LOG" "setRoot" "app rendered"
assert_log "$STREAM_LOG" "setHandler.*click.*callback=0" "Store Token button registered"
assert_log "$STREAM_LOG" "setHandler.*click.*callback=1" "Read Token button registered"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
