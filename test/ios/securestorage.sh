#!/usr/bin/env bash
# iOS secure storage test: install app, auto-tap Store Token + Read Token,
# assert that the write and read callbacks fire with correct results.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, SECURE_STORAGE_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$SECURE_STORAGE_APP" "securestorage" --autotest-buttons

# Wait for the read result (last meaningful log from the demo app)
wait_for_log "$STREAM_LOG" "SecureStorage read result" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_ios_log "$STREAM_LOG" "securestorage"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi

sleep 2
kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

assert_log "$STREAM_LOG" "SecureStorage write result: StorageSuccess" "write callback fires with StorageSuccess"
assert_log "$STREAM_LOG" "SecureStorage read result: StorageSuccess" "read callback fires with StorageSuccess"
assert_log "$STREAM_LOG" "test-token-12345" "read returns written token value"

cleanup_app

exit $EXIT_CODE
