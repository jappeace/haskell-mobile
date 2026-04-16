# Reusable builder functions for hatter based projects.
#
# Returns an attrset of 6 builder functions:
#   mkAndroidLib       — cross-compile Haskell to .so for Android (aarch64 or armv7a)
#   mkApk              — package .so + Java + resources into signed APK
#   mkIOSLib           — compile Haskell to .a for iOS (device or simulator)
#   mkSimulatorApp     — stage iOS sources + pre-built library for xcodebuild
#   mkWatchOSLib       — compile Haskell to .a for watchOS (device or simulator)
#   mkWatchOSSimulatorApp — stage watchOS sources + pre-built library for xcodebuild
#
# Usage:
#   let lib = import ./lib.nix { sources = import ../npins; };
#   in lib.mkAndroidLib { hatterSrc = ../.; mainModule = ../test/ScrollDemoMain.hs; }
{ sources, androidArch ? "aarch64" }:
let
  archConfig = {
    aarch64 = {
      crossAttr = "aarch64-android-prebuilt";
      ndkTarget = "aarch64-linux-android26";
      ghcPkgArch = "aarch64-linux";
      abiDir = "arm64-v8a";
    };
    armv7a = {
      crossAttr = "armv7a-android-prebuilt";
      ndkTarget = "armv7a-linux-androideabi26";
      ghcPkgArch = "armv7-linux";
      abiDir = "armeabi-v7a";
    };
  }.${androidArch};

  # armv7a: compiler-rt's cmake doesn't include "armv7a" in its ARM32 arch
  # list, so builtin targets are empty and the build produces no output.
  # We patch the nixpkgs source to fix this (see patch-compiler-rt.py).
  nixpkgsSrc = import ./patched-nixpkgs.nix {
    nixpkgsSrc = sources.nixpkgs;
    inherit androidArch;
  };

  pkgs = import nixpkgsSrc {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  # --- Android cross-compilation infrastructure ---
  androidPkgs = pkgs.pkgsCross.${archConfig.crossAttr};
  # armv7a uses the LLVM backend (no NCG for 32-bit ARM).  Building profiled
  # libraries with the LLVM ARM backend triggers an llc crash in
  # ARMAsmPrinter::emitXXStructor (LLVM bug).  Disable profiling for armv7a.
  ghc = if androidArch == "armv7a"
    then androidPkgs.haskellPackages.ghc.override { enableProfiledLibs = false; }
    else androidPkgs.haskellPackages.ghc;
  ghcCmd = "${ghc}/bin/${ghc.targetPrefix}ghc";
  ghcPkgDir = "${ghc}/lib/${ghc.targetPrefix}ghc-${ghc.version}/lib/${archConfig.ghcPkgArch}-ghc-${ghc.version}";

  androidComposition = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
  };
  ndk = "${androidComposition.ndk-bundle}/libexec/android-sdk/ndk/${androidComposition.ndk-bundle.version}";
  ndkCc = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/${archConfig.ndkTarget}-clang";
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

