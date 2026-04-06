# Android shared library — thin wrapper around lib.nix.
{ sources ? import ../npins
, androidArch ? "aarch64"
, mainModule ? ../app/MobileMain.hs
, consumerCabalFile ? null
, consumerCabal2Nix ? null
}:
let
  lib = import ./lib.nix { inherit sources androidArch; };
  crossDeps = import ./cross-deps.nix {
    inherit sources androidArch consumerCabalFile consumerCabal2Nix;
  };
in
lib.mkAndroidLib {
  haskellMobileSrc = ../.;
  inherit mainModule crossDeps;
}
