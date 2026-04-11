#!/usr/bin/env bash
# watchOS webview test: install webview app, launch, assert placeholder renders.
#
# Required env vars (set by watchos-simulator-all.nix harness):
#   SIM_UDID, BUNDLE_ID, WEBVIEW_APP, WORK_DIR, LOG_SUBSYSTEM
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$WEBVIEW_APP" "webview"
wait_for_render "webview"
sleep 5
collect_logs "webview"

# WebView node created (type=8)
assert_log "$FULL_LOG" "createNode\(type=8\)" "createNode(type=8) — WebView node created"

# URL property set (stored as text on watchOS)
assert_log "$FULL_LOG" "setStrProp.*webviewUrl.*example.com" "WebView URL set"

assert_log "$FULL_LOG" "setRoot" "setRoot"

cleanup_app

exit $EXIT_CODE
