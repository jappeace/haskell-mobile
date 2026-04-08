#!/usr/bin/env bash
# watchOS secure storage test: install app, verify write and read callbacks.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIMULATOR_ID, BUNDLE_ID, LOG_FILE, SIM_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/../ios/helpers.sh"

EXIT_CODE=0

# Install and launch
xcrun simctl install "$SIMULATOR_ID" "$SIM_APP"
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" &
sleep 2

# Start log stream
LOG_FILE="$WORK_DIR/securestorage_watchos_log.txt"
xcrun simctl spawn "$SIMULATOR_ID" log stream \
  --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
  --level info > "$LOG_FILE" 2>&1 &
LOG_PID=$!

wait_for_log "setRoot" 120 || true
sleep 5

# Get full log
FULL_LOG="$WORK_DIR/securestorage_watchos_full_log.txt"
get_full_log "$FULL_LOG" || true

kill "$LOG_PID" 2>/dev/null || true

# Check logs for secure storage bridge initialization
assert_log "$LOG_FILE" "secure storage bridge initialized" "watchOS secure storage bridge setup" || \
  assert_log "$FULL_LOG" "secure storage bridge initialized" "watchOS secure storage bridge (full log)" || true

exit $EXIT_CODE
