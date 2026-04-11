#!/usr/bin/env bash
# watchOS dialog test: install app, auto-tap Show Alert,
# assert that the callback fires with correct result.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, DIALOG_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$DIALOG_APP" "dialog" --autotest-buttons

# Wait for the alert result
wait_for_log "$STREAM_LOG" "Dialog alert result" 60 || true

sleep 2
kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

assert_log "$STREAM_LOG" "Dialog alert result: DialogButton1" "alert callback fires with DialogButton1"

cleanup_app

exit $EXIT_CODE
