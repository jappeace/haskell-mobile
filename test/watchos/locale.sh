#!/usr/bin/env bash
# watchOS locale test: launch counter app, assert locale detection logs.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$COUNTER_APP"
echo "Counter app installed."

LOG_FILE="$WORK_DIR/locale_log.txt"
> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

wait_for_log "$LOG_FILE" "Locale parsed:" 60 || true

assert_log "$LOG_FILE" "Locale raw:" "Locale raw tag logged"
assert_log "$LOG_FILE" "Locale parsed:" "Locale parsed tag logged"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
kill "$LOG_STREAM_PID" 2>/dev/null || true
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
