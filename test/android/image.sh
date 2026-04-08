#!/usr/bin/env bash
# Android image test: install image APK, assert all 3 ImageSource paths are exercised.
#
# Required env vars (set by emulator-all.nix harness):
#   ADB, EMULATOR_SERIAL, IMAGE_APK, PACKAGE, ACTIVITY, WORK_DIR
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

EXIT_CODE=0

install_apk "$IMAGE_APK" || { echo "FAIL: install_apk"; exit 1; }

"$ADB" -s "$EMULATOR_SERIAL" logcat -c
"$ADB" -s "$EMULATOR_SERIAL" shell am start -n "$PACKAGE/$ACTIVITY"

wait_for_logcat "setRoot" 120
WAIT_RC=$?
if [ $WAIT_RC -eq 2 ]; then
    dump_logcat "image"
    echo "FATAL: Native library failed to load — aborting"
    exit 1
fi
sleep 5

LOGCAT_FILE="$WORK_DIR/image_logcat.txt"
"$ADB" -s "$EMULATOR_SERIAL" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1 || true

# All 3 Image nodes created (type=6)
assert_logcat "$LOGCAT_FILE" "createNode.*type=6" "createNode(type=6) Image node"

# Test case 1: ImageResource — setStrProp with imageResource
assert_logcat "$LOGCAT_FILE" "setStrProp.*imageResource.*ic_launcher" "ImageResource: setStrProp with resource name"

# Test case 2: ImageData — setImageData called
assert_logcat "$LOGCAT_FILE" "setImageData.*node=.*bytes" "ImageData: setImageData called"

# Test case 3: ImageFile — setStrProp with imageFile
assert_logcat "$LOGCAT_FILE" "setStrProp.*imageFile.*/nonexistent/test.png" "ImageFile: setStrProp with file path"

# ScaleType set on image nodes
assert_logcat "$LOGCAT_FILE" "setNumProp.*scaleType" "ScaleType: setNumProp called"

"$ADB" -s "$EMULATOR_SERIAL" uninstall "$PACKAGE" 2>/dev/null || true

exit $EXIT_CODE
