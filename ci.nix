{
  native = import ./default.nix {};
  android = (import ./nix/android.nix {}).lib;
}
