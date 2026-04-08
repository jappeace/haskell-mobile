#!/usr/bin/env bash
# iOS styled test: install counter app, assert setNumProp calls for fontSize, padding, and gravity.
#
# The counter app wraps its label with Styled (WidgetStyle (Just 16.0) (Just AlignCenter)),
# so rendering must trigger setNumProp for fontSize, padding, and gravity.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, COUNTER_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$COUNTER_APP"
echo "Counter app installed."

LOG_FILE="$WORK_DIR/styled_log.txt"
> "$LOG_FILE"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$BUNDLE_ID\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

wait_for_log "$LOG_FILE" "setNumProp" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_ios_log "$LOG_FILE" "styled"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

assert_log "$LOG_FILE" "setNumProp.*fontSize" "setNumProp dispatched for fontSize"
assert_log "$LOG_FILE" "setNumProp.*padding"  "setNumProp dispatched for padding"
assert_log "$LOG_FILE" "setNumProp.*gravity"  "setNumProp dispatched for gravity"
assert_log "$LOG_FILE" "setStrProp.*color"    "setStrProp dispatched for color (text color)"
assert_log "$LOG_FILE" "setStrProp.*bgColor"  "setStrProp dispatched for bgColor (background color)"

xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
kill "$LOG_STREAM_PID" 2>/dev/null || true
xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
