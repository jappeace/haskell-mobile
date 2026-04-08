# Cross-compile Hackage packages for Android (aarch64 or armv7a).
#
# Uses nixpkgs haskellPackages infrastructure to build packages, then
# collects the results via collect-deps.nix.  The output contains:
#   $out/lib/*.a       — static archives
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# Consumers supply their own dependencies via consumerCabalFile (IFD),
# consumerCabal2Nix (pre-generated), or hpkgs overrides.
{ sources
, androidArch ? "aarch64"
, consumerCabalFile ? null
, consumerCabal2Nix ? null
, hpkgs ? (_: _: {})       # consumer haskellPackages overrides
}:
let
  archConfig = {
    aarch64 = { crossAttr = "aarch64-android-prebuilt"; };
    armv7a  = { crossAttr = "armv7a-android-prebuilt"; };
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

  # Cross-compilation toolchain
  androidPkgs = pkgs.pkgsCross.${archConfig.crossAttr};

  # Default overrides needed for cross-compilation:
  # - vector: test suite uses GHC plugins (inspection-testing), incompatible
  #   with cross-compilation's external interpreter.
  defaultOverrides = self: super: {
    vector = pkgs.haskell.lib.dontBenchmark (pkgs.haskell.lib.dontCheck super.vector);
  };

  # armv7a: disable profiling — LLVM ARM backend crashes in
  # ARMAsmPrinter::emitXXStructor when compiling profiled libraries.
  ghcOverride = if androidArch == "armv7a"
    then {
      ghc = androidPkgs.haskellPackages.ghc.override { enableProfiledLibs = false; };
    }
    else {};

  crossHaskellPkgs = androidPkgs.haskellPackages.override ({
    overrides = pkgs.lib.composeExtensions defaultOverrides hpkgs;
  } // ghcOverride);

  ghc = crossHaskellPkgs.ghc;
  ghcPkgCmd = "${ghc}/bin/${ghc.targetPrefix}ghc-pkg";

  resolvedDeps = import ./resolve-deps.nix {
    inherit pkgs consumerCabalFile consumerCabal2Nix;
    haskellPkgs = crossHaskellPkgs;
  };

in import ./collect-deps.nix {
  inherit pkgs ghc ghcPkgCmd;
  deps = resolvedDeps;
}
