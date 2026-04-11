#!/usr/bin/env bash
# Android webview test: install webview APK, assert WebView renders and page-load fires.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, WEBVIEW_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$WEBVIEW_APK" "webview"
wait_for_render "webview"
sleep 5
collect_logcat "webview"

# WebView node created (type=8)
assert_logcat "$LOGCAT_FILE" "createNode.*type=8" "createNode(type=8) WebView node"

# URL property set
assert_logcat "$LOGCAT_FILE" "setStrProp.*webviewUrl.*example.com" "WebView URL set to example.com"

# Page-load callback registered
assert_logcat "$LOGCAT_FILE" "setHandler.*callback=" "setHandler registered for page-load"

# setRoot called
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
