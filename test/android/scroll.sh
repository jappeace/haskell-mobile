#!/usr/bin/env bash
# Android scroll test: install scroll APK, assert ScrollView renders, swipe reveals button, tap it.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, SCROLL_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$SCROLL_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "scroll"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

LOGCAT_FILE="$WORK_DIR/scroll_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

assert_logcat "$LOGCAT_FILE" "createNode.*type=5" "createNode(type=5) scroll view"

# Verify ScrollView in view hierarchy
SCROLL_DUMP="$WORK_DIR/scroll_ui.xml"
scroll_dump_ok=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$SCROLL_DUMP" 2>/dev/null
        scroll_dump_ok=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $scroll_dump_ok -eq 1 ]; then
    if grep -q 'android.widget.ScrollView' "$SCROLL_DUMP" 2>/dev/null; then
        echo "PASS: android.widget.ScrollView in view hierarchy"
    else
        echo "FAIL: android.widget.ScrollView not in view hierarchy"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump scroll view hierarchy"
    EXIT_CODE=1
fi

# Swipe up to reveal Reached Bottom button
echo "=== Swipe up to reveal Reached Bottom ==="
"$ADB" -s "$EMULATOR_SERIAL" shell input swipe 540 1500 540 500
sleep 3

SCROLL_DUMP2="$WORK_DIR/scroll_ui2.xml"
scroll_dump2_ok=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$SCROLL_DUMP2" 2>/dev/null
        scroll_dump2_ok=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $scroll_dump2_ok -eq 1 ]; then
    if grep -q 'Reached Bottom' "$SCROLL_DUMP2" 2>/dev/null; then
        echo "PASS: Reached Bottom visible after swipe"
    else
        echo "FAIL: Reached Bottom not visible after swipe"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy after swipe"
    EXIT_CODE=1
fi

# Tap Reached Bottom button
echo "=== Tap Reached Bottom ==="
tap_done=0
if [ $scroll_dump2_ok -eq 1 ]; then
    tap_button "Reached Bottom" && tap_done=1 || true
fi
if [ $tap_done -eq 0 ]; then
    echo "Using fallback tap at (540, 1400)"
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap 540 1400
fi
sleep 5

"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true
assert_logcat "$LOGCAT_FILE" "Click dispatched" "Click dispatched after Reached Bottom tap"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
