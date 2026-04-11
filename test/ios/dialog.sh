#!/usr/bin/env bash
# iOS dialog test: install app, auto-tap Show Alert + Show Confirm,
# assert that the callbacks fire with correct results.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, DIALOG_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$DIALOG_APP" "dialog" --autotest-buttons

# Wait for the alert result (first callback from the demo app)
wait_for_log "$STREAM_LOG" "Dialog alert result" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_ios_log "$STREAM_LOG" "dialog"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi

sleep 5
kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

assert_log "$STREAM_LOG" "Dialog alert result: DialogButton1" "alert callback fires with DialogButton1"

cleanup_app

exit $EXIT_CODE
