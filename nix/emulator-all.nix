# Android emulator combined integration test.
#
# Single emulator session covering all test suites:
#
#   Phase 1 — Counter app (lifecycle + UI rendering + two-button sequence)
#     Verifies: Lifecycle events, setRoot/setStrProp/setHandler logcat,
#               uiautomator view hierarchy, + and - buttons, counter state.
#
#   Phase 2 — Scroll demo app
#     Verifies: createNode(type=5), android.widget.ScrollView in hierarchy,
#               swipe reveals Reached Bottom, tap dispatches click event.
#
# One boot + teardown cycle instead of four.
#
# Usage:
#   nix-build nix/emulator-all.nix -o result-emulator-all
#   ./result-emulator-all/bin/test-all
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  lib = import ./lib.nix { inherit sources; };

  counterApk = import ./apk.nix { inherit sources; };

  scrollAndroid = import ./android.nix {
    inherit sources;
    mainModule = ../test/ScrollDemoMain.hs;
  };
  scrollApk = lib.mkApk {
    sharedLib = scrollAndroid;
    androidSrc = ../android;
    apkName = "haskell-mobile-scroll.apk";
    name = "haskell-mobile-scroll-apk";
  };

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
  name = "haskell-mobile-emulator-all-tests";

  dontUnpack = true;

  buildPhase = ''
    mkdir -p $out/bin

    cat > $out/bin/test-all << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
export ANDROID_SDK_ROOT="${sdkRoot}"
export ANDROID_HOME="${sdkRoot}"
unset ANDROID_NDK_HOME 2>/dev/null || true
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"
AVDMANAGER="${sdk}/bin/avdmanager"
COUNTER_APK="${counterApk}/haskell-mobile.apk"
SCROLL_APK="${scrollApk}/haskell-mobile-scroll.apk"
PACKAGE="me.jappie.haskellmobile"
ACTIVITY=".MainActivity"
DEVICE_NAME="test_all"

# --- Debug: show SDK structure ---
echo "=== SDK structure ==="
echo "SDK_ROOT: $ANDROID_SDK_ROOT"
ls "$ANDROID_SDK_ROOT/" 2>/dev/null || echo "(cannot list SDK root)"
echo "--- system-images ---"
ls -R "$ANDROID_SDK_ROOT/system-images/" 2>/dev/null | head -20 || echo "(no system-images)"
echo "=== End SDK structure ==="

# --- KVM detection ---
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
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-emu-all-XXXX)
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
LOGCAT_PID=""
PORT=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
    if [ -n "$LOGCAT_PID" ] && kill -0 "$LOGCAT_PID" 2>/dev/null; then
        kill "$LOGCAT_PID" 2>/dev/null || true
    fi
    if [ -n "$EMU_PID" ] && kill -0 "$EMU_PID" 2>/dev/null; then
        echo "Killing emulator (PID $EMU_PID)"
        kill "$EMU_PID" 2>/dev/null || true
        wait "$EMU_PID" 2>/dev/null || true
    fi
    if [ -n "$PORT" ]; then
        "$ADB" -s "emulator-$PORT" emu kill 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
    echo "Cleanup done."
}
trap cleanup EXIT

# --- Find free port ---
echo "=== Finding free emulator port ==="
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

# ===========================================================================
# Helper: extract button centre from uiautomator dump and tap it
# ===========================================================================
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
        echo "WARNING: Could not dump UI hierarchy for '$BUTTON_TEXT' tap"
        return 1
    fi

    local BOUNDS=""
    if [ "$BUTTON_TEXT" = "+" ]; then
        BOUNDS=$(grep -o 'text="[+]"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$DUMP_FILE" 2>/dev/null \
              || grep -o 'text="\+"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$DUMP_FILE" 2>/dev/null \
              || echo "")
    else
        BOUNDS=$(grep -o "text=\"$BUTTON_TEXT\"[^>]*bounds=\"\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]\"" "$DUMP_FILE" 2>/dev/null \
              || echo "")
    fi

    if [ -z "$BOUNDS" ]; then
        echo "WARNING: Could not find '$BUTTON_TEXT' button bounds in UI dump"
        return 1
    fi

    local COORDS
    COORDS=$(echo "$BOUNDS" | head -1 | grep -o '\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]')
    local LEFT TOP RIGHT BOTTOM
    LEFT=$(echo "$COORDS" | sed 's/^\[//;s/,.*//')
    TOP=$(echo "$COORDS" | sed 's/^\[[0-9]*,//;s/\].*//')
    RIGHT=$(echo "$COORDS" | sed 's/.*\]\[//;s/,.*//')
    BOTTOM=$(echo "$COORDS" | sed 's/.*,//;s/\]//')

    local TAP_X TAP_Y
    TAP_X=$(( (LEFT + RIGHT) / 2 ))
    TAP_Y=$(( (TOP + BOTTOM) / 2 ))
    echo "Tapping '$BUTTON_TEXT' at ($TAP_X, $TAP_Y)"
    "$ADB" -s "emulator-$PORT" shell input tap "$TAP_X" "$TAP_Y"
    return 0
}

