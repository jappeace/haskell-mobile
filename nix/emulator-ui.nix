# Android emulator UI rendering test.
#
# Boots an emulator, installs the APK, and verifies:
#   1. The counter app renders (logcat: setStrProp with "Counter: 0", setRoot, setHandler)
#   2. The view hierarchy contains expected elements (uiautomator dump)
#   3. Tapping the "+" button updates state (logcat: Click dispatched, Counter: 1)
#   4. The updated view hierarchy reflects the new state
#
# Independent from nix/emulator.nix (lifecycle test) — can run in parallel.
#
# Usage:
#   nix-build nix/emulator-ui.nix -o result-emulator-ui
#   ./result-emulator-ui/bin/test-ui
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
  name = "haskell-mobile-emulator-ui-test";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-ui << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
export ANDROID_SDK_ROOT="${sdkRoot}"
export ANDROID_HOME="${sdkRoot}"
# Prevent the emulator from finding the runner's pre-installed SDK
unset ANDROID_NDK_HOME 2>/dev/null || true
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"
AVDMANAGER="${sdk}/bin/avdmanager"
APK_PATH="${apk}/haskell-mobile.apk"
PACKAGE="me.jappie.haskellmobile"
ACTIVITY=".MainActivity"
DEVICE_NAME="test_ui"

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
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-emu-ui-XXXX)
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

# Debug: show AVD config
echo "=== AVD config.ini ==="
cat "$ANDROID_AVD_HOME/$DEVICE_NAME.avd/config.ini"
echo "=== End config.ini ==="

# Fix system image path if needed: the nix SDK may store system images
# in a different structure. Patch image.sysdir.1 to point to the actual location.
SYSIMG_DIR="$ANDROID_SDK_ROOT/system-images/android-${platformVersion}/${systemImageType}/${abiVersion}"
if [ ! -d "$SYSIMG_DIR" ]; then
    echo "WARNING: Expected system image dir not found: $SYSIMG_DIR"
    echo "Searching for system image..."
    FOUND_SYSIMG=$(find "$ANDROID_SDK_ROOT" -name "system.img" -print -quit 2>/dev/null || echo "")
    if [ -n "$FOUND_SYSIMG" ]; then
        SYSIMG_DIR=$(dirname "$FOUND_SYSIMG")
        echo "Found system image at: $SYSIMG_DIR"
        # Patch the AVD config to point to the correct location
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

# --- Clear logcat buffer ---
echo "=== Preparing logcat ==="
"$ADB" -s "emulator-$PORT" logcat -c

# --- Launch activity ---
echo "=== Launching $PACKAGE/$ACTIVITY ==="
"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY"

# --- Step 2: Wait for initial render ---
# Uses `logcat -d` (dump mode) on each iteration instead of a background
# streaming process.  This avoids stdio buffering issues: a background
# `logcat > file &` uses block-buffered stdout (~4096 bytes), so on a
# quiet emulator the log data may never reach the file.  Dump mode writes
# the full ring buffer and exits — no buffering.
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

# Extra settle time for the view hierarchy to stabilize
sleep 5

# --- Step 3: Verify initial render via logcat ---
echo ""
echo "=== Verifying initial render (logcat) ==="
EXIT_CODE=0

if grep -q 'setStrProp.*Counter: 0' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Initial render — Counter: 0 in logcat"
else
    echo "FAIL: Initial render — Counter: 0 in logcat"
    EXIT_CODE=1
fi

if grep -q 'setRoot' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Initial render — setRoot in logcat"
else
    echo "FAIL: Initial render — setRoot in logcat"
    EXIT_CODE=1
fi

if grep -q 'setHandler.*click' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Initial render — button handlers in logcat"
else
    echo "FAIL: Initial render — button handlers in logcat"
    EXIT_CODE=1
fi

# --- Step 4: Verify view hierarchy via uiautomator dump ---
echo ""
echo "=== Verifying view hierarchy (uiautomator) ==="

