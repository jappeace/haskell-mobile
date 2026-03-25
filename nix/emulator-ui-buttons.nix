# Android emulator UI two-button test.
#
# Boots an emulator, installs the APK, and verifies:
#   1. The counter app renders (logcat: Counter: 0)
#   2. Tapping "+" twice updates state (Counter: 1, Counter: 2)
#   3. Tapping "-" three times updates state (Counter: 1, Counter: 0, Counter: -1)
#
# Proves both "+" and "-" buttons are wired up and functional.
#
# Usage:
#   nix-build nix/emulator-ui-buttons.nix -o result-emulator-ui-buttons
#   ./result-emulator-ui-buttons/bin/test-ui-buttons
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  apk = import ./apk.nix { inherit sources; };

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "34" ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis_playstore" ];
    abiVersions = [ "x86_64" ];
    cmdLineToolsVersion = "8.0";
  };

  sdk = androidComposition.androidsdk;
  sdkRoot = "${sdk}/libexec/android-sdk";

  platformVersion = "34";
  systemImageType = "google_apis_playstore";
  abiVersion = "x86_64";
  imagePackage = "system-images;android-${platformVersion};${systemImageType};${abiVersion}";

in pkgs.stdenv.mkDerivation {
  name = "haskell-mobile-emulator-ui-buttons-test";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-ui-buttons << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
export ANDROID_SDK_ROOT="${sdkRoot}"
export ANDROID_HOME="${sdkRoot}"
unset ANDROID_NDK_HOME 2>/dev/null || true
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"
AVDMANAGER="${sdk}/bin/avdmanager"
APK_PATH="${apk}/haskell-mobile.apk"
PACKAGE="me.jappie.haskellmobile"
ACTIVITY=".MainActivity"
DEVICE_NAME="test_ui_buttons"

# --- Debug: show SDK structure ---
echo "=== SDK structure ==="
echo "SDK_ROOT: $ANDROID_SDK_ROOT"
ls "$ANDROID_SDK_ROOT/" 2>/dev/null || echo "(cannot list SDK root)"
echo "--- system-images ---"
ls -R "$ANDROID_SDK_ROOT/system-images/" 2>/dev/null | head -20 || echo "(no system-images)"
echo "=== End SDK structure ==="

# Detect KVM
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "KVM detected -- using hardware acceleration"
    ACCEL_FLAG=""
    BOOT_TIMEOUT=180
else
    echo "No KVM -- using software emulation (slow boot expected)"
    ACCEL_FLAG="-no-accel"
    BOOT_TIMEOUT=900
fi

# --- Temp dirs ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-emu-ui-btn-XXXX)
export HOME="$WORK_DIR/home"
export ANDROID_USER_HOME="$WORK_DIR/user-home"
export ANDROID_AVD_HOME="$WORK_DIR/avd"
export ANDROID_EMULATOR_HOME="$WORK_DIR/emulator-home"
export TMPDIR="$WORK_DIR/tmp"
mkdir -p "$HOME" "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME" "$ANDROID_EMULATOR_HOME" "$TMPDIR"

# Restart ADB server so it uses our fresh HOME for key generation.
"$ADB" kill-server 2>/dev/null || true
"$ADB" start-server 2>/dev/null || true

LOGCAT_FILE="$WORK_DIR/logcat.txt"
UI_DUMP="$WORK_DIR/ui.xml"
EMU_PID=""

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
    if [ -n "$EMU_PID" ] && kill -0 "$EMU_PID" 2>/dev/null; then
        echo "Killing emulator (PID $EMU_PID)"
        kill "$EMU_PID" 2>/dev/null || true
        wait "$EMU_PID" 2>/dev/null || true
    fi
    "$ADB" -s "emulator-$PORT" emu kill 2>/dev/null || true
    rm -rf "$WORK_DIR"
    echo "Cleanup done."
}
trap cleanup EXIT

# --- Find free port ---
echo "=== Finding free emulator port ==="
PORT=""
for p in $(seq 5554 2 5584); do
    if ! "$ADB" devices 2>/dev/null | grep -q "emulator-$p"; then
        PORT=$p
        break
    fi
done

if [ -z "$PORT" ]; then
    echo "ERROR: No free emulator port found (5554-5584 all in use)"
    exit 1
fi
echo "Using port: $PORT"
export ANDROID_SERIAL="emulator-$PORT"

# --- Create AVD ---
echo "=== Creating AVD ==="
echo "n" | "$AVDMANAGER" create avd \
    --force \
    --name "$DEVICE_NAME" \
    --package "${imagePackage}" \
    --device "pixel_6" \
    -p "$ANDROID_AVD_HOME/$DEVICE_NAME.avd"

cat >> "$ANDROID_AVD_HOME/$DEVICE_NAME.avd/config.ini" << 'AVDCONF'
hw.ramSize = 4096
hw.gpu.enabled = yes
hw.gpu.mode = swiftshader_indirect
disk.dataPartition.size = 2G
AVDCONF

# Debug: show AVD config
echo "=== AVD config.ini ==="
cat "$ANDROID_AVD_HOME/$DEVICE_NAME.avd/config.ini"
echo "=== End config.ini ==="

