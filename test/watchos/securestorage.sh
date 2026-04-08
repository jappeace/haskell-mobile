#!/usr/bin/env bash
# watchOS secure storage test: install app, auto-tap Store Token + Read Token,
# assert that the write and read callbacks fire with correct results.
#
# --autotest-buttons fires onUIEvent(0) at t+3s (Store Token) and
# onUIEvent(1) at t+7s (Read Token), exercising the Keychain round-trip.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, SECURE_STORAGE_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$SECURE_STORAGE_APP"
echo "SecureStorage app installed."

SS_START=$(date "+%Y-%m-%d %H:%M:%S")

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

# Wait for the read result (last meaningful log from the demo app)
wait_for_log "$STREAM_LOG" "SecureStorage read result" 60 || true

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

FULL_LOG="$WORK_DIR/securestorage_full.txt"
get_full_log "$SS_START" "$FULL_LOG"

# Try full log first, fall back to stream log
if ! grep -q "SecureStorage write result" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' missing callback output, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

assert_log "$FULL_LOG" "SecureStorage write result: StorageSuccess" "write callback fires with StorageSuccess"
assert_log "$FULL_LOG" "SecureStorage read result: StorageSuccess" "read callback fires with StorageSuccess"
assert_log "$FULL_LOG" "test-token-12345" "read returns written token value"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
