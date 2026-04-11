#!/usr/bin/env bash
# Android secure storage test: install APK, tap Store Token, tap Read Token,
# assert that the write and read callbacks fire with correct results.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, SECURE_STORAGE_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$SECURE_STORAGE_APK" "securestorage"

wait_for_logcat "setRoot" 120 || true
sleep 5

# Tap the "Store Token" button
tap_button "Store Token" || { echo "FAIL: could not tap Store Token"; EXIT_CODE=1; }
sleep 3

# Tap the "Read Token" button
tap_button "Read Token" || { echo "FAIL: could not tap Read Token"; EXIT_CODE=1; }
sleep 3

collect_logcat "securestorage"

assert_logcat "$LOGCAT_FILE" "SecureStorage write result: StorageSuccess" "write callback fires with StorageSuccess"
assert_logcat "$LOGCAT_FILE" "SecureStorage read result: StorageSuccess" "read callback fires with StorageSuccess"
assert_logcat "$LOGCAT_FILE" "test-token-12345" "read returns written token value"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
