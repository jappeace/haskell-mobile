#!/usr/bin/env bash
# iOS webview test: install webview app, launch, assert WebView renders and page-load fires.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, WEBVIEW_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

xcrun simctl install "$SIM_UDID" "$WEBVIEW_APP"
echo "WebView app installed."

WEBVIEW_START=$(date "+%Y-%m-%d %H:%M:%S")

STREAM_LOG="$WORK_DIR/webview_stream.txt"
> "$STREAM_LOG"
xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"$BUNDLE_ID\"" \
    --style compact \
    > "$STREAM_LOG" 2>&1 &
LOG_STREAM_PID=$!
sleep 5

xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

render_done=0
wait_for_log "$STREAM_LOG" "setRoot" 60
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_ios_log "$STREAM_LOG" "webview"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
if [ $WAIT_RC -eq 0 ]; then
    render_done=1
fi

if [ $render_done -eq 0 ]; then
    echo "WARNING: setRoot not found — retrying with relaunch"
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$STREAM_LOG"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"
    wait_for_log "$STREAM_LOG" "setRoot" 60 || true
fi

sleep 5

kill "$LOG_STREAM_PID" 2>/dev/null || true
sleep 1

FULL_LOG="$WORK_DIR/webview_full.txt"
get_full_log "$WEBVIEW_START" "$FULL_LOG"

if ! grep -q "setRoot" "$FULL_LOG" 2>/dev/null; then
    echo "  'log show' empty/incomplete, using stream log"
    FULL_LOG="$STREAM_LOG"
fi

# WebView node created (type=8)
assert_log "$FULL_LOG" "createNode\(type=8\)" "createNode(type=8) — WKWebView created"

# URL property set
assert_log "$FULL_LOG" "setStrProp.*webviewUrl.*example.com" "WebView URL set to example.com"

# Page-load callback registered
assert_log "$FULL_LOG" "setHandler.*callback=" "setHandler registered for page-load"

assert_log "$FULL_LOG" "setRoot" "setRoot"

xcrun simctl uninstall "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

exit $EXIT_CODE
