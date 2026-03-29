# iOS static library build pipeline.
# Builds Haskell to a single .a using GHC -staticlib, then patches
# Mach-O platform tags from macOS to iOS using mac2ios.
# This is a macOS-only build (same ISA as iOS aarch64).
#
# Uses pre-built GHC from nixpkgs (cache.nixos.org) instead of
# haskell.nix, which tries to build GHC from source and OOMs on
# CI runners with limited RAM.
# mainModule: path to the user's Main.hs.
# The user writes a plain main :: IO () that calls runMobileApp.
# No foreign export ccall needed — the C bridge calls main via
# the GHC RTS API (rts_evalLazyIO on ZCMain_main_closure).
{ sources ? import ../npins
, simulator ? false
, mainModule ? ../app/MobileMain.hs
}:
let
  pkgs = import sources.nixpkgs {};

  ghc = pkgs.haskellPackages.ghc;

  mac2ios = import ./mac2ios.nix { inherit sources pkgs; };

  # Need static libgmp.a for merging into the iOS static library.
  # Default macOS nix gmp only builds shared; override to include static.
  gmpStatic = pkgs.gmp.overrideAttrs (old: {
    dontDisableStatic = true;
  });

in pkgs.stdenv.mkDerivation {
  pname = "haskell-mobile-ios";
  version = "0.1.0.0";

  src = ../src;

  nativeBuildInputs = [ ghc pkgs.cctools ];
  buildInputs = [ pkgs.libffi gmpStatic ];

  buildPhase = ''
    # Copy extra source modules into the writable build directory.
    # GHC writes _stub.h files next to sources, so they can't live in
    # the read-only nix store.
    mkdir -p HaskellMobile
    cp ${../src}/HaskellMobile/Types.hs HaskellMobile/
    cp ${../src}/HaskellMobile/Lifecycle.hs HaskellMobile/
    cp ${../src}/HaskellMobile/App.hs HaskellMobile/
    cp ${../src}/HaskellMobile/Widget.hs HaskellMobile/
    cp ${../src}/HaskellMobile/UIBridge.hs HaskellMobile/
    cp ${../src}/HaskellMobile/Render.hs HaskellMobile/

    # Copy user entry point (plain main :: IO (), no foreign export needed)
    cp ${mainModule} Main.hs

    ghc -staticlib \
      -O2 \
      -o libHaskellMobile.a \
      -I${../include} \
      -optl-lffi \
      -optl-Wl,-u,_haskellRunMain \
      -optl-Wl,-u,_haskellGreet \
      -optl-Wl,-u,_haskellOnLifecycle \
      -optl-Wl,-u,_haskellCreateContext \
      -optl-Wl,-u,_haskellRenderUI \
      -optl-Wl,-u,_haskellOnUIEvent \
      ${../cbits/platform_log.c} \
      ${../cbits/ui_bridge.c} \
      ${../cbits/run_main.c} \
      Main.hs \
      HaskellMobile.hs
  '';

  installPhase = ''
    mkdir -p $out/lib $out/include

    # Merge libgmp.a into the Haskell static library so downstream
    # consumers don't need to link libgmp separately.
    echo "Merging libgmp.a into libHaskellMobile.a"
    libtool -static -o libCombined.a libHaskellMobile.a ${gmpStatic}/lib/libgmp.a
    mv libCombined.a libHaskellMobile.a

    ${mac2ios}/bin/mac2ios ${if simulator then "-s" else ""} libHaskellMobile.a
    cp libHaskellMobile.a $out/lib/
    cp ${../include/HaskellMobile.h} $out/include/HaskellMobile.h
    cp ${../include/UIBridge.h} $out/include/UIBridge.h
  '';
}