# ===========================================================================
# Helper: install APK with retries
# ===========================================================================
install_apk() {
    local APK_PATH="$1"
    local INSTALL_OK=0
    for attempt in 1 2 3; do
        if "$ADB" -s "emulator-$PORT" install -t "$APK_PATH" 2>&1; then
            INSTALL_OK=1
            break
        fi
        echo "Install attempt $attempt failed, retrying in 10s..."
        sleep 10
    done
    if [ $INSTALL_OK -eq 0 ]; then
        echo "ERROR: Failed to install $APK_PATH after 3 attempts"
        return 1
    fi
    echo "APK installed: $APK_PATH"
    return 0
}

# ===========================================================================
# PHASE 1 — Counter app: lifecycle + UI rendering + two-button sequence
# ===========================================================================
echo ""
echo "============================================================"
echo "PHASE 1: Counter app (lifecycle + UI + buttons)"
echo "============================================================"

PHASE1_EXIT=0

install_apk "$COUNTER_APK" || { PHASE1_EXIT=1; }

if [ $PHASE1_EXIT -eq 0 ]; then

# --- 1a: Lifecycle + initial render ---
echo ""
echo "--- Phase 1a: Lifecycle + initial render ---"

"$ADB" -s "emulator-$PORT" logcat -c
> "$LOGCAT_FILE"
"$ADB" -s "emulator-$PORT" logcat '*:I' > "$LOGCAT_FILE" 2>&1 &
LOGCAT_PID=$!
sleep 2

"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY"

# Poll for setRoot
POLL_TIMEOUT=120
POLL_ELAPSED=0
RENDER_DONE=0
while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q "setRoot" "$LOGCAT_FILE" 2>/dev/null; then
        RENDER_DONE=1
        echo "Initial render after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done
[ $RENDER_DONE -eq 0 ] && echo "WARNING: setRoot not found after ''${POLL_TIMEOUT}s"
sleep 5

# Lifecycle events
for lifecycle_event in "Lifecycle: Create" "Lifecycle: Start" "Lifecycle: Resume" "Android UI bridge initialized"; do
    if grep -q "$lifecycle_event" "$LOGCAT_FILE" 2>/dev/null; then
        echo "PASS: $lifecycle_event"
    else
        echo "FAIL: $lifecycle_event not found"
        PHASE1_EXIT=1
    fi
done

# Render checks (logcat)
if grep -q 'setStrProp.*Counter: 0' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: 0 in logcat"
else
    echo "FAIL: Counter: 0 not in logcat"
    PHASE1_EXIT=1
fi
if grep -q 'setRoot' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: setRoot in logcat"
else
    echo "FAIL: setRoot not in logcat"
    PHASE1_EXIT=1
fi
if grep -q 'setHandler.*click' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: setHandler(click) in logcat"
else
    echo "FAIL: setHandler(click) not in logcat"
    PHASE1_EXIT=1
fi

# View hierarchy
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
        echo "FAIL: UI hierarchy — Counter: 0 not visible"
        PHASE1_EXIT=1
    fi
    if grep -q 'text="\+"' "$UI_DUMP" 2>/dev/null || grep -q 'text="+"' "$UI_DUMP" 2>/dev/null; then
        echo "PASS: UI hierarchy — + button visible"
    else
        echo "FAIL: UI hierarchy — + button not visible"
        PHASE1_EXIT=1
    fi
    if grep -q 'text="-"' "$UI_DUMP" 2>/dev/null; then
        echo "PASS: UI hierarchy — - button visible"
    else
        echo "FAIL: UI hierarchy — - button not visible"
        PHASE1_EXIT=1
    fi
