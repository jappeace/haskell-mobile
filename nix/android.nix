# Android shared library — thin wrapper around lib.nix.
{ sources ? import ../npins
, mainModule ? ../app/MobileMain.hs
}:
let
  lib = import ./lib.nix { inherit sources; };
  crossDeps = import ./cross-deps.nix { inherit sources; };
in
lib.mkAndroidLib {
  haskellMobileSrc = ../.;
  inherit mainModule crossDeps;
}
