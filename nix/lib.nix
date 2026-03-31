# Reusable builder functions for haskell-mobile based projects.
#
# Returns an attrset of 6 builder functions:
#   mkAndroidLib  — cross-compile Haskell to .so for aarch64-android
#   mkApk         — package .so + Java + resources into signed APK
#   mkEmulatorTest — Android emulator lifecycle test script
#   mkIOSLib      — compile Haskell to .a for iOS (device or simulator)
#   mkSimulatorApp — stage iOS sources + pre-built library for xcodebuild
#   mkSimulatorTest — iOS Simulator lifecycle test script
#
# Usage:
#   let lib = import ./lib.nix { sources = import ../npins; };
#   in lib.mkAndroidLib { haskellMobileSrc = ../.; mainModule = ../app/MobileMain.hs; }
{ sources }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  # --- Android cross-compilation infrastructure ---
  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;
  ghc = androidPkgs.haskellPackages.ghc;
  ghcCmd = "${ghc}/bin/${ghc.targetPrefix}ghc";
  ghcPkgDir = "${ghc}/lib/${ghc.targetPrefix}ghc-${ghc.version}/lib/aarch64-linux-ghc-${ghc.version}";

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
  };
  ndk = "${androidComposition.ndk-bundle}/libexec/android-sdk/ndk/${androidComposition.ndk-bundle.version}";
  ndkCc = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang";
  sysroot = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64/sysroot";

  # --- APK toolchain ---
  apkComposition = pkgs.androidenv.composeAndroidPackages {
    buildToolsVersions = [ "34.0.0" ];
    platformVersions = [ "34" ];
    includeNDK = false;
  };
  androidSdk = apkComposition.androidsdk;
  buildTools = "${androidSdk}/libexec/android-sdk/build-tools/34.0.0";
  platform = "${androidSdk}/libexec/android-sdk/platforms/android-34";

  # --- Emulator infrastructure ---
  emulatorComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "34" ];
    includeEmulator = true;
    includeSystemImages = true;
    systemImageTypes = [ "google_apis_playstore" ];
    abiVersions = [ "x86_64" ];
    cmdLineToolsVersion = "8.0";
  };
  emulatorSdk = emulatorComposition.androidsdk;
  emulatorSdkRoot = "${emulatorSdk}/libexec/android-sdk";