else
    echo "FAIL: Could not dump view hierarchy"
    PHASE1_EXIT=1
fi

# Tap + and verify Counter: 1
echo ""
echo "--- Phase 1a: Tap + button ---"
TAP_DONE=0
if [ $DUMP_OK -eq 1 ]; then
    tap_button "+" && TAP_DONE=1 || true
fi
if [ $TAP_DONE -eq 0 ]; then
    echo "Using fallback tap at (300, 600)"
    "$ADB" -s "emulator-$PORT" shell input tap 300 600
fi
sleep 5
"$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

if grep -q 'Click dispatched: callbackId=' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Click dispatched after + tap"
else
    echo "FAIL: Click dispatched not found after + tap"
    PHASE1_EXIT=1
fi
if grep -q 'setStrProp.*Counter: 1' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: 1 after + tap"
else
    echo "FAIL: Counter: 1 not found after + tap"
    PHASE1_EXIT=1
fi

DUMP2_OK=0
for attempt in 1 2 3; do
    if "$ADB" -s "emulator-$PORT" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "emulator-$PORT" pull /data/local/tmp/ui.xml "$UI_DUMP2" 2>/dev/null
        DUMP2_OK=1
        break
    fi
    sleep 5
done
if [ $DUMP2_OK -eq 1 ]; then
    if grep -q 'Counter: 1' "$UI_DUMP2" 2>/dev/null; then
        echo "PASS: UI hierarchy — Counter: 1 after tap"
    else
        echo "FAIL: UI hierarchy — Counter: 1 not seen after tap"
        PHASE1_EXIT=1
    fi
else
    echo "FAIL: Could not dump updated view hierarchy"
    PHASE1_EXIT=1
fi

# --- 1b: Two-button sequence (+, +, -, -, -) ---
echo ""
echo "--- Phase 1b: Two-button sequence ---"

# Fresh logcat + fresh app launch
kill "$LOGCAT_PID" 2>/dev/null || true
LOGCAT_PID=""
"$ADB" -s "emulator-$PORT" logcat -c
> "$LOGCAT_FILE"
"$ADB" -s "emulator-$PORT" shell am force-stop "$PACKAGE" 2>/dev/null || true
sleep 2
"$ADB" -s "emulator-$PORT" logcat '*:I' > "$LOGCAT_FILE" 2>&1 &
LOGCAT_PID=$!
sleep 2
"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY"

# Wait for initial render
POLL_TIMEOUT=120
POLL_ELAPSED=0
RENDER_DONE=0
while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if grep -q "setRoot" "$LOGCAT_FILE" 2>/dev/null; then
        RENDER_DONE=1
        echo "Counter app ready after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done
[ $RENDER_DONE -eq 0 ] && echo "WARNING: setRoot not found before button sequence"
sleep 5

if grep -q 'setStrProp.*Counter: 0' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: 0 at start of button sequence"
else
    echo "FAIL: Counter: 0 not found at start of button sequence"
    PHASE1_EXIT=1
fi

# Step 1: + → Counter: 1
echo "=== Tap 1: + (expect Counter: 1) ==="
tap_button "+" || "$ADB" -s "emulator-$PORT" shell input tap 300 600
sleep 3
if grep -q 'setStrProp.*Counter: 1' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: 1 after tap 1"
else
    echo "FAIL: Counter: 1 not found after tap 1"
    PHASE1_EXIT=1
fi

# Step 2: + → Counter: 2
echo "=== Tap 2: + (expect Counter: 2) ==="
tap_button "+" || "$ADB" -s "emulator-$PORT" shell input tap 300 600
sleep 3
if grep -q 'setStrProp.*Counter: 2' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: 2 after tap 2"
else
    echo "FAIL: Counter: 2 not found after tap 2"
    PHASE1_EXIT=1
fi

# Step 3: - → Counter: 1 (second occurrence)
echo "=== Tap 3: - (expect Counter: 1 again) ==="
tap_button "-" || "$ADB" -s "emulator-$PORT" shell input tap 700 600
sleep 3
COUNT_1=$(grep -c 'setStrProp.*Counter: 1' "$LOGCAT_FILE" 2>/dev/null || echo "0")
if [ "$COUNT_1" -ge 2 ]; then
    echo "PASS: Counter: 1 seen $COUNT_1 times (tap 3)"
