# Android shared library build pipeline.
# Builds Haskell to a shared .so for aarch64-android using nixpkgs
# cross-compilation (pkgsCross.aarch64-android-prebuilt) instead of
# haskell.nix, which builds GHC from source without cache hits.
#
# Uses Google's prebuilt NDK toolchain via nixpkgs, avoiding the
# LLVM 19 compiler-rt issue (NixOS/nixpkgs#380604).
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  };

  # Cross-compilation packages for Android using prebuilt NDK toolchain
  androidPkgs = pkgs.pkgsCross.aarch64-android-prebuilt;

  # Cross-GHC: runs on x86_64-linux, produces aarch64-android code
  ghc = androidPkgs.haskellPackages.ghc;
  ghcCmd = "${ghc}/bin/${ghc.targetPrefix}ghc";

  # Path to GHC's boot library static archives (for static linking into .so)
  ghcPkgDir = "${ghc}/lib/${ghc.targetPrefix}ghc-${ghc.version}/lib/aarch64-linux-ghc-${ghc.version}";

  # NDK toolchain for compiling the JNI bridge C code
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    includeNDK = true;
  };
  ndk = "${androidComposition.ndk-bundle}/libexec/android-sdk/ndk/${androidComposition.ndk-bundle.version}";
  ndkCc = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang";
  sysroot = "${ndk}/toolchains/llvm/prebuilt/linux-x86_64/sysroot";

in pkgs.stdenv.mkDerivation {
  pname = "haskell-mobile-android";
  version = "0.1.0.0";

  src = ../src;

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
      -I${sysroot}/usr/include \
      -I$RTS_INCLUDE \
      -I${../include} \
      -o jni_bridge.o \
      ${../cbits/jni_bridge.c}

    ${ndkCc} -c -fPIC \
      -I${sysroot}/usr/include \
      -I$RTS_INCLUDE \
      -I${../include} \
      -o ui_bridge_android.o \
      ${../cbits/ui_bridge_android.c}

    # Step 2: Copy extra source modules into the writable build directory.
    # GHC writes _stub.h files next to sources, so they can't live in
    # the read-only nix store.
    mkdir -p HaskellMobile
    cp ${../src}/HaskellMobile/Types.hs HaskellMobile/
    cp ${../src}/HaskellMobile/Lifecycle.hs HaskellMobile/
    cp ${../src}/HaskellMobile/App.hs HaskellMobile/
    cp ${../src}/HaskellMobile/Widget.hs HaskellMobile/
    cp ${../src}/HaskellMobile/UIBridge.hs HaskellMobile/
    cp ${../src}/HaskellMobile/Render.hs HaskellMobile/

    # Step 3: Compile Haskell to shared library with cross-GHC.
    # We use --whole-archive to statically link GHC's boot libraries
    # (RTS, base, ghc-prim, etc.) into our .so — Android's linker
    # can't find GHC's separate shared libraries at runtime.
    GHC_PKG_DIR="${ghcPkgDir}"

    # Discover containers library archive (hash varies by GHC version)
    CONTAINERS_LIB=$(find $GHC_PKG_DIR -name "libHScontainers-*.a" | head -1)
    echo "Containers lib: $CONTAINERS_LIB"

    ${ghcCmd} -shared -O2 \
      -o libhaskellmobile.so \
      -DHASKELL_MOBILE_PLATFORM \
      -I${../include} \
      HaskellMobile.hs \
      ${../cbits/android_stubs.c} \
      ${../cbits/platform_log.c} \
      ${../cbits/numa_stubs.c} \
      ${../cbits/ui_bridge.c} \
      -optl-L${androidPkgs.gmp}/lib \
      -optl-L${androidPkgs.libffi}/lib \
      -optl-lffi \
      -optl-llog \
      -optl-Wl,-z,max-page-size=16384 \
      -optl$(pwd)/jni_bridge.o \
      -optl$(pwd)/ui_bridge_android.o \
      -optl-Wl,-u,haskellInit \
      -optl-Wl,-u,haskellGreet \
      -optl-Wl,-u,haskellOnLifecycle \
      -optl-Wl,-u,haskellCreateContext \
      -optl-Wl,-u,haskellRenderUI \
      -optl-Wl,-u,haskellOnUIEvent \
      -optl-Wl,-u,haskellOnUITextChange \
      -optl-Wl,--whole-archive \
      -optl$GHC_PKG_DIR/rts-1.0.2/libHSrts-1.0.2.a \
      -optl$GHC_PKG_DIR/ghc-prim-0.12.0-b5b0/libHSghc-prim-0.12.0-b5b0.a \
      -optl$GHC_PKG_DIR/ghc-bignum-1.3-3be2/libHSghc-bignum-1.3-3be2.a \
      -optl$GHC_PKG_DIR/ghc-internal-9.1003.0-04f5/libHSghc-internal-9.1003.0-04f5.a \
      -optl$GHC_PKG_DIR/base-4.20.2.0-ecb4/libHSbase-4.20.2.0-ecb4.a \
      -optl$GHC_PKG_DIR/integer-gmp-1.1-e5a1/libHSinteger-gmp-1.1-e5a1.a \
      -optl$GHC_PKG_DIR/text-2.1.3-8cdf/libHStext-2.1.3-8cdf.a \
      -optl$GHC_PKG_DIR/array-0.5.8.0-39be/libHSarray-0.5.8.0-39be.a \
      -optl$GHC_PKG_DIR/deepseq-1.5.0.0-dd79/libHSdeepseq-1.5.0.0-dd79.a \
      -optl$CONTAINERS_LIB \
      -optl-Wl,--no-whole-archive
  '';

  installPhase = ''
    mkdir -p $out/lib/arm64-v8a
    cp libhaskellmobile.so $out/lib/arm64-v8a/

    # Bundle runtime dependencies (not provided by Android)
    cp ${androidPkgs.gmp}/lib/libgmp.so $out/lib/arm64-v8a/
    cp ${androidPkgs.libffi}/lib/libffi.so $out/lib/arm64-v8a/
  '';
}
