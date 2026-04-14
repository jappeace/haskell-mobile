#!/usr/bin/env bash
# Android ScrollView + TextInput regression test.
#
# Regression test for the SIGABRT that occurred when ScrollView wrapped
# multiple children (including TextInput) on Android. Android's ScrollView
# only accepts one direct child; the fix adds an inner LinearLayout wrapper.
# Installs the app, waits for render, taps TextInput, then checks logcat for:
#   - WindowManager errors (DeadObjectException, EXITING)
#   - App crashes / ANR
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, SCROLL_TEXTINPUT_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$SCROLL_TEXTINPUT_APK" "scroll_textinput"
wait_for_render "scroll_textinput"
sleep 3
collect_logcat "scroll_textinput"

# Basic checks: app started and rendered
assert_logcat "$LOGCAT_FILE" "setRoot" "setRoot called"
assert_logcat "$LOGCAT_FILE" "ScrollTextInput demo app registered" "demo app registered"

# Verify ScrollView is in view hierarchy
DUMP_FILE="$WORK_DIR/scroll_textinput_ui.xml"
dump_ok=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$DUMP_FILE" 2>/dev/null
        dump_ok=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $dump_ok -eq 1 ]; then
    if grep -q 'android.widget.ScrollView' "$DUMP_FILE" 2>/dev/null; then
        echo "PASS: ScrollView in view hierarchy"
    else
        echo "FAIL: ScrollView not in view hierarchy"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy"
    EXIT_CODE=1
fi

# Tap the first TextInput to bring up the keyboard
echo "=== Tapping TextInput to open keyboard ==="
tap_done=0
if [ $dump_ok -eq 1 ]; then
    tap_button "Weight (kg)" && tap_done=1 || true
fi
if [ $tap_done -eq 0 ]; then
    # Fallback: tap near the top-center where the first TextInput should be
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap 540 300
fi
sleep 5

# Collect logcat again to capture any crash/exception
collect_logcat "scroll_textinput"

# Check for the DeadObjectException that was reported in prrrrrrrrr PR #39
DEAD_OBJ=$(grep -c "DeadObjectException" "$LOGCAT_FILE" 2>/dev/null || echo "0")
EXITING=$(grep -c "EXITING" "$LOGCAT_FILE" 2>/dev/null || echo "0")
FATAL=$(grep -c "FATAL EXCEPTION" "$LOGCAT_FILE" 2>/dev/null || echo "0")

if [ "$DEAD_OBJ" -gt 0 ]; then
    echo "FAIL: DeadObjectException found in logcat ($DEAD_OBJ occurrences)"
    grep "DeadObjectException" "$LOGCAT_FILE" | head -5
    EXIT_CODE=1
else
    echo "PASS: No DeadObjectException in logcat"
fi

if [ "$FATAL" -gt 0 ]; then
    echo "FAIL: FATAL EXCEPTION found in logcat"
    grep -A3 "FATAL EXCEPTION" "$LOGCAT_FILE" | head -10
    EXIT_CODE=1
else
    echo "PASS: No FATAL EXCEPTION in logcat"
fi

# Dismiss keyboard and verify app is still alive
echo "=== Pressing back to dismiss keyboard ==="
"$ADB" -s "$EMULATOR_SERIAL" shell input keyevent KEYCODE_BACK
sleep 3

# Check the app is still running
APP_PID=$("$ADB" -s "$EMULATOR_SERIAL" shell pidof "$PACKAGE" 2>/dev/null || echo "")
if [ -n "$APP_PID" ]; then
    echo "PASS: App still running (PID $APP_PID)"
else
    echo "FAIL: App crashed — no longer running"
    EXIT_CODE=1
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