# Fix system image path if needed
SYSIMG_DIR="$ANDROID_SDK_ROOT/system-images/android-${platformVersion}/${systemImageType}/${abiVersion}"
if [ ! -d "$SYSIMG_DIR" ]; then
    echo "WARNING: Expected system image dir not found: $SYSIMG_DIR"
    echo "Searching for system image..."
    FOUND_SYSIMG=$(find "$ANDROID_SDK_ROOT" -name "system.img" -print -quit 2>/dev/null || echo "")
    if [ -n "$FOUND_SYSIMG" ]; then
        SYSIMG_DIR=$(dirname "$FOUND_SYSIMG")
        echo "Found system image at: $SYSIMG_DIR"
        sed -i "s|^image.sysdir.1=.*|image.sysdir.1=$SYSIMG_DIR/|" "$ANDROID_AVD_HOME/$DEVICE_NAME.avd/config.ini"
        echo "Patched image.sysdir.1 in AVD config"
    else
        echo "ERROR: Could not find system.img anywhere in SDK"
    fi
else
    echo "System image dir exists: $SYSIMG_DIR"
fi

# --- Boot emulator ---
echo "=== Booting emulator ==="
"$EMULATOR" \
    -avd "$DEVICE_NAME" \
    -no-window \
    -no-audio \
    -no-boot-anim \
    -no-metrics \
    -port "$PORT" \
    -gpu swiftshader_indirect \
    -no-snapshot \
    -memory 4096 \
    $ACCEL_FLAG \
    &
EMU_PID=$!
echo "Emulator PID: $EMU_PID"

# --- Wait for boot ---
echo "=== Waiting for boot (timeout: ''${BOOT_TIMEOUT}s) ==="
BOOT_DONE=""
ELAPSED=0
while [ $ELAPSED -lt $BOOT_TIMEOUT ]; do
    BOOT_DONE=$("$ADB" -s "emulator-$PORT" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || echo "")
    if [ "$BOOT_DONE" = "1" ]; then
        echo "Boot completed after ~''${ELAPSED}s"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    if [ $((ELAPSED % 60)) -eq 0 ]; then
        echo "  Still waiting... (''${ELAPSED}s elapsed)"
    fi
done

if [ "$BOOT_DONE" != "1" ]; then
    echo "ERROR: Emulator failed to boot within ''${BOOT_TIMEOUT}s"
    exit 1
fi

# Wait for device to settle
echo "Waiting for device to settle..."
sleep 30

# --- Install APK ---
echo "=== Installing APK ==="
INSTALL_OK=0
for attempt in 1 2 3; do
    if "$ADB" -s "emulator-$PORT" install -t "$APK_PATH" 2>&1; then
        INSTALL_OK=1
        break
    fi
    echo "Install attempt $attempt failed, retrying in 10s..."
    sleep 10
done

if [ $INSTALL_OK -eq 0 ]; then
    echo "ERROR: Failed to install APK after 3 attempts"
    exit 1
fi
echo "APK installed."

# --- Clear and capture logcat ---
echo "=== Preparing logcat ==="
"$ADB" -s "emulator-$PORT" logcat -c

"$ADB" -s "emulator-$PORT" logcat '*:I' > "$LOGCAT_FILE" 2>&1 &
LOGCAT_PID=$!
sleep 2

# --- Launch activity ---
echo "=== Launching $PACKAGE/$ACTIVITY ==="
"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY"

# --- Wait for initial render ---
echo "=== Waiting for initial render (timeout: 120s) ==="
POLL_TIMEOUT=120
POLL_ELAPSED=0
RENDER_DONE=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q "setRoot" "$LOGCAT_FILE" 2>/dev/null; then
        RENDER_DONE=1
        echo "Initial render detected after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

if [ $RENDER_DONE -eq 0 ]; then
    echo "WARNING: setRoot not found in logcat after ''${POLL_TIMEOUT}s"
fi

# Extra settle time for the view hierarchy to stabilize
sleep 5

# --- Verify initial render ---
echo ""
echo "=== Verifying initial render (logcat) ==="
EXIT_CODE=0

if grep -q 'setStrProp.*Counter: 0' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Initial render — Counter: 0 in logcat"
else
    echo "FAIL: Initial render — Counter: 0 in logcat"
    EXIT_CODE=1
fi

