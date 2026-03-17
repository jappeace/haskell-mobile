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

    # Step 1: Compile JNI bridge with NDK clang
    ${ndkCc} -c -fPIC \
      -I${sysroot}/usr/include \
      -I$RTS_INCLUDE \
      -o jni_bridge.o \
      ${../cbits/jni_bridge.c}

    # Step 2: Compile Haskell to shared library with cross-GHC
    ${ghcCmd} -shared -O2 \
      -o libhaskellmobile.so \
      HaskellMobile.hs \
      ${../cbits/android_stubs.c} \
      -optl-L${androidPkgs.gmp}/lib \
      -optl-L${androidPkgs.libffi}/lib \
      -optl-lffi \
      -optl-Wl,-z,max-page-size=16384 \
      -optl$(pwd)/jni_bridge.o \
      -optl-Wl,-u,haskellInit \
      -optl-Wl,-u,haskellGreet
  '';

  installPhase = ''
    mkdir -p $out/lib/arm64-v8a
    cp libhaskellmobile.so $out/lib/arm64-v8a/
  '';
}
