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

# Tap the TextInput to focus it — use uiautomator to find coordinates
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
else
    echo "WARNING: Could not find EditText, tapping center of screen"
    "$ADB" -s "$EMULATOR_SERIAL" shell input tap 540 400
fi
# Wait for keyboard to fully settle
sleep 5

# Diagnostic: verify our app has focus and keyboard is shown
echo "Focused window:"
"$ADB" -s "$EMULATOR_SERIAL" shell dumpsys window | grep -E "mCurrentFocus|mFocusedWindow" || true
echo "Input method status:"
"$ADB" -s "$EMULATOR_SERIAL" shell dumpsys input_method | grep -E "mActive|mServedView|mInputShown" | head -5 || true

# Type "hello" character by character using keyevent.
# Individual KEYCODE_* events are more reliable than "input text"
# on CI emulators where the soft keyboard may deactivate.
echo "Typing 'hello' via individual keyevents..."
"$ADB" -s "$EMULATOR_SERIAL" shell input keyevent KEYCODE_H
sleep 1

# Diagnostic: check if first character triggered anything
echo "After 'h' - checking logcat for TextChange:"
grep -i "TextChange\|text change\|view rebuilt" "$LOGCAT_STREAM_FILE" 2>/dev/null | tail -5 || echo "(no text change logs)"

"$ADB" -s "$EMULATOR_SERIAL" shell input keyevent KEYCODE_E
sleep 1
"$ADB" -s "$EMULATOR_SERIAL" shell input keyevent KEYCODE_L
sleep 1
"$ADB" -s "$EMULATOR_SERIAL" shell input keyevent KEYCODE_L
sleep 1
"$ADB" -s "$EMULATOR_SERIAL" shell input keyevent KEYCODE_O
echo "Done typing."

# Wait for all key events to be processed and render to complete
sleep 10

# Diagnostic: dump UI to check EditText text content
POST_DUMP="$WORK_DIR/textinput_rerender_post.xml"
if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui_post.xml 2>&1 | grep -q "dumped"; then
    "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui_post.xml "$POST_DUMP" 2>/dev/null
    echo "=== Post-typing text values ==="
    grep -o 'text="[^"]*"' "$POST_DUMP" 2>/dev/null | grep -v 'text=""' | head -10 || echo "(all empty)"
    echo "=== EditText details ==="
    grep 'class="android.widget.EditText"' "$POST_DUMP" 2>/dev/null | head -3 || echo "(no EditText)"
    echo "==="
fi

# Diagnostic: focused window — is our app still foreground?
echo "Post-typing focused window:"
"$ADB" -s "$EMULATOR_SERIAL" shell dumpsys window | grep -E "mCurrentFocus|mFocusedWindow" || true

# Diagnostic: app-specific logcat lines
echo "=== App logcat lines ==="
grep -i "hatter\|jappie\|view rebuilt\|setRoot\|setStrProp\|TextChange\|text change\|onUITextChange" "$LOGCAT_STREAM_FILE" 2>/dev/null | tail -30 || echo "(no app lines)"
echo "=== End app logcat ==="

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
