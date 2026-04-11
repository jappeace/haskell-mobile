#!/usr/bin/env bash
# watchOS bottom sheet test: install app, auto-tap Show Actions,
# assert that the callback fires with correct result.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, BOTTOM_SHEET_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$BOTTOM_SHEET_APP" "bottomsheet" --autotest-buttons

# Wait for the bottom sheet result
wait_for_log "$STREAM_LOG" "BottomSheet result" 60 || true

sleep 2
kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

assert_log "$STREAM_LOG" "BottomSheet result: BottomSheetItemSelected 0" "bottom sheet callback fires with BottomSheetItemSelected 0"

cleanup_app

exit $EXIT_CODE