in {

  # ---------------------------------------------------------------------------
  # mkAndroidLib: Cross-compile Haskell to shared .so for Android (aarch64/armv7a)
  # ---------------------------------------------------------------------------
  mkAndroidLib =
    { hatterSrc
    , mainModule
    , pname ? "hatter-android"
    , javaPackageName ? "me.jappie.hatter"
    , extraJniBridge ? []
    , extraNdkCompile ? (_: _: "")
    , extraModuleCopy ? ""
    , extraLinkObjects ? []
    , extraGhcIncludeDirs ? []
    , crossDeps ? null          # output of cross-deps.nix (lib/, hi/, pkgdb/)
    , extraGhcFlags ? []        # additional flags passed to cross-GHC
    , maxNodes ? 256            # static pool size (ignored when dynamicNodePool=true)
    , dynamicNodePool ? false   # use malloc/realloc instead of fixed array
    , soMaxSizeMB ? 200         # fail build if .so exceeds this (MB), catches whole-archive bloat
    }:
    let
      # Must match HatterActivity.java's System.loadLibrary("hatter").
      # Not configurable — any other name guarantees UnsatisfiedLinkError.
      soName = "libhatter.so";

      jniPackageMacro = builtins.replaceStrings ["."] ["_"] javaPackageName;

      # Template Haskell support for consumer code: when crossDeps includes
      # the iserv wrapper, add -fexternal-interpreter so GHC delegates TH
      # splices to the QEMU-emulated iserv-proxy-interpreter.
      thFlags = if crossDeps != null
        then "-fexternal-interpreter -pgmi ${crossDeps}/bin/iserv-proxy-wrapper"
        else "";
    in
    pkgs.stdenv.mkDerivation {
      inherit pname;
      version = "0.1.0.0";

      src = hatterSrc + "/src";

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
        # Core library C files always use me_jappie_hatter because
        # native methods are declared on HatterActivity (the library's
        # own class), not the consumer's subclass.
        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o jni_bridge.o \
          ${hatterSrc}/cbits/jni_bridge.c

        ${ndkCc} -c -fPIC \
          ${if dynamicNodePool then "-DDYNAMIC_NODE_POOL"
            else if maxNodes != 256 then "-DMAX_NODES=${toString maxNodes}"
            else ""} \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o ui_bridge_android.o \
          ${hatterSrc}/cbits/ui_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o permission_bridge_android.o \
          ${hatterSrc}/cbits/permission_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o secure_storage_android.o \
          ${hatterSrc}/cbits/secure_storage_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o ble_bridge_android.o \
          ${hatterSrc}/cbits/ble_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o dialog_bridge_android.o \
          ${hatterSrc}/cbits/dialog_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o location_bridge_android.o \
          ${hatterSrc}/cbits/location_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o auth_session_android.o \
          ${hatterSrc}/cbits/auth_session_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o platform_sign_in_android.o \
          ${hatterSrc}/cbits/platform_sign_in_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o camera_bridge_android.o \
          ${hatterSrc}/cbits/camera_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o bottom_sheet_android.o \
          ${hatterSrc}/cbits/bottom_sheet_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o http_bridge_android.o \
          ${hatterSrc}/cbits/http_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o network_status_android.o \
          ${hatterSrc}/cbits/network_status_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=me_jappie_hatter \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${hatterSrc}/include \
          -o animation_bridge_android.o \
          ${hatterSrc}/cbits/animation_bridge_android.c

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
          -I${hatterSrc}/include \
          -o ${oName} \
          ${src}
          '') (builtins.length extraJniBridge))}

        # Extra NDK compilation (e.g. SQLite, storage helpers)
        ${extraNdkCompile ndkCc sysroot}

        # Step 2: Copy source modules into writable build directory.
        # GHC writes _stub.h files next to sources, so they can't live in
        # the read-only nix store.
        mkdir -p Hatter
        cp ${hatterSrc}/src/Hatter/Types.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Lifecycle.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Widget.hs Hatter/
        cp ${hatterSrc}/src/Hatter/UIBridge.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Render.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Locale.hs Hatter/
        cp ${hatterSrc}/src/Hatter/I18n.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Permission.hs Hatter/
        cp ${hatterSrc}/src/Hatter/SecureStorage.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Ble.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Dialog.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Location.hs Hatter/
        cp ${hatterSrc}/src/Hatter/AuthSession.hs Hatter/
        cp ${hatterSrc}/src/Hatter/PlatformSignIn.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Camera.hs Hatter/
        cp ${hatterSrc}/src/Hatter/BottomSheet.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Http.hs Hatter/
        cp ${hatterSrc}/src/Hatter/NetworkStatus.hs Hatter/
        cp ${hatterSrc}/src/Hatter/AppContext.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Animation.hs Hatter/
        cp ${hatterSrc}/src/Hatter/FilesDir.hs Hatter/
        cp ${hatterSrc}/src/Hatter.hs .

        # Extra module copies (consumer overrides, additional modules)
        ${extraModuleCopy}

        # Copy user entry point (plain main :: IO (), no foreign export needed)
        cp ${mainModule} Main.hs

        # Step 3: Copy C sources into writable build dir and compile them
        # separately with cross-GHC.  This keeps them out of GHC's
        # compilation graph so iserv-proxy-interpreter doesn't try to
        # load them during Template Haskell evaluation (the C bridge
        # files reference Haskell FFI exports that iserv can't resolve).
        mkdir -p cbits
        cp ${hatterSrc}/cbits/android_stubs.c cbits/
        cp ${hatterSrc}/cbits/platform_log.c cbits/
        cp ${hatterSrc}/cbits/numa_stubs.c cbits/
        cp ${hatterSrc}/cbits/ui_bridge.c cbits/
        cp ${hatterSrc}/cbits/run_main.c cbits/
        cp ${hatterSrc}/cbits/locale.c cbits/
        cp ${hatterSrc}/cbits/permission_bridge.c cbits/
        cp ${hatterSrc}/cbits/secure_storage_bridge.c cbits/
        cp ${hatterSrc}/cbits/ble_bridge.c cbits/
        cp ${hatterSrc}/cbits/dialog_bridge.c cbits/
        cp ${hatterSrc}/cbits/location_bridge.c cbits/
        cp ${hatterSrc}/cbits/auth_session_bridge.c cbits/
        cp ${hatterSrc}/cbits/platform_sign_in_bridge.c cbits/
        cp ${hatterSrc}/cbits/camera_bridge.c cbits/
        cp ${hatterSrc}/cbits/bottom_sheet_bridge.c cbits/
        cp ${hatterSrc}/cbits/http_bridge.c cbits/
        cp ${hatterSrc}/cbits/network_status_bridge.c cbits/
        cp ${hatterSrc}/cbits/animation_bridge.c cbits/
        cp ${hatterSrc}/cbits/files_dir.c cbits/

        echo "=== Compiling C bridge files with cross-GHC ==="
        for cfile in cbits/*.c; do
          echo "  $cfile"
          ${ghcCmd} -c -I${hatterSrc}/include "$cfile"
        done

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
        TRANSFORMERS_LIB=$(find_lib "transformers")
        TIME_LIB=$(find_lib "time")

        echo "Libraries discovered:"
        echo "  rts: $RTS_LIB"
        echo "  ghc-prim: $GHC_PRIM_LIB"
        echo "  base: $BASE_LIB"
        echo "  containers: $CONTAINERS_LIB"

        ${ghcCmd} -shared -O2 \
          -o ${soName} \
          -I${hatterSrc}/include \
          ${builtins.concatStringsSep " " (map (d: "-I${d}") extraGhcIncludeDirs)} \
          ${if crossDeps != null then "-package-db ${crossDeps}/pkgdb -i${crossDeps}/hi" else ""} \
          ${thFlags} \
          ${builtins.concatStringsSep " " extraGhcFlags} \
          Main.hs \
          Hatter.hs \
          -optl-L${androidPkgs.gmp}/lib \
          -optl-L${androidPkgs.libffi}/lib \
          -optl-lffi \
          -optl-llog \
          -optl-Wl,-z,max-page-size=16384 \
          -optl$(pwd)/jni_bridge.o \
          -optl$(pwd)/ui_bridge_android.o \
          -optl$(pwd)/permission_bridge_android.o \
          -optl$(pwd)/secure_storage_android.o \
          -optl$(pwd)/ble_bridge_android.o \
          -optl$(pwd)/dialog_bridge_android.o \
          -optl$(pwd)/location_bridge_android.o \
          -optl$(pwd)/auth_session_android.o \
          -optl$(pwd)/platform_sign_in_android.o \
          -optl$(pwd)/camera_bridge_android.o \
          -optl$(pwd)/bottom_sheet_android.o \
          -optl$(pwd)/http_bridge_android.o \
          -optl$(pwd)/network_status_android.o \
          -optl$(pwd)/animation_bridge_android.o \
          -optl$(pwd)/cbits/android_stubs.o \
          -optl$(pwd)/cbits/platform_log.o \
          -optl$(pwd)/cbits/numa_stubs.o \
          -optl$(pwd)/cbits/ui_bridge.o \
          -optl$(pwd)/cbits/run_main.o \
          -optl$(pwd)/cbits/locale.o \
          -optl$(pwd)/cbits/permission_bridge.o \
          -optl$(pwd)/cbits/secure_storage_bridge.o \
          -optl$(pwd)/cbits/ble_bridge.o \
          -optl$(pwd)/cbits/dialog_bridge.o \
          -optl$(pwd)/cbits/location_bridge.o \
          -optl$(pwd)/cbits/auth_session_bridge.o \
          -optl$(pwd)/cbits/platform_sign_in_bridge.o \
          -optl$(pwd)/cbits/camera_bridge.o \
          -optl$(pwd)/cbits/bottom_sheet_bridge.o \
          -optl$(pwd)/cbits/http_bridge.o \
          -optl$(pwd)/cbits/network_status_bridge.o \
          -optl$(pwd)/cbits/animation_bridge.o \
          -optl$(pwd)/cbits/files_dir.o \
          ${builtins.concatStringsSep " " (builtins.genList (i: "-optl$(pwd)/extra_jni_${toString i}.o") (builtins.length extraJniBridge))} \
          ${builtins.concatStringsSep " " (map (o: "-optl${o}") extraLinkObjects)} \
          -optl-Wl,-u,haskellRunMain \
          -optl-Wl,-u,haskellOnLifecycle \
          -optl-Wl,-u,haskellRenderUI \
          -optl-Wl,-u,haskellOnUIEvent \
          -optl-Wl,-u,haskellOnUITextChange \
          -optl-Wl,-u,haskellOnPermissionResult \
          -optl-Wl,-u,haskellOnSecureStorageResult \
          -optl-Wl,-u,haskellOnBleScanResult \
          -optl-Wl,-u,haskellOnDialogResult \
          -optl-Wl,-u,haskellOnLocationUpdate \
          -optl-Wl,-u,haskellOnAuthSessionResult \
          -optl-Wl,-u,haskellOnPlatformSignInResult \
          -optl-Wl,-u,haskellOnCameraResult \
          -optl-Wl,-u,haskellOnVideoFrame \
          -optl-Wl,-u,haskellOnAudioChunk \
          -optl-Wl,-u,haskellOnBottomSheetResult \
          -optl-Wl,-u,haskellOnHttpResult \
          -optl-Wl,-u,haskellOnNetworkStatusChange \
          -optl-Wl,-u,haskellLogLocale \
          -optl-Wl,--wrap=registerForeignExports \
          -optl-Wl,--no-undefined \
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
          -optl$TRANSFORMERS_LIB \
          -optl$TIME_LIB \
          -optl-Wl,--no-whole-archive \
          ${if crossDeps != null then "$(for a in ${crossDeps}/lib/*.a; do echo -n \"-optl$a \"; done)" else ""} \
          ${if crossDeps != null && builtins.pathExists "${crossDeps}/lib-boot" then "$(for a in ${crossDeps}/lib-boot/*.a; do echo -n \"-optl$a \"; done)" else ""}
      '';

      installPhase = ''
        # Warn if .so is suspiciously large (see docs/ci-ram-regression-110.md).
        SO_SIZE_BYTES=$(stat -c %s ${soName})
        SO_SIZE_MB=$((SO_SIZE_BYTES / 1048576))
        echo ".so size: ''${SO_SIZE_MB} MB (warn threshold: ${toString soMaxSizeMB} MB)"
        if [ "$SO_SIZE_MB" -gt "${toString soMaxSizeMB}" ]; then
          echo "WARNING: ${soName} is ''${SO_SIZE_MB} MB, exceeds ${toString soMaxSizeMB} MB."
          echo "This usually means boot package .a files ended up in the --whole-archive link group."
          echo "Check that crossDeps .a files are in the correct directory (lib/ vs lib-boot/)."
        fi

        mkdir -p $out/lib/${archConfig.abiDir}
        cp ${soName} $out/lib/${archConfig.abiDir}/

        # Strip debug symbols to reduce .so size and runtime memory usage.
        # GHC embeds large debug/unwind sections; stripping typically cuts
        # the .so by 60-80%, which also prevents OOM kills on emulators.
        echo "Stripping debug symbols from ${soName}..."
        SO_BEFORE=$(stat -c %s $out/lib/${archConfig.abiDir}/${soName})
        ${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip \
          --strip-debug $out/lib/${archConfig.abiDir}/${soName}
        SO_AFTER=$(stat -c %s $out/lib/${archConfig.abiDir}/${soName})
        echo "Stripped: $((SO_BEFORE / 1048576)) MB -> $((SO_AFTER / 1048576)) MB"

        # Bundle runtime dependencies (not provided by Android)
        cp ${androidPkgs.gmp}/lib/libgmp.so $out/lib/${archConfig.abiDir}/
        cp ${androidPkgs.libffi}/lib/libffi.so $out/lib/${archConfig.abiDir}/
      '';
    };

  # ---------------------------------------------------------------------------
  # mkApk: Package shared library + Java + resources into a signed APK
  # ---------------------------------------------------------------------------
  mkApk =
    { sharedLibs ? null       # list of { lib = <drv>; abiDir = "arm64-v8a"; }
    , sharedLib ? null        # backward compat: single lib drv (assumes arm64-v8a)
    , androidSrc
    , baseJavaSrc ? null      # path to hatter's android/java/ for consumer APKs
    , apkName ? "app.apk"
    , name ? "app-apk"
    }:
    let
      resolvedLibs =
        if sharedLibs != null then sharedLibs
        else if sharedLib != null then [{ lib = sharedLib; abiDir = "arm64-v8a"; }]
        else builtins.throw "mkApk: either sharedLibs or sharedLib must be provided";
    in
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
          $(find java -name '*.java') \
          ${if baseJavaSrc != null then "$(find ${baseJavaSrc} -name '*.java')" else ""}

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
        ${builtins.concatStringsSep "\n" (map (sl: ''
        mkdir -p lib/${sl.abiDir}
        cp ${sl.lib}/lib/${sl.abiDir}/*.so lib/${sl.abiDir}/
        '') resolvedLibs)}
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
  # mkIOSLib: Compile Haskell to static .a for iOS (device or simulator)
  # ---------------------------------------------------------------------------
  mkIOSLib =
    { hatterSrc
    , mainModule
    , simulator ? false
    , pname ? "hatter-ios"
    , extraModuleCopy ? ""
    , crossDeps ? null          # output of ios-deps.nix (lib/, hi/, pkgdb/)
    }:
    let
      iosPkgs = import sources.nixpkgs {};
      iosGhc = iosPkgs.haskellPackages.ghc;
      mac2ios = import (hatterSrc + "/nix/mac2ios.nix") { inherit sources; pkgs = iosPkgs; };
      gmpStatic = iosPkgs.gmp.overrideAttrs (old: {
        dontDisableStatic = true;
      });
    in
    iosPkgs.stdenv.mkDerivation {
      inherit pname;
      version = "0.1.0.0";

      src = hatterSrc + "/src";

      nativeBuildInputs = [ iosGhc iosPkgs.cctools ];
      buildInputs = [ iosPkgs.libffi gmpStatic ];

      buildPhase = ''
        mkdir -p Hatter
        cp ${hatterSrc}/src/Hatter/Types.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Lifecycle.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Widget.hs Hatter/
        cp ${hatterSrc}/src/Hatter/UIBridge.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Render.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Locale.hs Hatter/
        cp ${hatterSrc}/src/Hatter/I18n.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Permission.hs Hatter/
        cp ${hatterSrc}/src/Hatter/SecureStorage.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Ble.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Dialog.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Location.hs Hatter/
        cp ${hatterSrc}/src/Hatter/AuthSession.hs Hatter/
        cp ${hatterSrc}/src/Hatter/PlatformSignIn.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Camera.hs Hatter/
        cp ${hatterSrc}/src/Hatter/BottomSheet.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Http.hs Hatter/
        cp ${hatterSrc}/src/Hatter/NetworkStatus.hs Hatter/
        cp ${hatterSrc}/src/Hatter/AppContext.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Animation.hs Hatter/
        cp ${hatterSrc}/src/Hatter/FilesDir.hs Hatter/
        cp ${hatterSrc}/src/Hatter.hs .

        # Extra module copies
        ${extraModuleCopy}

        cp ${mainModule} Main.hs

        # Copy C sources into writable build dir (GHC writes .o next to them)
        mkdir -p cbits
        cp ${hatterSrc}/cbits/platform_log.c cbits/
        cp ${hatterSrc}/cbits/ui_bridge.c cbits/
        cp ${hatterSrc}/cbits/run_main.c cbits/
        cp ${hatterSrc}/cbits/locale.c cbits/
        cp ${hatterSrc}/cbits/permission_bridge.c cbits/
        cp ${hatterSrc}/cbits/secure_storage_bridge.c cbits/
        cp ${hatterSrc}/cbits/ble_bridge.c cbits/
        cp ${hatterSrc}/cbits/dialog_bridge.c cbits/
        cp ${hatterSrc}/cbits/location_bridge.c cbits/
        cp ${hatterSrc}/cbits/auth_session_bridge.c cbits/
        cp ${hatterSrc}/cbits/platform_sign_in_bridge.c cbits/
        cp ${hatterSrc}/cbits/camera_bridge.c cbits/
        cp ${hatterSrc}/cbits/bottom_sheet_bridge.c cbits/
        cp ${hatterSrc}/cbits/http_bridge.c cbits/
        cp ${hatterSrc}/cbits/network_status_bridge.c cbits/
        cp ${hatterSrc}/cbits/animation_bridge.c cbits/
        cp ${hatterSrc}/cbits/files_dir.c cbits/

        ghc -staticlib \
          -O2 \
          -o libHatter.a \
          -I${hatterSrc}/include \
          ${if crossDeps != null then "-package-db ${crossDeps}/pkgdb -i${crossDeps}/hi" else ""} \
          -optl-lffi \
          -optl-Wl,-u,_haskellRunMain \
          -optl-Wl,-u,_haskellOnLifecycle \
          -optl-Wl,-u,_haskellRenderUI \
          -optl-Wl,-u,_haskellOnUIEvent \
          -optl-Wl,-u,_haskellOnPermissionResult \
          -optl-Wl,-u,_haskellOnSecureStorageResult \
          -optl-Wl,-u,_haskellOnBleScanResult \
          -optl-Wl,-u,_haskellOnDialogResult \
          -optl-Wl,-u,_haskellOnLocationUpdate \
          -optl-Wl,-u,_haskellOnAuthSessionResult \
          -optl-Wl,-u,_haskellOnPlatformSignInResult \
          -optl-Wl,-u,_haskellOnCameraResult \
          -optl-Wl,-u,_haskellOnVideoFrame \
          -optl-Wl,-u,_haskellOnAudioChunk \
          -optl-Wl,-u,_haskellOnBottomSheetResult \
          -optl-Wl,-u,_haskellOnHttpResult \
          -optl-Wl,-u,_haskellOnNetworkStatusChange \
          -optl-Wl,-u,_haskellLogLocale \
          cbits/platform_log.c \
          cbits/ui_bridge.c \
          cbits/run_main.c \
          cbits/locale.c \
          cbits/permission_bridge.c \
          cbits/secure_storage_bridge.c \
          cbits/ble_bridge.c \
          cbits/dialog_bridge.c \
          cbits/location_bridge.c \
          cbits/auth_session_bridge.c \
          cbits/platform_sign_in_bridge.c \
          cbits/camera_bridge.c \
          cbits/bottom_sheet_bridge.c \
          cbits/http_bridge.c \
          cbits/network_status_bridge.c \
          cbits/animation_bridge.c \
          cbits/files_dir.c \
          Main.hs \
          Hatter.hs
      '';

      installPhase = ''
        mkdir -p $out/lib $out/include

        echo "Merging static archives into libHatter.a"
        libtool -static -o libCombined.a libHatter.a \
          ${gmpStatic}/lib/libgmp.a \
          ${if crossDeps != null then "${crossDeps}/lib/*.a" else ""}
        mv libCombined.a libHatter.a

        ${mac2ios}/bin/mac2ios ${if simulator then "-s" else ""} libHatter.a
        cp libHatter.a $out/lib/
        cp ${hatterSrc}/include/Hatter.h $out/include/Hatter.h
        cp ${hatterSrc}/include/UIBridge.h $out/include/UIBridge.h
        cp ${hatterSrc}/include/PermissionBridge.h $out/include/PermissionBridge.h
        cp ${hatterSrc}/include/SecureStorageBridge.h $out/include/SecureStorageBridge.h
        cp ${hatterSrc}/include/BleBridge.h $out/include/BleBridge.h
        cp ${hatterSrc}/include/DialogBridge.h $out/include/DialogBridge.h
        cp ${hatterSrc}/include/LocationBridge.h $out/include/LocationBridge.h
        cp ${hatterSrc}/include/AuthSessionBridge.h $out/include/AuthSessionBridge.h
        cp ${hatterSrc}/include/PlatformSignInBridge.h $out/include/PlatformSignInBridge.h
        cp ${hatterSrc}/include/CameraBridge.h $out/include/CameraBridge.h
        cp ${hatterSrc}/include/BottomSheetBridge.h $out/include/BottomSheetBridge.h
        cp ${hatterSrc}/include/HttpBridge.h $out/include/HttpBridge.h
        cp ${hatterSrc}/include/NetworkStatusBridge.h $out/include/NetworkStatusBridge.h
        cp ${hatterSrc}/include/AnimationBridge.h $out/include/AnimationBridge.h
      '';
    };

  # ---------------------------------------------------------------------------
  # mkSimulatorApp: Stage iOS sources + pre-built library for xcodebuild
  # ---------------------------------------------------------------------------
  mkSimulatorApp =
    { iosLib
    , iosSrc
    , name ? "simulator-app"
    , maxNodes ? 256            # static pool size (ignored when dynamicNodePool=true)
    , dynamicNodePool ? false   # use malloc/realloc instead of fixed array
    }:
    let
      nodePoolCFlags =
        if dynamicNodePool then ["-DDYNAMIC_NODE_POOL"]
        else if maxNodes != 256 then ["-DMAX_NODES=${toString maxNodes}"]
        else [];
      # Inject OTHER_CFLAGS into project.yml when non-default pool settings used.
      # Uses single-quoted -c and argv to avoid shell quoting issues.
      flagYaml = ''[${builtins.concatStringsSep ", " (map (f: ''"${f}"'') nodePoolCFlags)}]'';
      patchProjectYml =
        if nodePoolCFlags == [] then ""
        else ''
          ${pkgs.python3}/bin/python3 -c '
import sys
yml = open(sys.argv[1]).read()
yml = yml.replace(
    "OTHER_LDFLAGS:",
    "OTHER_CFLAGS: " + sys.argv[2] + "\n        OTHER_LDFLAGS:"
)
open(sys.argv[1], "w").write(yml)
' "$out/share/ios/project.yml" '${flagYaml}'
        '';
    in
    pkgs.stdenv.mkDerivation {
      inherit name;

      dontUnpack = true;

      buildPhase = ''
        mkdir -p $out/share/ios/lib $out/share/ios/include

        cp -r ${iosSrc}/Hatter $out/share/ios/
        cp ${iosSrc}/project.yml $out/share/ios/project.yml
        chmod u+w $out/share/ios/project.yml

        cp ${iosLib}/lib/libHatter.a $out/share/ios/lib/
        cp ${iosLib}/include/Hatter.h $out/share/ios/include/
        cp ${iosLib}/include/UIBridge.h $out/share/ios/include/
        cp ${iosLib}/include/PermissionBridge.h $out/share/ios/include/
        cp ${iosLib}/include/SecureStorageBridge.h $out/share/ios/include/
        cp ${iosLib}/include/BleBridge.h $out/share/ios/include/
        cp ${iosLib}/include/DialogBridge.h $out/share/ios/include/
        cp ${iosLib}/include/LocationBridge.h $out/share/ios/include/
        cp ${iosLib}/include/AuthSessionBridge.h $out/share/ios/include/
        cp ${iosLib}/include/PlatformSignInBridge.h $out/share/ios/include/
        cp ${iosLib}/include/CameraBridge.h $out/share/ios/include/
        cp ${iosLib}/include/BottomSheetBridge.h $out/share/ios/include/
        cp ${iosLib}/include/HttpBridge.h $out/share/ios/include/
        cp ${iosLib}/include/NetworkStatusBridge.h $out/share/ios/include/
        cp ${iosLib}/include/AnimationBridge.h $out/share/ios/include/
        ${patchProjectYml}
      '';

      installPhase = "true";
    };

  # ---------------------------------------------------------------------------
  # mkWatchOSLib: Compile Haskell to static .a for watchOS (device or simulator)
  # ---------------------------------------------------------------------------
  mkWatchOSLib =
    { hatterSrc
    , mainModule
    , simulator ? false
    , pname ? "hatter-watchos"
    , extraModuleCopy ? ""
    , crossDeps ? null          # output of ios-deps.nix (lib/, hi/, pkgdb/)
    }:
    let
      iosPkgs = import sources.nixpkgs {};
      iosGhc = iosPkgs.haskellPackages.ghc;
      mac2watchos = import (hatterSrc + "/nix/mac2watchos.nix") {
        inherit sources; pkgs = iosPkgs;
      };
      gmpStatic = iosPkgs.gmp.overrideAttrs (old: {
        dontDisableStatic = true;
      });
    in
    iosPkgs.stdenv.mkDerivation {
      inherit pname;
      version = "0.1.0.0";

      src = hatterSrc + "/src";

      nativeBuildInputs = [ iosGhc iosPkgs.cctools ];
      buildInputs = [ iosPkgs.libffi gmpStatic ];

      buildPhase = ''
        mkdir -p Hatter
        cp ${hatterSrc}/src/Hatter/Types.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Lifecycle.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Widget.hs Hatter/
        cp ${hatterSrc}/src/Hatter/UIBridge.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Render.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Locale.hs Hatter/
        cp ${hatterSrc}/src/Hatter/I18n.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Permission.hs Hatter/
        cp ${hatterSrc}/src/Hatter/SecureStorage.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Ble.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Dialog.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Location.hs Hatter/
        cp ${hatterSrc}/src/Hatter/AuthSession.hs Hatter/
        cp ${hatterSrc}/src/Hatter/PlatformSignIn.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Camera.hs Hatter/
        cp ${hatterSrc}/src/Hatter/BottomSheet.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Http.hs Hatter/
        cp ${hatterSrc}/src/Hatter/NetworkStatus.hs Hatter/
        cp ${hatterSrc}/src/Hatter/AppContext.hs Hatter/
        cp ${hatterSrc}/src/Hatter/Animation.hs Hatter/
        cp ${hatterSrc}/src/Hatter/FilesDir.hs Hatter/
        cp ${hatterSrc}/src/Hatter.hs .

        # Extra module copies
        ${extraModuleCopy}

        cp ${mainModule} Main.hs

        # Copy C sources into writable build dir (GHC writes .o next to them)
        mkdir -p cbits
        cp ${hatterSrc}/cbits/platform_log.c cbits/
        cp ${hatterSrc}/cbits/ui_bridge.c cbits/
        cp ${hatterSrc}/cbits/run_main.c cbits/
        cp ${hatterSrc}/cbits/locale.c cbits/
        cp ${hatterSrc}/cbits/permission_bridge.c cbits/
        cp ${hatterSrc}/cbits/secure_storage_bridge.c cbits/
        cp ${hatterSrc}/cbits/ble_bridge.c cbits/
        cp ${hatterSrc}/cbits/dialog_bridge.c cbits/
        cp ${hatterSrc}/cbits/location_bridge.c cbits/
        cp ${hatterSrc}/cbits/auth_session_bridge.c cbits/
        cp ${hatterSrc}/cbits/platform_sign_in_bridge.c cbits/
        cp ${hatterSrc}/cbits/camera_bridge.c cbits/
        cp ${hatterSrc}/cbits/bottom_sheet_bridge.c cbits/
        cp ${hatterSrc}/cbits/http_bridge.c cbits/
        cp ${hatterSrc}/cbits/network_status_bridge.c cbits/
        cp ${hatterSrc}/cbits/animation_bridge.c cbits/
        cp ${hatterSrc}/cbits/files_dir.c cbits/

        ghc -staticlib \
          -O2 \
          -o libHatter.a \
          -I${hatterSrc}/include \
          ${if crossDeps != null then "-package-db ${crossDeps}/pkgdb -i${crossDeps}/hi" else ""} \
          -optl-lffi \
          -optl-Wl,-u,_haskellRunMain \
          -optl-Wl,-u,_haskellOnLifecycle \
          -optl-Wl,-u,_haskellRenderUI \
          -optl-Wl,-u,_haskellOnUIEvent \
          -optl-Wl,-u,_haskellOnPermissionResult \
          -optl-Wl,-u,_haskellOnSecureStorageResult \
          -optl-Wl,-u,_haskellOnBleScanResult \
          -optl-Wl,-u,_haskellOnDialogResult \
          -optl-Wl,-u,_haskellOnLocationUpdate \
          -optl-Wl,-u,_haskellOnAuthSessionResult \
          -optl-Wl,-u,_haskellOnPlatformSignInResult \
          -optl-Wl,-u,_haskellOnCameraResult \
          -optl-Wl,-u,_haskellOnVideoFrame \
          -optl-Wl,-u,_haskellOnAudioChunk \
          -optl-Wl,-u,_haskellOnBottomSheetResult \
          -optl-Wl,-u,_haskellOnHttpResult \
          -optl-Wl,-u,_haskellOnNetworkStatusChange \
          -optl-Wl,-u,_haskellLogLocale \
          cbits/platform_log.c \
          cbits/ui_bridge.c \
          cbits/run_main.c \
          cbits/locale.c \
          cbits/permission_bridge.c \
          cbits/secure_storage_bridge.c \
          cbits/ble_bridge.c \
          cbits/dialog_bridge.c \
          cbits/location_bridge.c \
          cbits/auth_session_bridge.c \
          cbits/platform_sign_in_bridge.c \
          cbits/camera_bridge.c \
          cbits/bottom_sheet_bridge.c \
          cbits/http_bridge.c \
          cbits/network_status_bridge.c \
          cbits/animation_bridge.c \
          cbits/files_dir.c \
          Main.hs \
          Hatter.hs
      '';

      installPhase = ''
        mkdir -p $out/lib $out/include

        echo "Merging static archives into libHatter.a"
        libtool -static -o libCombined.a libHatter.a \
          ${gmpStatic}/lib/libgmp.a \
          ${if crossDeps != null then "${crossDeps}/lib/*.a" else ""}
        mv libCombined.a libHatter.a

        ${mac2watchos}/bin/mac2watchos ${if simulator then "-s" else ""} libHatter.a
        cp libHatter.a $out/lib/
        cp ${hatterSrc}/include/Hatter.h $out/include/Hatter.h
        cp ${hatterSrc}/include/UIBridge.h $out/include/UIBridge.h
        cp ${hatterSrc}/include/PermissionBridge.h $out/include/PermissionBridge.h
        cp ${hatterSrc}/include/SecureStorageBridge.h $out/include/SecureStorageBridge.h
        cp ${hatterSrc}/include/BleBridge.h $out/include/BleBridge.h
        cp ${hatterSrc}/include/DialogBridge.h $out/include/DialogBridge.h
        cp ${hatterSrc}/include/LocationBridge.h $out/include/LocationBridge.h
        cp ${hatterSrc}/include/AuthSessionBridge.h $out/include/AuthSessionBridge.h
        cp ${hatterSrc}/include/PlatformSignInBridge.h $out/include/PlatformSignInBridge.h
        cp ${hatterSrc}/include/CameraBridge.h $out/include/CameraBridge.h
        cp ${hatterSrc}/include/BottomSheetBridge.h $out/include/BottomSheetBridge.h
        cp ${hatterSrc}/include/HttpBridge.h $out/include/HttpBridge.h
        cp ${hatterSrc}/include/NetworkStatusBridge.h $out/include/NetworkStatusBridge.h
        cp ${hatterSrc}/include/AnimationBridge.h $out/include/AnimationBridge.h
      '';
    };

  # ---------------------------------------------------------------------------
  # mkWatchOSSimulatorApp: Stage watchOS sources + pre-built library for xcodebuild
  # ---------------------------------------------------------------------------
  mkWatchOSSimulatorApp =
    { watchosLib
    , watchosSrc
    , name ? "watchos-simulator-app"
    }:
    pkgs.stdenv.mkDerivation {
      inherit name;

      dontUnpack = true;

      buildPhase = ''
        mkdir -p $out/share/watchos/lib $out/share/watchos/include

        cp -r ${watchosSrc}/Hatter $out/share/watchos/
        cp ${watchosSrc}/project.yml $out/share/watchos/project.yml

        cp ${watchosLib}/lib/libHatter.a $out/share/watchos/lib/
        cp ${watchosLib}/include/Hatter.h $out/share/watchos/include/
        cp ${watchosLib}/include/UIBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/PermissionBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/SecureStorageBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/BleBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/DialogBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/LocationBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/AuthSessionBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/PlatformSignInBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/CameraBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/BottomSheetBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/HttpBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/NetworkStatusBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/AnimationBridge.h $out/share/watchos/include/
      '';

      installPhase = "true";
    };

}
