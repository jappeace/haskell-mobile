#!/usr/bin/env bash
# iOS webview test: install webview app, launch, assert WebView renders and page-load fires.
#
# Required env vars (set by simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, WEBVIEW_APP, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$WEBVIEW_APP" "webview"
wait_for_render "webview"
sleep 5
collect_logs "webview"

# WebView node created (type=8)
assert_log "$FULL_LOG" "createNode\(type=8\)" "createNode(type=8) — WKWebView created"
assert_log "$FULL_LOG" "setStrProp.*webviewUrl.*example.com" "WebView URL set to example.com"
assert_log "$FULL_LOG" "setHandler.*callback=" "setHandler registered for page-load"
assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
