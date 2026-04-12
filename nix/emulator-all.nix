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
{ sources ? import ../npins, androidArch ? "aarch64" }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  abiDir = { aarch64 = "arm64-v8a"; armv7a = "armeabi-v7a"; }.${androidArch};

  # API 34 x86_64 emulator only has arm64-v8a translation (no armeabi-v7a).
  # API 30 still has 32-bit ARM translation, needed for Wear OS armv7a APKs.
  emulatorApiLevel = { aarch64 = "34"; armv7a = "30"; }.${androidArch};

  lib = import ./lib.nix { inherit sources androidArch; };

  counterAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/CounterDemoMain.hs;
  };
  counterApk = lib.mkApk {
    sharedLibs = [{ lib = counterAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile.apk";
    name = "haskell-mobile-apk";
  };

  scrollAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/ScrollDemoMain.hs;
  };
  scrollApk = lib.mkApk {
    sharedLibs = [{ lib = scrollAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-scroll.apk";
    name = "haskell-mobile-scroll-apk";
  };

  textinputAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/TextInputDemoMain.hs;
  };
  textinputApk = lib.mkApk {
    sharedLibs = [{ lib = textinputAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-textinput.apk";
    name = "haskell-mobile-textinput-apk";
  };

  permissionAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/PermissionDemoMain.hs;
  };
  permissionApk = lib.mkApk {
    sharedLibs = [{ lib = permissionAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-permission.apk";
    name = "haskell-mobile-permission-apk";
  };

  secureStorageAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/SecureStorageDemoMain.hs;
  };
  secureStorageApk = lib.mkApk {
    sharedLibs = [{ lib = secureStorageAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-securestorage.apk";
    name = "haskell-mobile-securestorage-apk";
  };

  imageAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/ImageDemoMain.hs;
  };
  imageApk = lib.mkApk {
    sharedLibs = [{ lib = imageAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-image.apk";
    name = "haskell-mobile-image-apk";
  };

  nodepoolAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/NodePoolTestMain.hs;
    dynamicNodePool = true;
  };
  nodepoolApk = lib.mkApk {
    sharedLibs = [{ lib = nodepoolAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-nodepool.apk";
    name = "haskell-mobile-nodepool-apk";
  };

  bleAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/BleDemoMain.hs;
  };
  bleApk = lib.mkApk {
    sharedLibs = [{ lib = bleAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-ble.apk";
    name = "haskell-mobile-ble-apk";
  };

  dialogAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/DialogDemoMain.hs;
  };
  dialogApk = lib.mkApk {
    sharedLibs = [{ lib = dialogAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-dialog.apk";
    name = "haskell-mobile-dialog-apk";
  };

  locationAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/LocationDemoMain.hs;
  };
  locationApk = lib.mkApk {
    sharedLibs = [{ lib = locationAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-location.apk";
    name = "haskell-mobile-location-apk";
  };

  webviewAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/WebViewDemoMain.hs;
  };
  webviewApk = lib.mkApk {
    sharedLibs = [{ lib = webviewAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-webview.apk";
    name = "haskell-mobile-webview-apk";
  };

  authSessionAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/AuthSessionDemoMain.hs;
  };
  authSessionApk = lib.mkApk {
    sharedLibs = [{ lib = authSessionAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-authsession.apk";
    name = "haskell-mobile-authsession-apk";
  };

  cameraAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/CameraDemoMain.hs;
  };
  cameraApk = lib.mkApk {
    sharedLibs = [{ lib = cameraAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-camera.apk";
    name = "haskell-mobile-camera-apk";
  };

  bottomSheetAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/BottomSheetDemoMain.hs;
  };
  bottomSheetApk = lib.mkApk {
    sharedLibs = [{ lib = bottomSheetAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-bottomsheet.apk";
    name = "haskell-mobile-bottomsheet-apk";
  };

  httpAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/HttpDemoMain.hs;
  };
  httpApk = lib.mkApk {
    sharedLibs = [{ lib = httpAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-http.apk";
    name = "haskell-mobile-http-apk";
  };

  networkStatusAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/NetworkStatusDemoMain.hs;
  };
  networkStatusApk = lib.mkApk {
    sharedLibs = [{ lib = networkStatusAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-networkstatus.apk";
    name = "haskell-mobile-networkstatus-apk";
  };

  mapviewAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/MapViewDemoMain.hs;
  };
  mapviewApk = lib.mkApk {
    sharedLibs = [{ lib = mapviewAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-mapview.apk";
    name = "haskell-mobile-mapview-apk";
  };

  animationAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/AnimationDemoMain.hs;
  };
  animationApk = lib.mkApk {
    sharedLibs = [{ lib = animationAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-animation.apk";
    name = "haskell-mobile-animation-apk";
  };

  filesDirAndroid = import ./android.nix {
    inherit sources androidArch;
    mainModule = ../test/FilesDirDemoMain.hs;
  };
  filesDirApk = lib.mkApk {
    sharedLibs = [{ lib = filesDirAndroid; inherit abiDir; }];
    androidSrc = ../android;
    apkName = "haskell-mobile-filesdir.apk";
    name = "haskell-mobile-filesdir-apk";
  };

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ emulatorApiLevel ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis" ];
    abiVersions = [ "x86_64" ];
    cmdLineToolsVersion = "8.0";
  };

  sdk = androidComposition.androidsdk;
  sdkRoot = "${sdk}/libexec/android-sdk";

  platformVersion = emulatorApiLevel;
  systemImageType = "google_apis";
  abiVersion = "x86_64";
  imagePackage = "system-images;android-${platformVersion};${systemImageType};${abiVersion}";

  testScripts = builtins.path { path = ../test; name = "test-scripts"; };

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
TEXTINPUT_APK="${textinputApk}/haskell-mobile-textinput.apk"
PERMISSION_APK="${permissionApk}/haskell-mobile-permission.apk"
SECURE_STORAGE_APK="${secureStorageApk}/haskell-mobile-securestorage.apk"
IMAGE_APK="${imageApk}/haskell-mobile-image.apk"
NODEPOOL_APK="${nodepoolApk}/haskell-mobile-nodepool.apk"
BLE_APK="${bleApk}/haskell-mobile-ble.apk"
DIALOG_APK="${dialogApk}/haskell-mobile-dialog.apk"
LOCATION_APK="${locationApk}/haskell-mobile-location.apk"
WEBVIEW_APK="${webviewApk}/haskell-mobile-webview.apk"
AUTH_SESSION_APK="${authSessionApk}/haskell-mobile-authsession.apk"
CAMERA_APK="${cameraApk}/haskell-mobile-camera.apk"
BOTTOM_SHEET_APK="${bottomSheetApk}/haskell-mobile-bottomsheet.apk"
HTTP_APK="${httpApk}/haskell-mobile-http.apk"
NETWORK_STATUS_APK="${networkStatusApk}/haskell-mobile-networkstatus.apk"
MAPVIEW_APK="${mapviewApk}/haskell-mobile-mapview.apk"
ANIMATION_APK="${animationApk}/haskell-mobile-animation.apk"
FILES_DIR_APK="${filesDirApk}/haskell-mobile-filesdir.apk"
PACKAGE="me.jappie.haskellmobile"
ACTIVITY=".MainActivity"
DEVICE_NAME="test_all"
TEST_SCRIPTS="${testScripts}"

# --- .so size guard (see docs/ci-ram-regression-110.md) ---
# Fail fast if any test .so exceeds 120 MB.  The counter app is ~80 MB;
# anything above 120 MB indicates whole-archive bloat that will OOM the emulator.
SO_MAX_MB=120
SIZE_FAIL=0
for so_path in \
    "${counterAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${scrollAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${textinputAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${permissionAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${secureStorageAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${imageAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${nodepoolAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${bleAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${dialogAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${webviewAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${authSessionAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${cameraAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${bottomSheetAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${httpAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${networkStatusAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${mapviewAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${animationAndroid}/lib/${abiDir}/libhaskellmobile.so" \
    "${filesDirAndroid}/lib/${abiDir}/libhaskellmobile.so"; do
    SO_BYTES=$(stat -c %s "$so_path")
    SO_MB=$((SO_BYTES / 1048576))
    SO_LABEL=$(echo "$so_path" | grep -oP '[^/]+(?=/lib/)')
    if [ "$SO_MB" -gt "$SO_MAX_MB" ]; then
        echo "FAIL  $SO_LABEL .so is ''${SO_MB} MB (limit: ''${SO_MAX_MB} MB)"
        SIZE_FAIL=1
    else
        echo "OK    $SO_LABEL .so is ''${SO_MB} MB"
    fi
done
if [ "$SIZE_FAIL" -eq 1 ]; then
    echo ""
    echo "FATAL: .so size limit exceeded. This usually means boot package .a files"
    echo "ended up in the --whole-archive link group. See docs/ci-ram-regression-110.md"
    exit 1
fi
echo ""

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

EMU_PID=""
PORT=""

# Phase result tracking
PHASE1_OK=0
PHASE2_OK=0
PHASE3_OK=0
PHASE4_OK=0
PHASE5_OK=0
PHASE6_OK=0
PHASE7_OK=0
PHASE8_OK=0
PHASE9_OK=0
PHASE10_OK=0
PHASE11_OK=0
PHASE12_OK=0
PHASE13_OK=0
PHASE14_OK=0

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
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
EMULATOR_SERIAL="emulator-$PORT"

# --- Create AVD ---
echo "=== Creating AVD ==="
echo "n" | "$AVDMANAGER" create avd \
    --force \
    --name "$DEVICE_NAME" \
    --package "${imagePackage}" \
    --device "pixel_6" \
    -p "$ANDROID_AVD_HOME/$DEVICE_NAME.avd"

cat >> "$ANDROID_AVD_HOME/$DEVICE_NAME.avd/config.ini" << 'AVDCONF'
hw.ramSize = 6144
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
    -memory 6144 \
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
# PHASE 1 + PHASE 2 — Run test scripts
# ===========================================================================
export ADB EMULATOR_SERIAL COUNTER_APK SCROLL_APK TEXTINPUT_APK PERMISSION_APK SECURE_STORAGE_APK IMAGE_APK NODEPOOL_APK BLE_APK DIALOG_APK LOCATION_APK WEBVIEW_APK AUTH_SESSION_APK CAMERA_APK BOTTOM_SHEET_APK HTTP_APK NETWORK_STATUS_APK MAPVIEW_APK ANIMATION_APK FILES_DIR_APK PACKAGE ACTIVITY WORK_DIR

PHASE1_EXIT=0
PHASE2_EXIT=0
PHASE3_EXIT=0
PHASE4_EXIT=0
PHASE5_EXIT=0
PHASE6_EXIT=0
PHASE7_EXIT=0
PHASE8_EXIT=0
PHASE9_EXIT=0
PHASE10_EXIT=0
PHASE11_EXIT=0
PHASE12_EXIT=0
PHASE13_EXIT=0
PHASE14_EXIT=0

# run_with_retry LABEL COMMAND [ARGS...]
# Runs the command up to 10 times. Succeeds on first pass, fails only if all 10 fail.
# If the command outputs "FATAL:", retrying is pointless (e.g. native library failed
# to load), so we stop immediately and report the error.
run_with_retry() {
    local label="$1"; shift
    local max_attempts=10
    local attempt=1
    local output_file="$WORK_DIR/retry_''${label}.log"
    while [ $attempt -le $max_attempts ]; do
        echo "[$label] attempt $attempt/$max_attempts"
        if "$@" 2>&1 | tee "$output_file"; then
            echo "[$label] PASSED on attempt $attempt"
            return 0
        fi
        if grep -q "^FATAL:" "$output_file" 2>/dev/null; then
            echo "[$label] FATAL error detected — not retrying"
            return 1
        fi
        echo "[$label] attempt $attempt FAILED"
        attempt=$((attempt + 1))
        if [ $attempt -le $max_attempts ]; then
            echo "[$label] retrying in 5s..."
            sleep 5
        fi
    done
    echo "[$label] FAILED after $max_attempts attempts"
    return 1
}

echo ""
echo "--- lifecycle ---"
run_with_retry "lifecycle" bash "$TEST_SCRIPTS/android/lifecycle.sh" || PHASE1_EXIT=1
echo "--- ui ---"
run_with_retry "ui"        bash "$TEST_SCRIPTS/android/ui.sh"        || PHASE1_EXIT=1
echo "--- buttons ---"
run_with_retry "buttons"   bash "$TEST_SCRIPTS/android/buttons.sh"   || PHASE1_EXIT=1
echo "--- scroll ---"
run_with_retry "scroll"    bash "$TEST_SCRIPTS/android/scroll.sh"    || PHASE2_EXIT=1
echo "--- styled ---"
run_with_retry "styled"    bash "$TEST_SCRIPTS/android/styled.sh"    || PHASE1_EXIT=1
echo "--- locale ---"
run_with_retry "locale"    bash "$TEST_SCRIPTS/android/locale.sh"    || PHASE1_EXIT=1
echo "--- textinput ---"
run_with_retry "textinput" bash "$TEST_SCRIPTS/android/textinput.sh" || PHASE3_EXIT=1
echo "--- permission ---"
run_with_retry "permission" bash "$TEST_SCRIPTS/android/permission.sh" || PHASE4_EXIT=1
echo "--- securestorage ---"
run_with_retry "securestorage" bash "$TEST_SCRIPTS/android/securestorage.sh" || PHASE7_EXIT=1
echo "--- image ---"
run_with_retry "image" bash "$TEST_SCRIPTS/android/image.sh" || PHASE6_EXIT=1
echo "--- node-pool ---"
run_with_retry "node-pool" bash "$TEST_SCRIPTS/android/node-pool.sh" || PHASE5_EXIT=1
echo "--- ble ---"
run_with_retry "ble" bash "$TEST_SCRIPTS/android/ble.sh" || PHASE7_EXIT=1
echo "--- dialog ---"
run_with_retry "dialog" bash "$TEST_SCRIPTS/android/dialog.sh" || PHASE8_EXIT=1
echo "--- location ---"
run_with_retry "location" bash "$TEST_SCRIPTS/android/location.sh" || PHASE7_EXIT=1
echo "--- webview ---"
run_with_retry "webview" bash "$TEST_SCRIPTS/android/webview.sh" || PHASE9_EXIT=1
echo "--- mapview ---"
run_with_retry "mapview" bash "$TEST_SCRIPTS/android/mapview.sh" || PHASE9_EXIT=1
echo "--- authsession ---"
run_with_retry "authsession" bash "$TEST_SCRIPTS/android/authsession.sh" || PHASE10_EXIT=1
echo "--- camera ---"
run_with_retry "camera" bash "$TEST_SCRIPTS/android/camera.sh" || PHASE10_EXIT=1
echo "--- bottomsheet ---"
run_with_retry "bottomsheet" bash "$TEST_SCRIPTS/android/bottomsheet.sh" || PHASE11_EXIT=1
echo "--- http ---"
run_with_retry "http" bash "$TEST_SCRIPTS/android/http.sh" || PHASE12_EXIT=1
echo "--- networkstatus ---"
run_with_retry "networkstatus" bash "$TEST_SCRIPTS/android/network_status.sh" || PHASE7_EXIT=1
echo "--- animation ---"
run_with_retry "animation" bash "$TEST_SCRIPTS/android/animation.sh" || PHASE13_EXIT=1
echo "--- filesdir ---"
run_with_retry "filesdir" bash "$TEST_SCRIPTS/android/filesdir.sh" || PHASE14_EXIT=1

# --- Phase results ---
if [ $PHASE1_EXIT -eq 0 ]; then
    PHASE1_OK=1
    echo ""
    echo "PHASE 1 PASSED"
else
    echo ""
    echo "PHASE 1 FAILED"
fi

if [ $PHASE2_EXIT -eq 0 ]; then
    PHASE2_OK=1
    echo ""
    echo "PHASE 2 PASSED"
else
    echo ""
    echo "PHASE 2 FAILED"
fi

if [ $PHASE3_EXIT -eq 0 ]; then
    PHASE3_OK=1
    echo ""
    echo "PHASE 3 PASSED"
else
    PHASE3_OK=0
    echo ""
    echo "PHASE 3 FAILED"
fi

if [ $PHASE4_EXIT -eq 0 ]; then
    PHASE4_OK=1
    echo ""
    echo "PHASE 4 PASSED"
else
    PHASE4_OK=0
    echo ""
    echo "PHASE 4 FAILED"
fi

if [ $PHASE5_EXIT -eq 0 ]; then
    PHASE5_OK=1
    echo ""
    echo "PHASE 5 PASSED"
else
    PHASE5_OK=0
    echo ""
    echo "PHASE 5 FAILED"
fi

if [ $PHASE6_EXIT -eq 0 ]; then
    PHASE6_OK=1
    echo ""
    echo "PHASE 6 PASSED"
else
    PHASE6_OK=0
    echo ""
    echo "PHASE 6 FAILED"
fi

if [ $PHASE7_EXIT -eq 0 ]; then
    PHASE7_OK=1
    echo ""
    echo "PHASE 7 PASSED"
else
    PHASE7_OK=0
    echo ""
    echo "PHASE 7 FAILED"
fi

if [ $PHASE8_EXIT -eq 0 ]; then
    PHASE8_OK=1
    echo ""
    echo "PHASE 8 PASSED"
else
    PHASE8_OK=0
    echo ""
    echo "PHASE 8 FAILED"
fi

if [ $PHASE9_EXIT -eq 0 ]; then
    PHASE9_OK=1
    echo ""
    echo "PHASE 9 PASSED"
else
    PHASE9_OK=0
    echo ""
    echo "PHASE 9 FAILED"
fi

if [ $PHASE10_EXIT -eq 0 ]; then
    PHASE10_OK=1
    echo ""
    echo "PHASE 10 PASSED"
else
    PHASE10_OK=0
    echo ""
    echo "PHASE 10 FAILED"
fi

if [ $PHASE11_EXIT -eq 0 ]; then
    PHASE11_OK=1
    echo ""
    echo "PHASE 11 PASSED"
else
    PHASE11_OK=0
    echo ""
    echo "PHASE 11 FAILED"
fi

if [ $PHASE12_EXIT -eq 0 ]; then
    PHASE12_OK=1
    echo ""
    echo "PHASE 12 PASSED"
else
    PHASE12_OK=0
    echo ""
    echo "PHASE 12 FAILED"
fi

if [ $PHASE13_EXIT -eq 0 ]; then
    PHASE13_OK=1
    echo ""
    echo "PHASE 13 PASSED"
else
    PHASE13_OK=0
    echo ""
    echo "PHASE 13 FAILED"
fi

if [ $PHASE14_EXIT -eq 0 ]; then
    PHASE14_OK=1
    echo ""
    echo "PHASE 14 PASSED"
else
    PHASE14_OK=0
    echo ""
    echo "PHASE 14 FAILED"
fi

# ===========================================================================
# Final report
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

if [ $PHASE3_OK -eq 1 ]; then
    echo "PASS  Phase 3 — TextInput demo app"
else
    echo "FAIL  Phase 3 — TextInput demo app"
    FINAL_EXIT=1
fi

if [ $PHASE4_OK -eq 1 ]; then
    echo "PASS  Phase 4 — Permission demo app"
else
    echo "FAIL  Phase 4 — Permission demo app"
    FINAL_EXIT=1
fi

if [ $PHASE5_OK -eq 1 ]; then
    echo "PASS  Phase 5 — Node pool stress test (300 nodes, dynamic pool)"
else
    echo "FAIL  Phase 5 — Node pool stress test (300 nodes, dynamic pool)"
    FINAL_EXIT=1
fi

if [ $PHASE6_OK -eq 1 ]; then
    echo "PASS  Phase 6 — Image demo app"
else
    echo "FAIL  Phase 6 — Image demo app"
    FINAL_EXIT=1
fi

if [ $PHASE7_OK -eq 1 ]; then
    echo "PASS  Phase 7 — SecureStorage + BLE + Location demo app"
else
    echo "FAIL  Phase 7 — SecureStorage + BLE + Location demo app"
    FINAL_EXIT=1
fi

if [ $PHASE8_OK -eq 1 ]; then
    echo "PASS  Phase 8 — Dialog demo app"
else
    echo "FAIL  Phase 8 — Dialog demo app"
    FINAL_EXIT=1
fi

if [ $PHASE9_OK -eq 1 ]; then
    echo "PASS  Phase 9 — WebView demo app"
else
    echo "FAIL  Phase 9 — WebView demo app"
    FINAL_EXIT=1
fi

if [ $PHASE10_OK -eq 1 ]; then
    echo "PASS  Phase 10 — AuthSession demo app"
else
    echo "FAIL  Phase 10 — AuthSession demo app"
    FINAL_EXIT=1
fi

if [ $PHASE11_OK -eq 1 ]; then
    echo "PASS  Phase 11 — BottomSheet demo app"
else
    echo "FAIL  Phase 11 — BottomSheet demo app"
    FINAL_EXIT=1
fi

if [ $PHASE12_OK -eq 1 ]; then
    echo "PASS  Phase 12 — HTTP demo app"
else
    echo "FAIL  Phase 12 — HTTP demo app"
    FINAL_EXIT=1
fi

if [ $PHASE13_OK -eq 1 ]; then
    echo "PASS  Phase 13 — Animation demo app"
else
    echo "FAIL  Phase 13 — Animation demo app"
    FINAL_EXIT=1
fi

if [ $PHASE14_OK -eq 1 ]; then
    echo "PASS  Phase 14 — FilesDir demo app"
else
    echo "FAIL  Phase 14 — FilesDir demo app"
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
