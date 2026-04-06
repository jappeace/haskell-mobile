#!/usr/bin/env bash
# Android locale test: launch counter app, assert locale detection logs.
#
# haskellLogLocale is called from JNI_OnLoad, logging:
#   "Locale raw: <tag>"
#   "Locale parsed: <tag>"
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$COUNTER_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "Locale parsed:" 60 || true

LOGCAT_FILE="$WORK_DIR/locale_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

assert_logcat "$LOGCAT_FILE" "Locale raw:" "Locale raw tag logged"
assert_logcat "$LOGCAT_FILE" "Locale parsed:" "Locale parsed tag logged"

"$ADB" -s "$EMULATOR_SERIAL" shell am force-stop "$PACKAGE" 2>/dev/null || true
"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