else
    echo "FAIL: Counter: 1 seen $COUNT_1 times, expected >=2 (tap 3)"
    PHASE1_EXIT=1
fi

# Step 4: - → Counter: 0 (second occurrence)
echo "=== Tap 4: - (expect Counter: 0 again) ==="
tap_button "-" || "$ADB" -s "emulator-$PORT" shell input tap 700 600
sleep 3
COUNT_0=$(grep -c 'setStrProp.*Counter: 0' "$LOGCAT_FILE" 2>/dev/null || echo "0")
if [ "$COUNT_0" -ge 2 ]; then
    echo "PASS: Counter: 0 seen $COUNT_0 times (tap 4)"
else
    echo "FAIL: Counter: 0 seen $COUNT_0 times, expected >=2 (tap 4)"
    PHASE1_EXIT=1
fi

# Step 5: - → Counter: -1
echo "=== Tap 5: - (expect Counter: -1) ==="
tap_button "-" || "$ADB" -s "emulator-$PORT" shell input tap 700 600
sleep 3
if grep -q 'setStrProp.*Counter: -1' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Counter: -1 after tap 5"
else
    echo "FAIL: Counter: -1 not found after tap 5"
    PHASE1_EXIT=1
fi

# Kill logcat
kill "$LOGCAT_PID" 2>/dev/null || true
LOGCAT_PID=""

fi  # PHASE1_EXIT initial guard

# --- Phase 1 result ---
if [ $PHASE1_EXIT -eq 0 ]; then
    PHASE1_OK=1
    echo ""
    echo "PHASE 1 PASSED"
else
    echo ""
    echo "PHASE 1 FAILED"
    # Diagnostic dump
    echo "=== Filtered logcat (UIBridge) ==="
    grep -i "UIBridge\|setRoot\|setStrProp\|setHandler\|Click dispatched\|Counter:\|Lifecycle\|loadLibrary\|FATAL" \
        "$LOGCAT_FILE" 2>/dev/null | tail -50 || echo "(no relevant lines)"
fi

# --- Between phases: uninstall counter app, clear logcat ---
echo ""
echo "=== Uninstalling counter app ==="
"$ADB" -s "emulator-$PORT" uninstall "$PACKAGE" 2>/dev/null || true
"$ADB" -s "emulator-$PORT" logcat -c 2>/dev/null || true
sleep 5

# ===========================================================================
# PHASE 2 — Scroll demo app
# ===========================================================================
echo ""
echo "============================================================"
echo "PHASE 2: Scroll demo app"
echo "============================================================"

PHASE2_EXIT=0

install_apk "$SCROLL_APK" || { PHASE2_EXIT=1; }

if [ $PHASE2_EXIT -eq 0 ]; then

"$ADB" -s "emulator-$PORT" logcat -c

"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY"

# Poll for setRoot using dump mode (avoids buffering issues)
echo "=== Waiting for scroll app render (timeout: 120s) ==="
POLL_TIMEOUT=120
POLL_ELAPSED=0
RENDER_DONE=0
while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    "$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1
    if grep -q "setRoot" "$LOGCAT_FILE" 2>/dev/null; then
        RENDER_DONE=1
        echo "Scroll app rendered after ~''${POLL_ELAPSED}s"
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done
[ $RENDER_DONE -eq 0 ] && echo "WARNING: setRoot not found after ''${POLL_TIMEOUT}s"
sleep 5

# Verify 1: ScrollView node
if grep -qE 'createNode.*type=5|createNode.*5.*->' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: createNode(type=5) found in logcat"
else
    echo "FAIL: createNode(type=5) not found in logcat"
    PHASE2_EXIT=1
fi

# Verify 2: View hierarchy contains ScrollView
SCROLL_DUMP="$WORK_DIR/scroll_ui.xml"
SCROLL_DUMP_OK=0
for attempt in 1 2 3; do
    if "$ADB" -s "emulator-$PORT" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "emulator-$PORT" pull /data/local/tmp/ui.xml "$SCROLL_DUMP" 2>/dev/null
        SCROLL_DUMP_OK=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $SCROLL_DUMP_OK -eq 1 ]; then
    if grep -q 'android.widget.ScrollView' "$SCROLL_DUMP" 2>/dev/null; then
        echo "PASS: android.widget.ScrollView in view hierarchy"
    else
        echo "FAIL: android.widget.ScrollView not in view hierarchy"
        PHASE2_EXIT=1
    fi