in {

  # ---------------------------------------------------------------------------
  # mkAndroidLib: Cross-compile Haskell to shared .so for aarch64-android
  # ---------------------------------------------------------------------------
  mkAndroidLib =
    { haskellMobileSrc
    , mainModule
    , pname ? "haskell-mobile-android"
    , soName ? "libhaskellmobile.so"
    , javaPackageName ? "me.jappie.haskellmobile"
    , extraJniBridge ? []
    , extraNdkCompile ? (_: _: "")
    , extraModuleCopy ? ""
    , extraLinkObjects ? []
    , extraGhcIncludeDirs ? []
    }:
    let
      jniPackageMacro = builtins.replaceStrings ["."] ["_"] javaPackageName;
    in
    pkgs.stdenv.mkDerivation {
      inherit pname;
      version = "0.1.0.0";

      src = haskellMobileSrc + "/src";

      nativeBuildInputs = [ ghc ];
      buildInputs = [ androidPkgs.libffi androidPkgs.gmp ];

      buildPhase = ''
        # Discover RTS include path for HsFFI.h
        GHC_LIBDIR=$(${ghcCmd} --print-libdir)
        RTS_INCLUDE=$(dirname $(find $GHC_LIBDIR -name "HsFFI.h" | head -1))

        echo "GHC: ${ghcCmd}"
        echo "GHC libdir: $GHC_LIBDIR"
        echo "RTS include: $RTS_INCLUDE"

        # Step 1: Compile JNI bridge and Android UI bridge with NDK clang
        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=${jniPackageMacro} \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${haskellMobileSrc}/include \
          -o jni_bridge.o \
          ${haskellMobileSrc}/cbits/jni_bridge.c

        ${ndkCc} -c -fPIC \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${haskellMobileSrc}/include \
          -o ui_bridge_android.o \
          ${haskellMobileSrc}/cbits/ui_bridge_android.c

        # Compile extra JNI bridge sources (consumer-specific JNI methods)
        ${builtins.concatStringsSep "\n" (builtins.genList (i:
          let src = builtins.elemAt extraJniBridge i;
              base = builtins.replaceStrings ["/"] ["_"] (builtins.baseNameOf src);
              oName = "extra_jni_${toString i}.o";
          in ''
        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=${jniPackageMacro} \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${haskellMobileSrc}/include \
          -o ${oName} \
          ${src}
          '') (builtins.length extraJniBridge))}

        # Extra NDK compilation (e.g. SQLite, storage helpers)
        ${extraNdkCompile ndkCc sysroot}

        # Step 2: Copy source modules into writable build directory.
        # GHC writes _stub.h files next to sources, so they can't live in
        # the read-only nix store.
        mkdir -p HaskellMobile
        cp ${haskellMobileSrc}/src/HaskellMobile/Types.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Lifecycle.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Widget.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/UIBridge.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Render.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile.hs .

        # Default App.hs — only copy if not already present (consumer may override)
        if [ ! -f HaskellMobile/App.hs ]; then
          cp ${haskellMobileSrc}/src/HaskellMobile/App.hs HaskellMobile/
        fi

        # Extra module copies (consumer overrides, additional modules)
        ${extraModuleCopy}

        # Copy user entry point (plain main :: IO (), no foreign export needed)
        cp ${mainModule} Main.hs

        # Step 3: Copy C sources that GHC compiles into writable build dir.
        # GHC writes .o.tmp files next to C sources; nix store is read-only.
        mkdir -p cbits
        cp ${haskellMobileSrc}/cbits/android_stubs.c cbits/
        cp ${haskellMobileSrc}/cbits/platform_log.c cbits/
        cp ${haskellMobileSrc}/cbits/numa_stubs.c cbits/
        cp ${haskellMobileSrc}/cbits/ui_bridge.c cbits/
        cp ${haskellMobileSrc}/cbits/run_main.c cbits/

        # Step 4: Compile Haskell to shared library with cross-GHC.
        # Discover library paths dynamically — hash suffixes vary across nixpkgs.
        GHC_PKG_DIR="${ghcPkgDir}"

        find_lib() {
          local result
          # Exclude debug (_debug), profiling (_p), threaded (_thr) variants
          # and GHC shared library stubs (*-ghc*).
          result=$(find "$GHC_PKG_DIR" -name "libHS$1-*.a" \
            ! -name '*_debug*' ! -name '*_p.a' ! -name '*_thr*' \
            ! -name '*-ghc*' | head -1)
          if [ -z "$result" ]; then
            echo "ERROR: Could not find library: $1" >&2
            exit 1
          fi
          echo "$result"
        }

        RTS_LIB=$(find_lib "rts")
        GHC_PRIM_LIB=$(find_lib "ghc-prim")
        GHC_BIGNUM_LIB=$(find_lib "ghc-bignum")
        GHC_INTERNAL_LIB=$(find_lib "ghc-internal")
        BASE_LIB=$(find_lib "base")
        INTEGER_GMP_LIB=$(find_lib "integer-gmp")
        TEXT_LIB=$(find_lib "text")
        ARRAY_LIB=$(find_lib "array")
        DEEPSEQ_LIB=$(find_lib "deepseq")
        CONTAINERS_LIB=$(find_lib "containers")

        echo "Libraries discovered:"
        echo "  rts: $RTS_LIB"
        echo "  ghc-prim: $GHC_PRIM_LIB"
        echo "  base: $BASE_LIB"
        echo "  containers: $CONTAINERS_LIB"

        ${ghcCmd} -shared -O2 \
          -o ${soName} \
          -I${haskellMobileSrc}/include \
          ${builtins.concatStringsSep " " (map (d: "-I${d}") extraGhcIncludeDirs)} \
          Main.hs \
          HaskellMobile.hs \
          cbits/android_stubs.c \
          cbits/platform_log.c \
          cbits/numa_stubs.c \
          cbits/ui_bridge.c \
          cbits/run_main.c \
          -optl-L${androidPkgs.gmp}/lib \
          -optl-L${androidPkgs.libffi}/lib \
          -optl-lffi \
          -optl-llog \
          -optl-Wl,-z,max-page-size=16384 \
          -optl$(pwd)/jni_bridge.o \
          -optl$(pwd)/ui_bridge_android.o \
          ${builtins.concatStringsSep " " (builtins.genList (i: "-optl$(pwd)/extra_jni_${toString i}.o") (builtins.length extraJniBridge))} \
          ${builtins.concatStringsSep " " (map (o: "-optl${o}") extraLinkObjects)} \
          -optl-Wl,-u,haskellRunMain \
          -optl-Wl,-u,haskellGreet \
          -optl-Wl,-u,haskellOnLifecycle \
          -optl-Wl,-u,haskellCreateContext \
          -optl-Wl,-u,haskellRenderUI \
          -optl-Wl,-u,haskellOnUIEvent \
          -optl-Wl,-u,haskellOnUITextChange \
          -optl-Wl,--whole-archive \
          -optl$RTS_LIB \
          -optl$GHC_PRIM_LIB \
          -optl$GHC_BIGNUM_LIB \
          -optl$GHC_INTERNAL_LIB \
          -optl$BASE_LIB \
          -optl$INTEGER_GMP_LIB \
          -optl$TEXT_LIB \
          -optl$ARRAY_LIB \
          -optl$DEEPSEQ_LIB \
          -optl$CONTAINERS_LIB \
          -optl-Wl,--no-whole-archive
      '';

      installPhase = ''
        mkdir -p $out/lib/arm64-v8a
        cp ${soName} $out/lib/arm64-v8a/

        # Bundle runtime dependencies (not provided by Android)
        cp ${androidPkgs.gmp}/lib/libgmp.so $out/lib/arm64-v8a/
        cp ${androidPkgs.libffi}/lib/libffi.so $out/lib/arm64-v8a/
      '';
    };

  # ---------------------------------------------------------------------------
  # mkApk: Package shared library + Java + resources into a signed APK
  # ---------------------------------------------------------------------------
  mkApk =
    { sharedLib
    , androidSrc
    , apkName ? "app.apk"
    , name ? "app-apk"
    }:
    pkgs.stdenv.mkDerivation {
      inherit name;

      src = androidSrc;

      nativeBuildInputs = with pkgs; [
        jdk17_headless
        zip
        unzip
      ];

      buildPhase = ''
        export HOME=$TMPDIR

        echo "=== Step 1: Compile resources with aapt2 ==="
        mkdir -p compiled_res
        ${buildTools}/aapt2 compile \
          --dir res \
          -o compiled_res/

        echo "=== Step 2: Link resources with aapt2 ==="
        mkdir -p gen
        ${buildTools}/aapt2 link \
          -I ${platform}/android.jar \
          --manifest AndroidManifest.xml \
          --java gen \
          -o base.apk \
          compiled_res/*.flat

        echo "=== Step 3: Compile Java sources ==="
        mkdir -p classes
        find gen -name "*.java" -print

        javac \
          -source 11 -target 11 \
          -classpath ${platform}/android.jar \
          -d classes \
          $(find gen -name '*.java') \
          $(find java -name '*.java')

        echo "=== Step 4: Convert to DEX ==="
        mkdir -p dex_out
        ${buildTools}/d8 \
          --min-api 26 \
          --output dex_out \
          $(find classes -name "*.class")

        echo "=== Step 5: Build APK ==="
        cp base.apk unsigned.apk
        cd dex_out
        zip -j ../unsigned.apk classes.dex
        cd ..
        mkdir -p lib/arm64-v8a
        cp ${sharedLib}/lib/arm64-v8a/*.so lib/arm64-v8a/
        zip -r unsigned.apk lib/

        echo "=== Step 6: Zipalign ==="
        ${buildTools}/zipalign -f 4 unsigned.apk aligned.apk

        echo "=== Step 7: Sign APK ==="
        keytool -genkeypair \
          -keystore debug.keystore \
          -storepass android \
          -keypass android \
          -alias debug \
          -keyalg RSA \
          -keysize 2048 \
          -validity 10000 \
          -dname "CN=Debug, OU=Debug, O=Debug, L=Debug, ST=Debug, C=US"

        ${buildTools}/apksigner sign \
          --ks debug.keystore \
          --ks-pass pass:android \
          --key-pass pass:android \
          --ks-key-alias debug \
          --out ${apkName} \
          aligned.apk
      '';

      installPhase = ''
        mkdir -p $out
        cp ${apkName} $out/
      '';
    };

  # ---------------------------------------------------------------------------
  # mkEmulatorTest: Android emulator lifecycle test script
  # ---------------------------------------------------------------------------
  mkEmulatorTest =
    { apk
    , apkFileName
    , packageName
    , activity ? ".MainActivity"
    , events ? [ "Lifecycle: Create" "Lifecycle: Start" "Lifecycle: Resume"
                 "Android UI bridge initialized" ]
    , name ? "emulator-test"
    }:
    let
      sdk = emulatorSdk;
      sdkRoot = emulatorSdkRoot;
      platformVersion = "34";
      systemImageType = "google_apis_playstore";
      abiVersion = "x86_64";
      imagePackage = "system-images;android-${platformVersion};${systemImageType};${abiVersion}";

      # Build the bash array literal for events
      eventsArray = builtins.concatStringsSep " " (map (e: "\"${e}\"") events);
    in
    pkgs.stdenv.mkDerivation {
      inherit name;

      dontUnpack = true;

      buildPhase = ''
        mkdir -p $out/bin

        cat > $out/bin/test-lifecycle << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
export ANDROID_SDK_ROOT="${sdkRoot}"
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
EMULATOR="$ANDROID_SDK_ROOT/emulator/emulator"
AVDMANAGER="${sdk}/bin/avdmanager"
APK_PATH="${apk}/${apkFileName}"
PACKAGE="${packageName}"
ACTIVITY="${activity}"
DEVICE_NAME="test_lifecycle"

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
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-emu-XXXX)
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

# --- Clear and capture logcat ---
echo "=== Preparing logcat ==="
"$ADB" -s "emulator-$PORT" logcat -c
"$ADB" -s "emulator-$PORT" logcat '*:I' > "$LOGCAT_FILE" 2>&1 &
LOGCAT_PID=$!
sleep 2

# --- Launch activity ---
echo "=== Launching $PACKAGE/$ACTIVITY ==="
"$ADB" -s "emulator-$PORT" shell am start -n "$PACKAGE/$ACTIVITY"
sleep 10

# --- Poll logcat for lifecycle events ---
echo "=== Checking for lifecycle events (timeout: 120s) ==="
EVENTS=(${eventsArray})
POLL_TIMEOUT=120
POLL_ELAPSED=0
ALL_FOUND=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    FOUND_COUNT=0
    for event in "''${EVENTS[@]}"; do
        if grep -q "$event" "$LOGCAT_FILE" 2>/dev/null; then
            FOUND_COUNT=$((FOUND_COUNT + 1))
        fi
    done

    if [ $FOUND_COUNT -eq ''${#EVENTS[@]} ]; then
        ALL_FOUND=1
        break
    fi

    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

kill "$LOGCAT_PID" 2>/dev/null || true

# --- Report results ---
echo ""
echo "=== Results ==="
echo "--- HaskellMobile logcat ---"
grep -i "HaskellMobile\|UIBridge\|haskellmobile\|loadLibrary\|FATAL\|CRASH\|System.load" "$LOGCAT_FILE" 2>/dev/null || echo "(no matching lines)"
echo "--- End filtered logcat ---"
echo ""

EXIT_CODE=0
for event in "''${EVENTS[@]}"; do
    if grep -q "$event" "$LOGCAT_FILE" 2>/dev/null; then
        echo "PASS: $event"
    else
        echo "FAIL: $event (not found in logcat)"
        EXIT_CODE=1
    fi
done

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "All lifecycle events verified successfully!"
else
    echo "Some lifecycle events were not detected."
fi

exit $EXIT_CODE
SCRIPT

        chmod +x $out/bin/test-lifecycle
      '';

      installPhase = "true";
    };

  # ---------------------------------------------------------------------------
  # mkIOSLib: Compile Haskell to static .a for iOS (device or simulator)
  # ---------------------------------------------------------------------------
  mkIOSLib =
    { haskellMobileSrc
    , mainModule
    , simulator ? false
    , pname ? "haskell-mobile-ios"
    , extraModuleCopy ? ""
    }:
    let
      iosPkgs = import sources.nixpkgs {};
      iosGhc = iosPkgs.haskellPackages.ghc;
      mac2ios = import (haskellMobileSrc + "/nix/mac2ios.nix") { inherit sources; pkgs = iosPkgs; };
      gmpStatic = iosPkgs.gmp.overrideAttrs (old: {
        dontDisableStatic = true;
      });
    in
    iosPkgs.stdenv.mkDerivation {
      inherit pname;
      version = "0.1.0.0";

      src = haskellMobileSrc + "/src";

      nativeBuildInputs = [ iosGhc iosPkgs.cctools ];
      buildInputs = [ iosPkgs.libffi gmpStatic ];

      buildPhase = ''
        mkdir -p HaskellMobile
        cp ${haskellMobileSrc}/src/HaskellMobile/Types.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Lifecycle.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Widget.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/UIBridge.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Render.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile.hs .

        # Default App.hs — only copy if not already present
        if [ ! -f HaskellMobile/App.hs ]; then
          cp ${haskellMobileSrc}/src/HaskellMobile/App.hs HaskellMobile/
        fi

        # Extra module copies
        ${extraModuleCopy}

        cp ${mainModule} Main.hs

        # Copy C sources into writable build dir (GHC writes .o next to them)
        mkdir -p cbits
        cp ${haskellMobileSrc}/cbits/platform_log.c cbits/
        cp ${haskellMobileSrc}/cbits/ui_bridge.c cbits/
        cp ${haskellMobileSrc}/cbits/run_main.c cbits/

        ghc -staticlib \
          -O2 \
          -o libHaskellMobile.a \
          -I${haskellMobileSrc}/include \
          -optl-lffi \
          -optl-Wl,-u,_haskellRunMain \
          -optl-Wl,-u,_haskellGreet \
          -optl-Wl,-u,_haskellOnLifecycle \
          -optl-Wl,-u,_haskellCreateContext \
          -optl-Wl,-u,_haskellRenderUI \
          -optl-Wl,-u,_haskellOnUIEvent \
          cbits/platform_log.c \
          cbits/ui_bridge.c \
          cbits/run_main.c \
          Main.hs \
          HaskellMobile.hs
      '';

      installPhase = ''
        mkdir -p $out/lib $out/include

        echo "Merging libgmp.a into libHaskellMobile.a"
        libtool -static -o libCombined.a libHaskellMobile.a ${gmpStatic}/lib/libgmp.a
        mv libCombined.a libHaskellMobile.a

        ${mac2ios}/bin/mac2ios ${if simulator then "-s" else ""} libHaskellMobile.a
        cp libHaskellMobile.a $out/lib/
        cp ${haskellMobileSrc}/include/HaskellMobile.h $out/include/HaskellMobile.h
        cp ${haskellMobileSrc}/include/UIBridge.h $out/include/UIBridge.h
      '';
    };

  # ---------------------------------------------------------------------------
  # mkSimulatorApp: Stage iOS sources + pre-built library for xcodebuild
  # ---------------------------------------------------------------------------
  mkSimulatorApp =
    { iosLib
    , iosSrc
    , name ? "simulator-app"
    }:
    pkgs.stdenv.mkDerivation {
      inherit name;

      dontUnpack = true;

      buildPhase = ''
        mkdir -p $out/share/ios/lib $out/share/ios/include

        cp -r ${iosSrc}/HaskellMobile $out/share/ios/
        cp ${iosSrc}/project.yml $out/share/ios/project.yml

        cp ${iosLib}/lib/libHaskellMobile.a $out/share/ios/lib/
        cp ${iosLib}/include/HaskellMobile.h $out/share/ios/include/
        cp ${iosLib}/include/UIBridge.h $out/share/ios/include/
      '';

      installPhase = "true";
    };

  # ---------------------------------------------------------------------------
  # mkSimulatorTest: iOS Simulator lifecycle test script
  # ---------------------------------------------------------------------------
  mkSimulatorTest =
    { simulatorApp
    , bundleId
    , scheme
    , events ? [ "Lifecycle: Create" "Lifecycle: Resume" ]
    , name ? "simulator-test"
    }:
    let
      iosPkgs = import sources.nixpkgs {};
      xcodegen = iosPkgs.xcodegen;

      eventsArray = builtins.concatStringsSep " " (map (e: "\"${e}\"") events);
    in
    iosPkgs.stdenv.mkDerivation {
      inherit name;

      dontUnpack = true;

      buildPhase = ''
        mkdir -p $out/bin

        cat > $out/bin/test-lifecycle-ios << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
BUNDLE_ID="${bundleId}"
SCHEME="${scheme}"
DEVICE_TYPE="iPhone 16"
SHARE_DIR="${simulatorApp}/share/ios"

# --- Temp working directory ---
WORK_DIR=$(mktemp -d /tmp/haskell-mobile-sim-XXXX)
SIM_UDID=""

cleanup() {
    echo ""
    echo "=== Cleaning up ==="
    if [ -n "$SIM_UDID" ]; then
        echo "Shutting down simulator $SIM_UDID"
        xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
        echo "Deleting simulator $SIM_UDID"
        xcrun simctl delete "$SIM_UDID" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
    echo "Cleanup done."
}
trap cleanup EXIT

echo "=== iOS Simulator Lifecycle Test ==="
echo "Working directory: $WORK_DIR"

# --- Stage library and sources ---
echo "=== Staging Xcode project ==="
mkdir -p "$WORK_DIR/ios/lib" "$WORK_DIR/ios/include"
cp "$SHARE_DIR/lib/libHaskellMobile.a" "$WORK_DIR/ios/lib/"
cp "$SHARE_DIR/include/HaskellMobile.h" "$WORK_DIR/ios/include/"
cp "$SHARE_DIR/include/UIBridge.h" "$WORK_DIR/ios/include/"
cp -r "$SHARE_DIR/HaskellMobile" "$WORK_DIR/ios/"
cp "$SHARE_DIR/project.yml" "$WORK_DIR/ios/"
chmod -R u+w "$WORK_DIR/ios"

# --- Generate Xcode project ---
echo "=== Generating Xcode project ==="
cd "$WORK_DIR/ios"
${xcodegen}/bin/xcodegen generate

# --- Build for simulator ---
echo "=== Building for iOS Simulator ==="
xcodebuild build \
    -project HaskellMobile.xcodeproj \
    -scheme "$SCHEME" \
    -sdk iphonesimulator \
    -configuration Release \
    -derivedDataPath "$WORK_DIR/build" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    | tail -20

echo "Build succeeded."

# --- Find .app bundle ---
APP_PATH=$(find "$WORK_DIR/build" -name "*.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find .app bundle in build output"
    exit 1
fi
echo "App bundle: $APP_PATH"

# --- Discover latest iOS runtime ---
echo "=== Discovering iOS runtime ==="
RUNTIME=$(xcrun simctl list runtimes -j \
    | python3 -c "
import json, sys
data = json.load(sys.stdin)
ios_runtimes = [r for r in data['runtimes'] if r['platform'] == 'iOS' and r['isAvailable']]
if not ios_runtimes:
    print('ERROR: No available iOS runtimes', file=sys.stderr)
    sys.exit(1)
print(ios_runtimes[-1]['identifier'])
")
echo "Runtime: $RUNTIME"

# --- Create and boot simulator ---
echo "=== Creating simulator ==="
SIM_UDID=$(xcrun simctl create "test-lifecycle-ios" "$DEVICE_TYPE" "$RUNTIME" \
    | tr -d '[:space:]')

if [ -z "$SIM_UDID" ]; then
    echo "ERROR: Failed to create simulator device"
    exit 1
fi
echo "Simulator UDID: $SIM_UDID"

echo "=== Booting simulator ==="
xcrun simctl boot "$SIM_UDID"

BOOT_TIMEOUT=120
BOOT_ELAPSED=0
while [ $BOOT_ELAPSED -lt $BOOT_TIMEOUT ]; do
    STATE=$(xcrun simctl list devices -j \
        | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime_devs in data['devices'].values():
    for d in runtime_devs:
        if d['udid'] == '$SIM_UDID':
            print(d['state'])
            sys.exit(0)
print('Unknown')
")
    if [ "$STATE" = "Booted" ]; then
        echo "Simulator booted after ~''${BOOT_ELAPSED}s"
        break
    fi
    sleep 2
    BOOT_ELAPSED=$((BOOT_ELAPSED + 2))
done

if [ "$STATE" != "Booted" ]; then
    echo "ERROR: Simulator failed to boot within ''${BOOT_TIMEOUT}s"
    exit 1
fi

sleep 5

# --- Install app ---
echo "=== Installing app ==="
xcrun simctl install "$SIM_UDID" "$APP_PATH"
echo "App installed."

# --- Start log capture ---
echo "=== Starting log capture ==="
LOG_FILE="$WORK_DIR/os_log.txt"

xcrun simctl spawn "$SIM_UDID" log stream \
    --level info \
    --predicate "subsystem == \"${bundleId}\"" \
    --style compact \
    > "$LOG_FILE" 2>&1 &
LOG_PID=$!

sleep 5

check_events() {
    local FOUND_COUNT=0
    for event in "''${EVENTS[@]}"; do
        if grep -q "$event" "$LOG_FILE" 2>/dev/null; then
            FOUND_COUNT=$((FOUND_COUNT + 1))
        fi
    done
    [ $FOUND_COUNT -eq ''${#EVENTS[@]} ]
}

# --- Launch app ---
echo "=== Launching $BUNDLE_ID ==="
EVENTS=(${eventsArray})
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

# --- Poll for lifecycle events ---
echo "=== Checking for lifecycle events (timeout: 60s) ==="
POLL_TIMEOUT=60
POLL_ELAPSED=0
ALL_FOUND=0

while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
    if check_events; then
        ALL_FOUND=1
        break
    fi
    sleep 2
    POLL_ELAPSED=$((POLL_ELAPSED + 2))
done

# --- Retry: log stream can miss early startup messages ---
if [ $ALL_FOUND -eq 0 ]; then
    echo ""
    echo "=== Retrying: terminating and relaunching app ==="
    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true
    sleep 3
    > "$LOG_FILE"
    xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID"

    POLL_TIMEOUT=30
    POLL_ELAPSED=0
    while [ $POLL_ELAPSED -lt $POLL_TIMEOUT ]; do
        if check_events; then
            ALL_FOUND=1
            break
        fi
        sleep 2
        POLL_ELAPSED=$((POLL_ELAPSED + 2))
    done
fi

kill "$LOG_PID" 2>/dev/null || true

# --- Report results ---
echo ""
echo "=== Results ==="
echo "--- Captured log ---"
cat "$LOG_FILE" 2>/dev/null || echo "(no log output)"
echo "--- End log ---"
echo ""

EXIT_CODE=0
for event in "''${EVENTS[@]}"; do
    if grep -q "$event" "$LOG_FILE" 2>/dev/null; then
        echo "PASS: $event"
    else
        echo "FAIL: $event (not found in os_log)"
        EXIT_CODE=1
    fi
done

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "All lifecycle events verified successfully!"
else
    echo "Some lifecycle events were not detected."
fi

exit $EXIT_CODE
SCRIPT

        chmod +x $out/bin/test-lifecycle-ios
      '';

      installPhase = "true";
    };
}