# uiautomator dump can be flaky, retry a few times
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
    if grep -q 'Counter: 0' "$UI_DUMP" 2>/dev/null; then
        echo "PASS: UI hierarchy — Counter: 0 visible"
    else
        echo "FAIL: UI hierarchy — Counter: 0 visible"
        EXIT_CODE=1
    fi

    if grep -q 'text="\+"' "$UI_DUMP" 2>/dev/null || grep -q 'text="+"' "$UI_DUMP" 2>/dev/null; then
        echo "PASS: UI hierarchy — + button visible"
    else
        echo "FAIL: UI hierarchy — + button visible"
        EXIT_CODE=1
    fi

    if grep -q 'text="-"' "$UI_DUMP" 2>/dev/null; then
        echo "PASS: UI hierarchy — - button visible"
    else
        echo "FAIL: UI hierarchy — - button visible"
        EXIT_CODE=1
    fi
else
    echo "FAIL: UI hierarchy — could not dump view hierarchy"
    EXIT_CODE=1
fi

# --- Step 5: Simulate "+" button tap ---
echo ""
echo "=== Tapping + button ==="

TAP_DONE=0
if [ $DUMP_OK -eq 1 ]; then
    # Extract bounds of the "+" button from uiautomator XML
    # Format: bounds="[left,top][right,bottom]"
    BOUNDS=$(grep -o 'text="[+]"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$UI_DUMP" 2>/dev/null \
          || grep -o 'text="\+"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$UI_DUMP" 2>/dev/null \
          || echo "")
    # Take only the first match — grep -o can return multiple lines
    BOUNDS=$(echo "$BOUNDS" | head -1)

    if [ -n "$BOUNDS" ]; then
        # Parse [left,top][right,bottom]
        COORDS=$(echo "$BOUNDS" | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]' | head -1)
        LEFT=$(echo "$COORDS" | sed 's/^\[//;s/,.*//')
        TOP=$(echo "$COORDS" | sed 's/^\[[0-9]*,//;s/\].*//')
        RIGHT=$(echo "$COORDS" | sed 's/.*\]\[//;s/,.*//')
        BOTTOM=$(echo "$COORDS" | sed 's/.*,//;s/\]//')

        TAP_X=$(( (LEFT + RIGHT) / 2 ))
        TAP_Y=$(( (TOP + BOTTOM) / 2 ))
        echo "Tapping + button at ($TAP_X, $TAP_Y)"
        "$ADB" -s "emulator-$PORT" shell input tap "$TAP_X" "$TAP_Y"
        TAP_DONE=1
    else
        echo "WARNING: Could not find + button bounds, trying text-based search fallback"
    fi
fi

# Fallback: try tapping via coordinates if bounds extraction failed
if [ $TAP_DONE -eq 0 ]; then
    echo "Using fallback: tapping center-right area of screen"
    # The counter app has a column layout: text on top, + and - buttons below
    "$ADB" -s "emulator-$PORT" shell input tap 300 600
    TAP_DONE=1
fi

# Wait for re-render and dump logcat
echo "Waiting for re-render..."
sleep 5
"$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

# --- Step 6: Verify re-render via logcat ---
echo ""
echo "=== Verifying re-render (logcat) ==="

if grep -q 'Click dispatched: callbackId=' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Button tap — Click dispatched in logcat"
else
    echo "FAIL: Button tap — Click dispatched in logcat"
    EXIT_CODE=1
fi

if grep -q 'setStrProp.*Counter: 1' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Re-render — Counter: 1 in logcat"
else
    echo "FAIL: Re-render — Counter: 1 in logcat"
    EXIT_CODE=1
fi

# --- Step 7: Verify updated view hierarchy ---
echo ""
echo "=== Verifying updated view hierarchy ==="

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
    if grep -q 'Counter: 1' "$UI_DUMP2" 2>/dev/null; then
        echo "PASS: UI hierarchy — Counter: 1 after tap"
    else
        echo "FAIL: UI hierarchy — Counter: 1 after tap"
        EXIT_CODE=1
    fi
else
    echo "FAIL: UI hierarchy — could not dump updated view hierarchy"
    EXIT_CODE=1
fi

# Final logcat dump (captures any events logged after last poll)
"$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

# --- Report ---
echo ""
echo "=== Filtered logcat (UIBridge) ==="
grep -i "UIBridge" "$LOGCAT_FILE" 2>/dev/null || echo "(no UIBridge lines)"
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
    echo "All UI rendering checks passed!"
else
    echo "Some UI rendering checks failed."
fi

exit $EXIT_CODE
SCRIPT

    chmod +x $out/bin/test-ui
  '';

  installPhase = "true";
}
