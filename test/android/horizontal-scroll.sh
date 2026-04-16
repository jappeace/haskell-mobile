#!/usr/bin/env bash
# Android horizontal scroll test: install horizontal-scroll APK, assert HorizontalScrollView
# renders, swipe left to reveal "Reached End" button, tap it.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, HORIZONTAL_SCROLL_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$HORIZONTAL_SCROLL_APK" "horizontal-scroll"
wait_for_render "horizontal-scroll"
sleep 5
collect_logcat "horizontal-scroll"

assert_logcat "$LOGCAT_FILE" "createNode.*type=10" "createNode(type=10) horizontal scroll view"

# Verify HorizontalScrollView in view hierarchy
HSCROLL_DUMP="$WORK_DIR/hscroll_ui.xml"
hscroll_dump_ok=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$HSCROLL_DUMP" 2>/dev/null
        hscroll_dump_ok=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $hscroll_dump_ok -eq 1 ]; then
    if grep -q 'android.widget.HorizontalScrollView' "$HSCROLL_DUMP" 2>/dev/null; then
        echo "PASS: android.widget.HorizontalScrollView in view hierarchy"
    else
        echo "FAIL: android.widget.HorizontalScrollView not in view hierarchy"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump horizontal scroll view hierarchy"
    EXIT_CODE=1
fi

# Swipe left multiple times to reveal Reached End button (20 items to scroll past)
echo "=== Swipe left to reveal Reached End ==="
for swipe_n in 1 2 3 4 5 6 7 8; do
    "$ADB" -s "$EMULATOR_SERIAL" shell input swipe 900 540 100 540 300
    sleep 1
done
sleep 3

HSCROLL_DUMP2="$WORK_DIR/hscroll_ui2.xml"
hscroll_dump2_ok=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$HSCROLL_DUMP2" 2>/dev/null
        hscroll_dump2_ok=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $hscroll_dump2_ok -eq 1 ]; then
    if grep -q 'Reached End' "$HSCROLL_DUMP2" 2>/dev/null; then
        echo "PASS: Reached End visible after swipe"
    else
        echo "FAIL: Reached End not visible after swipe"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy after swipe"
    EXIT_CODE=1
fi

# Tap Reached End button
echo "=== Tap Reached End ==="
tap_done=0
if [ $hscroll_dump2_ok -eq 1 ]; then
    tap_button "Reached End" && tap_done=1 || true
fi
if [ $tap_done -eq 0 ]; then
    echo "Using fallback tap at (900, 540)"
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap 900 540
fi
sleep 5

collect_logcat "horizontal-scroll"
assert_logcat "$LOGCAT_FILE" "Click dispatched" "Click dispatched after Reached End tap"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