# --- Helper: extract button coordinates from uiautomator dump ---
# Usage: tap_button "+" or tap_button "-"
tap_button() {
    local BUTTON_TEXT="$1"
    local DUMP_FILE="$WORK_DIR/ui_tap.xml"

    local DUMP_OK=0
    for attempt in 1 2 3; do
        if "$ADB" -s "emulator-$PORT" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
            "$ADB" -s "emulator-$PORT" pull /data/local/tmp/ui.xml "$DUMP_FILE" 2>/dev/null
            DUMP_OK=1
            break
        fi
        echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
        sleep 5
    done

    if [ $DUMP_OK -eq 0 ]; then
        echo "WARNING: Could not dump UI hierarchy for $BUTTON_TEXT tap"
        return 1
    fi

    local BOUNDS=""
    if [ "$BUTTON_TEXT" = "+" ]; then
        BOUNDS=$(grep -o 'text="[+]"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$DUMP_FILE" 2>/dev/null \
              || grep -o 'text="\+"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$DUMP_FILE" 2>/dev/null \
              || echo "")
    else
        BOUNDS=$(grep -o 'text="-"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$DUMP_FILE" 2>/dev/null \
              || echo "")
    fi

    if [ -z "$BOUNDS" ]; then
        echo "WARNING: Could not find $BUTTON_TEXT button bounds"
        return 1
    fi

    local COORDS=$(echo "$BOUNDS" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]')
    local LEFT=$(echo "$COORDS" | sed 's/^\[//;s/,.*//')
    local TOP=$(echo "$COORDS" | sed 's/^\[[0-9]*,//;s/\].*//')
    local RIGHT=$(echo "$COORDS" | sed 's/.*\]\[//;s/,.*//')
    local BOTTOM=$(echo "$COORDS" | sed 's/.*,//;s/\]//')

    local TAP_X=$(( (LEFT + RIGHT) / 2 ))
    local TAP_Y=$(( (TOP + BOTTOM) / 2 ))
    echo "Tapping $BUTTON_TEXT button at ($TAP_X, $TAP_Y)"
    "$ADB" -s "emulator-$PORT" shell input tap "$TAP_X" "$TAP_Y"
    return 0
}

# --- Helper: wait for a counter value in logcat ---
# Usage: wait_for_counter "Counter: 1" 30
wait_for_counter() {
    local PATTERN="$1"
    local TIMEOUT="$2"
    local ELAPSED=0

    while [ $ELAPSED -lt $TIMEOUT ]; do
        if grep -q "setStrProp.*$PATTERN" "$LOGCAT_FILE" 2>/dev/null; then
            echo "  Detected '$PATTERN' after ~''${ELAPSED}s"
            return 0
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done
    echo "  WARNING: '$PATTERN' not found after ''${TIMEOUT}s"
    return 1
}

# --- Step 1: Tap "+" → Counter: 1 ---
echo ""
echo "=== Tap 1: + button (expect Counter: 1) ==="
tap_button "+"
sleep 3
if grep -q 'setStrProp.*Counter: 1' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: 1 after first + tap"
else
    echo "FAIL: Counter: 1 after first + tap"
    EXIT_CODE=1
fi

# --- Step 2: Tap "+" → Counter: 2 ---
echo ""
echo "=== Tap 2: + button (expect Counter: 2) ==="
tap_button "+"
sleep 3
if grep -q 'setStrProp.*Counter: 2' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: 2 after second + tap"
else
    echo "FAIL: Counter: 2 after second + tap"
    EXIT_CODE=1
fi

# --- Step 3: Tap "-" → Counter: 1 ---
echo ""
echo "=== Tap 3: - button (expect Counter: 1 again) ==="
tap_button "-"
sleep 3
# Counter: 1 already appeared from step 1, so count occurrences
COUNT_1=$(grep -c 'setStrProp.*Counter: 1' "$LOGCAT_FILE" 2>/dev/null || echo "0")
if [ "$COUNT_1" -ge 2 ]; then
    echo "PASS: Counter: 1 after first - tap (seen $COUNT_1 times)"
else
    echo "FAIL: Counter: 1 after first - tap (seen $COUNT_1 times, expected >=2)"
    EXIT_CODE=1
fi

# --- Step 4: Tap "-" → Counter: 0 ---
echo ""
echo "=== Tap 4: - button (expect Counter: 0 again) ==="
tap_button "-"
sleep 3
COUNT_0=$(grep -c 'setStrProp.*Counter: 0' "$LOGCAT_FILE" 2>/dev/null || echo "0")
if [ "$COUNT_0" -ge 2 ]; then
    echo "PASS: Counter: 0 after second - tap (seen $COUNT_0 times)"
else
    echo "FAIL: Counter: 0 after second - tap (seen $COUNT_0 times, expected >=2)"
    EXIT_CODE=1
fi

# --- Step 5: Tap "-" → Counter: -1 ---
echo ""
echo "=== Tap 5: - button (expect Counter: -1) ==="
tap_button "-"
sleep 3
if grep -q 'setStrProp.*Counter: -1' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: -1 after third - tap"
else
    echo "FAIL: Counter: -1 after third - tap"
    EXIT_CODE=1
fi

# Kill logcat capture
kill "$LOGCAT_PID" 2>/dev/null || true

# --- Report ---
echo ""
echo "=== Filtered logcat (UIBridge) ==="
grep -i "UIBridge" "$LOGCAT_FILE" 2>/dev/null || echo "(no UIBridge lines)"
echo "--- End filtered logcat ---"

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "All two-button UI checks passed!"
else
    echo "Some two-button UI checks failed."
fi

exit $EXIT_CODE
SCRIPT

    chmod +x $out/bin/test-ui-buttons
  '';

  installPhase = "true";
}
