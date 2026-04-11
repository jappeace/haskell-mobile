#!/usr/bin/env bash
# Android textinput test: install textinput APK, assert InputType is applied via setNumProp.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, TEXTINPUT_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

start_app "$TEXTINPUT_APK" "textinput"
wait_for_render "textinput"
sleep 5
collect_logcat "textinput"

assert_logcat "$LOGCAT_FILE" "createNode.*type=4" "createNode(type=4) TextInput node"
assert_logcat "$LOGCAT_FILE" "setNumProp.*inputType=1.*android=8194" "setNumProp InputNumber -> TYPE_CLASS_NUMBER|DECIMAL"

# Verify EditText in view hierarchy
TEXTINPUT_DUMP="$WORK_DIR/textinput_ui.xml"
dump_ok=0
for attempt in 1 2 3; do
    if "$ADB" -s "$EMULATOR_SERIAL" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "$EMULATOR_SERIAL" pull /data/local/tmp/ui.xml "$TEXTINPUT_DUMP" 2>/dev/null
        dump_ok=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $dump_ok -eq 1 ]; then
    if grep -q 'android.widget.EditText' "$TEXTINPUT_DUMP" 2>/dev/null; then
        echo "PASS: android.widget.EditText in view hierarchy"
    else
        echo "FAIL: android.widget.EditText not in view hierarchy"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump textinput view hierarchy"
    EXIT_CODE=1
fi

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
