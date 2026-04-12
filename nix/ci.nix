{ sources ? import ../npins }:
let
  isDarwin = builtins.currentSystem == "aarch64-darwin"
          || builtins.currentSystem == "x86_64-darwin";
  pkgs = import sources.nixpkgs {};

  # Compilation and link-test targets.
  # New targets added here are automatically picked up by `all-builds`.
  buildTargets = {
    native = import ../default.nix {};
    android-aarch64 = import ./android.nix { inherit sources; };
    android-armv7a = import ./android.nix { inherit sources; androidArch = "armv7a"; };
    apk = import ./apk.nix { inherit sources; };
    consumer-link-test = import ./test-link-consumer.nix { inherit sources; };
    consumer-deps-test = import ./test-consumer-deps.nix { inherit sources; };
    th-test = import ./test-th.nix { inherit sources; };
    readme-example = import ./test-readme-example.nix { inherit sources; };
    th-direct-test = import ./test-th-direct.nix { inherit sources; };
  } // (if isDarwin then {
    ios-lib = import ./ios.nix { inherit sources; };
    watchos-lib = import ./watchos.nix { inherit sources; };
  } else {});

  # Emulator/simulator test runners — heavy (include system images),
  # need dedicated CI jobs with enough disk space.
  testRunners = {
    emulator-all = import ./emulator-all.nix { inherit sources; };
    emulator-armv7a = import ./emulator-all.nix {
      inherit sources; androidArch = "armv7a";
    };
  } // (if isDarwin then {
    simulator-all = import ./simulator-all.nix { inherit sources; };
    watchos-simulator-all = import ./watchos-simulator-all.nix {
      inherit sources;
    };
  } else {});

  # Known-failing targets: documented upstream issues, not included in
  # all-builds but available for manual testing.
  #
  # th-direct-test-armv7a: Template Haskell on armv7a crashes with SIGSEGV
  # in GHC's RTS linker during GC (heap closure has invalid info pointer).
  # Root cause: GHC's ARM32 RTS linker is broken with per-function ELF
  # sections (LLVM -ffunction-sections) in statically-linked iserv
  # (GHC #14291, haskell.nix #1544).  ARM32 support is effectively
  # abandoned in GHC — GHCup dropped it, haskell.nix closed as wontfix.
  # Regular armv7a cross-compilation (without TH) works fine.
  knownFailing = {
    th-direct-test-armv7a = import ./test-th-direct.nix { inherit sources; androidArch = "armv7a"; };
  };

  testScripts = builtins.path { path = ../test; name = "test-scripts"; };

in
  buildTargets // testRunners // knownFailing // {
    # Meta-target: builds every compilation/link-test target.
    # Excludes emulator/simulator runners (they have dedicated CI jobs).
    # Adding a new attr to buildTargets automatically includes it here.
    all-builds = pkgs.runCommand "ci-all-builds" {} ''
      mkdir -p $out
      ${builtins.concatStringsSep "\n" (
        builtins.map (name: "ln -s ${buildTargets.${name}} $out/${name}")
          (builtins.attrNames buildTargets)
      )}
    '';

    # Lint all test shell scripts with shellcheck.
    shellcheck = pkgs.runCommand "ci-shellcheck" {
      nativeBuildInputs = [ pkgs.shellcheck ];
    } ''
      shellcheck -x \
        --source-path=${testScripts}/android \
        ${testScripts}/android/*.sh
      shellcheck -x \
        --source-path=${testScripts}/ios \
        ${testScripts}/ios/*.sh
      shellcheck -x \
        --source-path=${testScripts}/watchos \
        ${testScripts}/watchos/*.sh
      echo "All shell scripts passed shellcheck."
      touch $out
    '';
  }
