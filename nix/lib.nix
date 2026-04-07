# Reusable builder functions for haskell-mobile based projects.
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
#   in lib.mkAndroidLib { haskellMobileSrc = ../.; mainModule = ../app/MobileMain.hs; }
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
    , crossDeps ? null          # output of cross-deps.nix (lib/, hi/, pkgdb/)
    , maxNodes ? 256            # static pool size (ignored when dynamicNodePool=true)
    , dynamicNodePool ? false   # use malloc/realloc instead of fixed array
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
          ${if dynamicNodePool then "-DDYNAMIC_NODE_POOL"
            else if maxNodes != 256 then "-DMAX_NODES=${toString maxNodes}"
            else ""} \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${haskellMobileSrc}/include \
          -o ui_bridge_android.o \
          ${haskellMobileSrc}/cbits/ui_bridge_android.c

        ${ndkCc} -c -fPIC \
          -DJNI_PACKAGE=${jniPackageMacro} \
          -I${sysroot}/usr/include \
          -I$RTS_INCLUDE \
          -I${haskellMobileSrc}/include \
          -o permission_bridge_android.o \
          ${haskellMobileSrc}/cbits/permission_bridge_android.c

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
        cp ${haskellMobileSrc}/src/HaskellMobile/Locale.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/I18n.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Permission.hs HaskellMobile/
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
        cp ${haskellMobileSrc}/cbits/locale.c cbits/
        cp ${haskellMobileSrc}/cbits/permission_bridge.c cbits/

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
          -I${haskellMobileSrc}/include \
          ${builtins.concatStringsSep " " (map (d: "-I${d}") extraGhcIncludeDirs)} \
          ${if crossDeps != null then "-package-db ${crossDeps}/pkgdb -i${crossDeps}/hi" else ""} \
          Main.hs \
          HaskellMobile.hs \
          cbits/android_stubs.c \
          cbits/platform_log.c \
          cbits/numa_stubs.c \
          cbits/ui_bridge.c \
          cbits/run_main.c \
          cbits/locale.c \
          cbits/permission_bridge.c \
          -optl-L${androidPkgs.gmp}/lib \
          -optl-L${androidPkgs.libffi}/lib \
          -optl-lffi \
          -optl-llog \
          -optl-Wl,-z,max-page-size=16384 \
          -optl$(pwd)/jni_bridge.o \
          -optl$(pwd)/ui_bridge_android.o \
          -optl$(pwd)/permission_bridge_android.o \
          ${builtins.concatStringsSep " " (builtins.genList (i: "-optl$(pwd)/extra_jni_${toString i}.o") (builtins.length extraJniBridge))} \
          ${builtins.concatStringsSep " " (map (o: "-optl${o}") extraLinkObjects)} \
          -optl-Wl,-u,haskellRunMain \
          -optl-Wl,-u,haskellGreet \
          -optl-Wl,-u,haskellOnLifecycle \
          -optl-Wl,-u,haskellCreateContext \
          -optl-Wl,-u,haskellRenderUI \
          -optl-Wl,-u,haskellOnUIEvent \
          -optl-Wl,-u,haskellOnUITextChange \
          -optl-Wl,-u,haskellOnPermissionResult \
          -optl-Wl,-u,haskellLogLocale \
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
          ${if crossDeps != null then "$(for a in ${crossDeps}/lib/*.a; do echo -n \"-optl$a \"; done)" else ""} \
          -optl-Wl,--no-whole-archive
      '';

      installPhase = ''
        mkdir -p $out/lib/${archConfig.abiDir}
        cp ${soName} $out/lib/${archConfig.abiDir}/

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
    { haskellMobileSrc
    , mainModule
    , simulator ? false
    , pname ? "haskell-mobile-ios"
    , extraModuleCopy ? ""
    , crossDeps ? null          # output of ios-deps.nix (lib/, hi/, pkgdb/)
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
        cp ${haskellMobileSrc}/src/HaskellMobile/Locale.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/I18n.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Permission.hs HaskellMobile/
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
        cp ${haskellMobileSrc}/cbits/locale.c cbits/
        cp ${haskellMobileSrc}/cbits/permission_bridge.c cbits/

        ghc -staticlib \
          -O2 \
          -o libHaskellMobile.a \
          -I${haskellMobileSrc}/include \
          ${if crossDeps != null then "-package-db ${crossDeps}/pkgdb -i${crossDeps}/hi" else ""} \
          -optl-lffi \
          -optl-Wl,-u,_haskellRunMain \
          -optl-Wl,-u,_haskellGreet \
          -optl-Wl,-u,_haskellOnLifecycle \
          -optl-Wl,-u,_haskellCreateContext \
          -optl-Wl,-u,_haskellRenderUI \
          -optl-Wl,-u,_haskellOnUIEvent \
          -optl-Wl,-u,_haskellOnPermissionResult \
          -optl-Wl,-u,_haskellLogLocale \
          cbits/platform_log.c \
          cbits/ui_bridge.c \
          cbits/run_main.c \
          cbits/locale.c \
          cbits/permission_bridge.c \
          Main.hs \
          HaskellMobile.hs
      '';

      installPhase = ''
        mkdir -p $out/lib $out/include

        echo "Merging static archives into libHaskellMobile.a"
        libtool -static -o libCombined.a libHaskellMobile.a \
          ${gmpStatic}/lib/libgmp.a \
          ${if crossDeps != null then "${crossDeps}/lib/*.a" else ""}
        mv libCombined.a libHaskellMobile.a

        ${mac2ios}/bin/mac2ios ${if simulator then "-s" else ""} libHaskellMobile.a
        cp libHaskellMobile.a $out/lib/
        cp ${haskellMobileSrc}/include/HaskellMobile.h $out/include/HaskellMobile.h
        cp ${haskellMobileSrc}/include/UIBridge.h $out/include/UIBridge.h
        cp ${haskellMobileSrc}/include/PermissionBridge.h $out/include/PermissionBridge.h
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
      flagYaml = ''["$$(inherited)", ${builtins.concatStringsSep ", " (map (f: ''"${f}"'') nodePoolCFlags)}]'';
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

        cp -r ${iosSrc}/HaskellMobile $out/share/ios/
        cp ${iosSrc}/project.yml $out/share/ios/project.yml
        chmod u+w $out/share/ios/project.yml

        cp ${iosLib}/lib/libHaskellMobile.a $out/share/ios/lib/
        cp ${iosLib}/include/HaskellMobile.h $out/share/ios/include/
        cp ${iosLib}/include/UIBridge.h $out/share/ios/include/
        cp ${iosLib}/include/PermissionBridge.h $out/share/ios/include/
        ${patchProjectYml}
      '';

      installPhase = "true";
    };

  # ---------------------------------------------------------------------------
  # mkWatchOSLib: Compile Haskell to static .a for watchOS (device or simulator)
  # ---------------------------------------------------------------------------
  mkWatchOSLib =
    { haskellMobileSrc
    , mainModule
    , simulator ? false
    , pname ? "haskell-mobile-watchos"
    , extraModuleCopy ? ""
    , crossDeps ? null          # output of ios-deps.nix (lib/, hi/, pkgdb/)
    }:
    let
      iosPkgs = import sources.nixpkgs {};
      iosGhc = iosPkgs.haskellPackages.ghc;
      mac2watchos = import (haskellMobileSrc + "/nix/mac2watchos.nix") {
        inherit sources; pkgs = iosPkgs;
      };
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
        cp ${haskellMobileSrc}/src/HaskellMobile/Locale.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/I18n.hs HaskellMobile/
        cp ${haskellMobileSrc}/src/HaskellMobile/Permission.hs HaskellMobile/
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
        cp ${haskellMobileSrc}/cbits/locale.c cbits/
        cp ${haskellMobileSrc}/cbits/permission_bridge.c cbits/

        ghc -staticlib \
          -O2 \
          -o libHaskellMobile.a \
          -I${haskellMobileSrc}/include \
          ${if crossDeps != null then "-package-db ${crossDeps}/pkgdb -i${crossDeps}/hi" else ""} \
          -optl-lffi \
          -optl-Wl,-u,_haskellRunMain \
          -optl-Wl,-u,_haskellGreet \
          -optl-Wl,-u,_haskellOnLifecycle \
          -optl-Wl,-u,_haskellCreateContext \
          -optl-Wl,-u,_haskellRenderUI \
          -optl-Wl,-u,_haskellOnUIEvent \
          -optl-Wl,-u,_haskellOnPermissionResult \
          -optl-Wl,-u,_haskellLogLocale \
          cbits/platform_log.c \
          cbits/ui_bridge.c \
          cbits/run_main.c \
          cbits/locale.c \
          cbits/permission_bridge.c \
          Main.hs \
          HaskellMobile.hs
      '';

      installPhase = ''
        mkdir -p $out/lib $out/include

        echo "Merging static archives into libHaskellMobile.a"
        libtool -static -o libCombined.a libHaskellMobile.a \
          ${gmpStatic}/lib/libgmp.a \
          ${if crossDeps != null then "${crossDeps}/lib/*.a" else ""}
        mv libCombined.a libHaskellMobile.a

        ${mac2watchos}/bin/mac2watchos ${if simulator then "-s" else ""} libHaskellMobile.a
        cp libHaskellMobile.a $out/lib/
        cp ${haskellMobileSrc}/include/HaskellMobile.h $out/include/HaskellMobile.h
        cp ${haskellMobileSrc}/include/UIBridge.h $out/include/UIBridge.h
        cp ${haskellMobileSrc}/include/PermissionBridge.h $out/include/PermissionBridge.h
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

        cp -r ${watchosSrc}/HaskellMobile $out/share/watchos/
        cp ${watchosSrc}/project.yml $out/share/watchos/project.yml

        cp ${watchosLib}/lib/libHaskellMobile.a $out/share/watchos/lib/
        cp ${watchosLib}/include/HaskellMobile.h $out/share/watchos/include/
        cp ${watchosLib}/include/UIBridge.h $out/share/watchos/include/
        cp ${watchosLib}/include/PermissionBridge.h $out/share/watchos/include/
      '';

      installPhase = "true";
    };

}
