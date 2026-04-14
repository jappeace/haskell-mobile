#!/usr/bin/env bash
# Android textinput_rerender test: verify that typing in a TextInput
# triggers a re-render so that a dependent Text widget updates.
#
# Reproduces jappeace/prrrrrrrrr#47.
#
# The demo app has a TextInput + a Text showing "Typed: <value>".
# After typing text via adb, the logcat should show setStrProp
# updating the Text to "Typed: hello".
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, TEXTINPUT_RERENDER_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$TEXTINPUT_RERENDER_APK" "textinput-rerender"

LOGCAT_STREAM_FILE="$WORK_DIR/textinput_rerender_log.txt"
: > "$LOGCAT_STREAM_FILE"
"$ADB" -s "$EMULATOR_SERIAL" logcat '*:I' > "$LOGCAT_STREAM_FILE" 2>&1 &
LOGCAT_STREAM_PID=$!

# Wait for initial render
wait_for_logcat "setRoot" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "textinput-rerender"
    echo "FATAL: Native library failed to load — aborting"
    kill "$LOGCAT_STREAM_PID" 2>/dev/null || true
    exit 1
fi
sleep 5

# Verify initial state: "Typed: " (empty)
assert_logcat "$LOGCAT_STREAM_FILE" 'view rebuilt: Typed:' "Initial render shows empty Typed label"

# Tap the TextInput to focus it
TAP_DUMP="$WORK_DIR/textinput_rerender_ui.xml"
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$TAP_DUMP" 2>/dev/null
        break
    fi
    sleep 3
done

# Find and tap the EditText
EDIT_BOUNDS=$(grep -o 'class="android.widget.EditText"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$TAP_DUMP" 2>/dev/null | head -1 || echo "")
if [ -n "$EDIT_BOUNDS" ]; then
    COORDS=$(echo "$EDIT_BOUNDS" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]')
    LEFT=$(echo "$COORDS" | sed 's/^\[//;s/,.*//')
    TOP=$(echo "$COORDS" | sed 's/^\[[0-9]*,//;s/\].*//')
    RIGHT=$(echo "$COORDS" | sed 's/.*\]\[//;s/,.*//')
    BOTTOM=$(echo "$COORDS" | sed 's/.*,//;s/\]//')
    TAP_X=$(( (LEFT + RIGHT) / 2 ))
    TAP_Y=$(( (TOP + BOTTOM) / 2 ))
    echo "Tapping EditText at ($TAP_X, $TAP_Y)"
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap "$TAP_X" "$TAP_Y"
    sleep 2
else
    echo "WARNING: Could not find EditText, tapping center of screen"
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap 540 400
    sleep 2
fi

# Type "hello" via adb
"$ADB" -s "$EMULATOR_SERIAL" shell input text "hello"
sleep 3

# The key assertion: after typing, the view function should have been
# called with the updated state, producing a logcat line like:
#   view rebuilt: Typed: hello
# AND a setStrProp call updating the Text widget:
#   setStrProp(..., value="Typed: hello")
#
# On master (broken): neither of these appear because OnChange
# does not trigger renderView.
assert_logcat "$LOGCAT_STREAM_FILE" 'view rebuilt: Typed: hello' "View rebuilt with typed text after OnChange"
assert_logcat "$LOGCAT_STREAM_FILE" 'setStrProp.*Typed: hello' "Text widget updated to show typed text"

kill "$LOGCAT_STREAM_PID" 2>/dev/null || true
"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
