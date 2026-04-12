#!/usr/bin/env bash
# Android files directory test: install files-dir APK, launch app,
# verify the app files directory path is retrieved and file I/O works.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, FILES_DIR_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$FILES_DIR_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120 || true
sleep 5

LOGCAT_FILE="$WORK_DIR/filesdir_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true
assert_logcat "$LOGCAT_FILE" "FilesDir: " "FilesDir path retrieved"
assert_logcat "$LOGCAT_FILE" "FilesDir write-read OK" "FilesDir write-read succeeded"

# Verify no crash
LOGCAT_ERR="$WORK_DIR/filesdir_logcat_err.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:E' > "$LOGCAT_ERR" 2>&1 || true
if grep -qE "$FATAL_PATTERNS" "$LOGCAT_ERR" 2>/dev/null; then
    echo "FAIL: Fatal crash detected during files dir test"
    grep -E "$FATAL_PATTERNS" "$LOGCAT_ERR" | tail -10
    EXIT_CODE=1
else
    echo "PASS: No crash during files dir test"
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
