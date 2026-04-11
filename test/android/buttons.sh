#!/usr/bin/env bash
# Android buttons test: 5-tap sequence (+, +, -, -, -) verifying counter state transitions.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, COUNTER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$COUNTER_APK" "buttons"

LOGCAT_STREAM_FILE="$WORK_DIR/buttons_log.txt"
: > "$LOGCAT_STREAM_FILE"
"$ADB" -s "$EMULATOR_SERIAL" logcat '*:I' > "$LOGCAT_STREAM_FILE" 2>&1 &
LOGCAT_STREAM_PID=$!

# Wait for initial render
wait_for_logcat "setStrProp.*Counter: 0" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "buttons"
    echo "FATAL: Native library failed to load — aborting"
    kill "$LOGCAT_STREAM_PID" 2>/dev/null || true
    exit 1
fi
sleep 5

assert_logcat "$LOGCAT_STREAM_FILE" "setStrProp.*Counter: 0" "Counter: 0 at start"

# Tap 1: + → Counter: 1
echo "=== Tap 1: + (expect Counter: 1) ==="
tap_button "+" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 300 600
sleep 3
assert_logcat "$LOGCAT_STREAM_FILE" "setStrProp.*Counter: 1" "Counter: 1 after tap 1"

# Tap 2: + → Counter: 2
echo "=== Tap 2: + (expect Counter: 2) ==="
tap_button "+" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 300 600
sleep 3
assert_logcat "$LOGCAT_STREAM_FILE" "setStrProp.*Counter: 2" "Counter: 2 after tap 2"

# Tap 3: - → Counter: 1 again (expect ≥2 occurrences)
echo "=== Tap 3: - (expect Counter: 1 again) ==="
tap_button "-" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 700 600
sleep 3
count_1=$(grep -c 'setStrProp.*Counter: 1' "$LOGCAT_STREAM_FILE" 2>/dev/null || echo "0")
if [ "$count_1" -ge 2 ]; then
    echo "PASS: Counter: 1 seen $count_1 times (tap 3)"
else
    echo "FAIL: Counter: 1 seen $count_1 times, expected >=2 (tap 3)"
    EXIT_CODE=1
fi

# Tap 4: - → Counter: 0 again (expect ≥2 occurrences)
echo "=== Tap 4: - (expect Counter: 0 again) ==="
tap_button "-" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 700 600
sleep 3
count_0=$(grep -c 'setStrProp.*Counter: 0' "$LOGCAT_STREAM_FILE" 2>/dev/null || echo "0")
if [ "$count_0" -ge 2 ]; then
    echo "PASS: Counter: 0 seen $count_0 times (tap 4)"
else
    echo "FAIL: Counter: 0 seen $count_0 times, expected >=2 (tap 4)"
    EXIT_CODE=1
fi

# Tap 5: - → Counter: -1
echo "=== Tap 5: - (expect Counter: -1) ==="
tap_button "-" || "$ADB" -s "$EMULATOR_SERIAL" shell input tap 700 600
sleep 3
assert_logcat "$LOGCAT_STREAM_FILE" "setStrProp.*Counter: -1" "Counter: -1 after tap 5"

kill "$LOGCAT_STREAM_PID" 2>/dev/null || true
"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
