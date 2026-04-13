# Staged watchOS simulator app — thin wrapper around lib.nix.
{ sources ? import ../npins }:
let
  lib = import ./lib.nix { inherit sources; };
  watchosLib = import ./watchos.nix { inherit sources; simulator = true; };
in
lib.mkWatchOSSimulatorApp {
  inherit watchosLib;
  watchosSrc = ../watchos;
  name = "hatter-watchos-simulator-app";
}
