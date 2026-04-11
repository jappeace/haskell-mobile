#!/usr/bin/env bash
# watchOS styled test: install counter app, assert setNumProp calls for fontSize + padding.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APP" "styled"

wait_for_log "$STREAM_LOG" "setNumProp" 60 || true
sleep 5

assert_log "$STREAM_LOG" "setNumProp.*fontSize" "setNumProp dispatched for fontSize"
assert_log "$STREAM_LOG" "setNumProp.*padding"  "setNumProp dispatched for padding"
assert_log "$STREAM_LOG" "setStrProp.*color"    "setStrProp dispatched for color (text color)"
assert_log "$STREAM_LOG" "setStrProp.*bgColor"  "setStrProp dispatched for bgColor (background color)"

cleanup_app

exit $EXIT_CODE