else
    echo "FAIL: Could not dump scroll view hierarchy"
    PHASE2_EXIT=1
fi

# Verify 3: Swipe to reveal Reached Bottom
echo "=== Swipe up to reveal Reached Bottom button ==="
"$ADB" -s "emulator-$PORT" shell input swipe 540 1500 540 500
sleep 3

SCROLL_DUMP2="$WORK_DIR/scroll_ui2.xml"
SCROLL_DUMP2_OK=0
for attempt in 1 2 3; do
    if "$ADB" -s "emulator-$PORT" shell uiautomator dump /data/local/tmp/ui.xml 2>&1 | grep -q "dumped"; then
        "$ADB" -s "emulator-$PORT" pull /data/local/tmp/ui.xml "$SCROLL_DUMP2" 2>/dev/null
        SCROLL_DUMP2_OK=1
        break
    fi
    echo "  uiautomator dump attempt $attempt failed, retrying in 5s..."
    sleep 5
done

if [ $SCROLL_DUMP2_OK -eq 1 ]; then
    if grep -q 'Reached Bottom' "$SCROLL_DUMP2" 2>/dev/null; then
        echo "PASS: Reached Bottom visible after swipe"
    else
        echo "FAIL: Reached Bottom not visible after swipe"
        PHASE2_EXIT=1
    fi
else
    echo "FAIL: Could not dump view hierarchy after swipe"
    PHASE2_EXIT=1
fi

# Verify 4: Tap Reached Bottom and check click dispatch
echo "=== Tap Reached Bottom button ==="
TAP_DONE=0
if [ $SCROLL_DUMP2_OK -eq 1 ]; then
    BOUNDS=$(grep -o 'text="Reached Bottom"[^>]*bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' "$SCROLL_DUMP2" 2>/dev/null || echo "")
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
    fi
fi
if [ $TAP_DONE -eq 0 ]; then
    echo "Using fallback: tapping lower-center of screen"
    "$ADB" -s "emulator-$PORT" shell input tap 540 1400
fi

sleep 5
"$ADB" -s "emulator-$PORT" logcat -d '*:I' > "$LOGCAT_FILE" 2>&1

if grep -q 'Click dispatched: callbackId=' "$LOGCAT_FILE" 2>/dev/null; then
    echo "PASS: Click dispatched after Reached Bottom tap"
else
    echo "FAIL: Click dispatched not found after Reached Bottom tap"
    PHASE2_EXIT=1
fi

fi  # PHASE2_EXIT initial guard

# --- Phase 2 result ---
if [ $PHASE2_EXIT -eq 0 ]; then
    PHASE2_OK=1
    echo ""
    echo "PHASE 2 PASSED"
else
    echo ""
    echo "PHASE 2 FAILED"
    echo "=== Filtered logcat (UIBridge/createNode/scroll) ==="
    grep -i "UIBridge\|createNode\|setRoot\|Click dispatched\|ScrollView\|FATAL" \
        "$LOGCAT_FILE" 2>/dev/null | tail -40 || echo "(no relevant lines)"
fi

# ===========================================================================
# PHASE 3 — Final report
# ===========================================================================
echo ""
echo "============================================================"
echo "FINAL REPORT"
echo "============================================================"

FINAL_EXIT=0

if [ $PHASE1_OK -eq 1 ]; then
    echo "PASS  Phase 1 — Counter app (lifecycle + UI + buttons)"
else
    echo "FAIL  Phase 1 — Counter app (lifecycle + UI + buttons)"
    FINAL_EXIT=1
fi

if [ $PHASE2_OK -eq 1 ]; then
    echo "PASS  Phase 2 — Scroll demo app"
else
    echo "FAIL  Phase 2 — Scroll demo app"
    FINAL_EXIT=1
fi

echo ""
if [ $FINAL_EXIT -eq 0 ]; then
    echo "All combined emulator integration checks passed!"
else
    echo "Some combined emulator integration checks FAILED."
fi

exit $FINAL_EXIT
SCRIPT

    chmod +x $out/bin/test-all
  '';

  installPhase = "true";
}
