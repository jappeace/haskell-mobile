#!/usr/bin/env bash
# Android webview test: install webview APK, assert WebView renders and page-load fires.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, WEBVIEW_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$WEBVIEW_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "webview"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

LOGCAT_FILE="$WORK_DIR/webview_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

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
