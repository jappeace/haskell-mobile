# Android emulator ScrollView integration test.
#
# Boots an emulator, installs the APK in scroll-demo mode, and verifies:
#   1. Haskell emitted a ScrollView node (logcat: createNode type=5)
#   2. Native view hierarchy contains android.widget.ScrollView (uiautomator)
#   3. Swiping up reveals the "Reached Bottom" button (uiautomator after swipe)
#   4. Tapping the button dispatches a click event (logcat: Click dispatched)
#
# Independent from other emulator tests — can run in parallel.
#
# Usage:
#   nix-build nix/emulator-scroll.nix -o result-emulator-scroll
#   ./result-emulator-scroll/bin/test-scroll
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
  name = "haskell-mobile-emulator-scroll-test";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-scroll << 'SCRIPT'
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
DEVICE_NAME="test_scroll"

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
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-emu-scroll-XXXX)
export HOME="$WORK_DIR/home"
export ANDROID_USER_HOME="$WORK_DIR/user-home"
export ANDROID_AVD_HOME="$WORK_DIR/avd"
export ANDROID_EMULATOR_HOME="$WORK_DIR/emulator-home"
export TMPDIR="$WORK_DIR/tmp"
mkdir -p "$HOME" "$ANDROID_USER_HOME" "$ANDROID_AVD_HOME" "$ANDROID_EMULATOR_HOME" "$TMPDIR"

"$ADB" kill-server 2>/dev/null || true
"$ADB" start-server 2>/dev/null || true

LOGCAT_FILE="$WORK_DIR/logcat.txt"
UI_DUMP="$WORK_DIR/ui.xml"
UI_DUMP2="$WORK_DIR/ui2.xml"
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

# --- Clear logcat buffer ---
echo "=== Preparing logcat ==="
"$ADB" -s "emulator-$PORT" logcat -c

# --- Launch activity with scroll_demo intent extra ---
echo "=== Launching $PACKAGE/$ACTIVITY in scroll-demo mode ==="
"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY" --es test_mode scroll_demo

# --- Wait for initial render ---
echo "=== Waiting for initial render (timeout: 120s) ==="
POLL_TIMEOUT=120
POLL_ELAPSED=0
RENDER_DONE=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    "$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1
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

sleep 5

EXIT_CODE=0

# --- Verify 1: ScrollView node was created ---
echo ""
echo "=== Verify 1: ScrollView node created (logcat) ==="
if grep -qE 'createNode.*type=5|createNode.*5.*->' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: createNode(type=5) found in logcat"
else
    echo "FAIL: createNode(type=5) not found in logcat"
    EXIT_CODE=1
fi

# --- Verify 2: View hierarchy contains ScrollView ---
echo ""
echo "=== Verify 2: View hierarchy (uiautomator) ==="
DUMP_OK=0
for attempt in 1 2 3; do
    if "$ADB" -s "emulator-$PORT" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "emulator-$PORT" pull /data/local/tmp/ui.xml "$UI_DUMP" 2>/dev/null
        DUMP_OK=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $DUMP_OK -eq 1 ]; then
    if grep -q 'android.widget.ScrollView' "$UI_DUMP" 2>/dev/null; then
        echo "PASS: android.widget.ScrollView present in view hierarchy"
    else
        echo "FAIL: android.widget.ScrollView not found in view hierarchy"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy"
    EXIT_CODE=1
fi

# --- Verify 3: Swipe to reveal bottom ---
echo ""
echo "=== Verify 3: Swipe up to reveal Reached Bottom button ==="
"$ADB" -s "emulator-$PORT" shell input swipe 540 1500 540 500
sleep 3

DUMP2_OK=0
for attempt in 1 2 3; do
    if "$ADB" -s "emulator-$PORT" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "emulator-$PORT" pull /data/local/tmp/ui.xml "$UI_DUMP2" 2>/dev/null
        DUMP2_OK=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $DUMP2_OK -eq 1 ]; then
    if grep -q 'Reached Bottom' "$UI_DUMP2" 2>/dev/null; then
        echo "PASS: Reached Bottom button visible after swipe"
    else
        echo "FAIL: Reached Bottom button not visible after swipe"
        EXIT_CODE=1
    fi
else
    echo "FAIL: Could not dump view hierarchy after swipe"
    EXIT_CODE=1
fi

# --- Verify 4: Tap button and check click dispatch ---
echo ""
echo "=== Verify 4: Tap Reached Bottom button ==="
TAP_DONE=0
if [ $DUMP2_OK -eq 1 ]; then
    BOUNDS=$(grep -o 'text="Reached Bottom"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$UI_DUMP2" 2>/dev/null || echo "")
    BOUNDS=$(echo "$BOUNDS" | head -1)

    if [ -n "$BOUNDS" ]; then
        COORDS=$(echo "$BOUNDS" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' | head -1)
        LEFT=$(echo "$COORDS" | sed 's/^\[//;s/,.*//')
        TOP=$(echo "$COORDS" | sed 's/^\[[0-9]*,//;s/\].*//')
        RIGHT=$(echo "$COORDS" | sed 's/.*\]\[//;s/,.*//')
        BOTTOM=$(echo "$COORDS" | sed 's/.*,//;s/\]//')

        TAP_X=$(( (LEFT + RIGHT) / 2 ))
        TAP_Y=$(( (TOP + BOTTOM) / 2 ))
        echo "Tapping Reached Bottom at ($TAP_X, $TAP_Y)"
        "$ADB" -s "emulator-$PORT" shell input tap "$TAP_X" "$TAP_Y"
        TAP_DONE=1
    else
        echo "WARNING: Could not extract button bounds from UI dump"
    fi
fi

if [ $TAP_DONE -eq 0 ]; then
    echo "Using fallback: tapping lower-center of screen"
    "$ADB" -s "emulator-$PORT" shell input tap 540 1400
    TAP_DONE=1
fi

sleep 5
"$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

if grep -q 'Click dispatched: callbackId=' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Click dispatched in logcat"
else
    echo "FAIL: Click dispatched not found in logcat"
    EXIT_CODE=1
fi

# Final logcat dump
"$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

# --- Report ---
echo ""
echo "=== Filtered logcat (UIBridge) ==="
grep -i "UIBridge\|createNode\|setRoot\|Click dispatched" "$LOGCAT_FILE" 2>/dev/null || echo "(no UIBridge lines)"
echo "--- End filtered logcat ---"

if [ $EXIT_CODE -ne 0 ]; then
    echo ""
    echo "=== Crash / library-load messages ==="
    grep -iE "FATAL|AndroidRuntime|UnsatisfiedLinkError|System\.load|loadLibrary|haskellmobile|CRASH|SIGNAL" \
      "$LOGCAT_FILE" 2>/dev/null | tail -30 || echo "(none)"
    echo "--- End crash messages ---"
    echo ""
    echo "=== Last 40 lines of logcat ==="
    tail -40 "$LOGCAT_FILE" 2>/dev/null || echo "(empty)"
    echo "--- End logcat tail ---"
fi

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "All ScrollView integration checks passed!"
else
    echo "Some ScrollView integration checks failed."
fi

exit $EXIT_CODE
SCRIPT

    chmod +x $out/bin/test-scroll
  '';

  installPhase = "true";
}
