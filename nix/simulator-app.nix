# Staged iOS simulator app — thin wrapper around lib.nix.
{ sources ? import ../npins }:
let
  lib = import ./lib.nix { inherit sources; };
  iosLib = import ./ios.nix { inherit sources; simulator = true; };
in
lib.mkSimulatorApp {
  inherit iosLib;
  iosSrc = ../ios;
  name = "hatter-simulator-app";
}
