# iOS static library build pipeline.
# Builds Haskell to a single .a using GHC -staticlib, then patches
# Mach-O platform tags from macOS to iOS using mac2ios.
# This is a macOS-only build (same ISA as iOS aarch64).
#
# Uses pre-built GHC from nixpkgs (cache.nixos.org) instead of
# haskell.nix, which tries to build GHC from source and OOMs on
# CI runners with limited RAM.
{ sources ? import ../npins }:
let
  pkgs = import sources.nixpkgs {};

  ghc = pkgs.haskellPackages.ghc;

  mac2ios = import ./mac2ios.nix { inherit sources pkgs; };

in pkgs.stdenv.mkDerivation {
  pname = "haskell-mobile-ios";
  version = "0.1.0.0";

  src = ../src;

  nativeBuildInputs = [ ghc ];
  buildInputs = [ pkgs.libffi ];

  buildPhase = ''
    ghc -staticlib \
      -O2 \
      -o libHaskellMobile.a \
      -optl-lffi \
      -optl-Wl,-u,_haskellInit \
      -optl-Wl,-u,_haskellGreet \
      HaskellMobile.hs
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include
    ${mac2ios}/bin/mac2ios libHaskellMobile.a
    cp libHaskellMobile.a $out/lib/
    cp ${../include/HaskellMobile.h} $out/include/
  '';
}
