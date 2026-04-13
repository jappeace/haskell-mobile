# Cross-compile Hackage packages for Android (aarch64 or armv7a).
#
# Uses nixpkgs haskellPackages infrastructure to build packages, then
# collects the results via collect-deps.nix.  The output contains:
#   $out/lib/*.a       — static archives
#   $out/pkgdb/        — GHC package database (.conf + cache)
#
# Template Haskell cross-compilation support (both architectures):
# static iserv-proxy, native libdl, and package DB patching.
# aarch64 additionally gets QEMU guest_base overlay and mmap wrapper
# (for ADRP relocation range issues).
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

  # QEMU overlay for aarch64 TH cross-compilation.
  # Without -B, QEMU uses guest_base=0: guest addresses map directly to
  # host addresses.  The guest binary loads at ~0x200000 where QEMU's own
  # code resides, so mmap hints from GHC's RTS linker are ignored.
  # Loaded .o code lands far from the binary's symbols, exceeding the
  # +-4 GiB range of aarch64 ADRP relocations.
  # -B 0x4000000000 shifts the guest address space by 256 GiB.
  qemuOverlay = final: prev: {
    qemu-user = prev.symlinkJoin {
      name = "qemu-user-with-guest-base";
      paths = [ prev.qemu-user ];
      postBuild = ''
        rm $out/bin/qemu-aarch64
        cat > $out/bin/qemu-aarch64 <<'WRAPPER'
#!/bin/sh
exec ${prev.qemu-user}/bin/qemu-aarch64 -B 0x4000000000 "$@"
WRAPPER
        chmod +x $out/bin/qemu-aarch64
      '';
    };
  };

  pkgs = import nixpkgsSrc ({
    config.allowUnfree = true;
    config.android_sdk.accept_license = true;
  } // (if androidArch == "aarch64"
        then { overlays = [ qemuOverlay ]; }
        else {}));

  # Cross-compilation toolchain
  androidPkgs = pkgs.pkgsCross.${archConfig.crossAttr};

  # --- TH support: static C libraries ---
  # Static versions of C libraries so iserv-proxy-interpreter can be
  # linked statically.  A static binary does not need Android's dynamic
  # linker (/system/bin/linker or linker64), which lets QEMU run it on
  # the build host during TH evaluation.
  gmpStatic = androidPkgs.gmp.overrideAttrs (old: {
    dontDisableStatic = true;
  });
  libffiStatic = androidPkgs.libffi.overrideAttrs (old: {
    dontDisableStatic = true;
  });
  numactlStatic = androidPkgs.numactl.overrideAttrs (old: {
    dontDisableStatic = true;
  });

  # Android NDK ships libdl.a as LLVM bitcode with stub implementations
  # where dlerror() returns "libdl.a is a stub --- use libdl.so instead".
  # GHC's RTS linker can't parse LLVM bitcode as ELF.
  #
  # Fix: provide a native-ELF libdl.a that implements dlopen/dlsym by
  # searching the process's own dynamic symbol table.  Combined with
  # --export-dynamic on iserv-proxy-interpreter, this lets the RTS
  # linker resolve symbols (strlen, ghc-prim, etc.) from the static binary.
  libdlNative = pkgs.runCommand "libdl-native-android" {
    nativeBuildInputs = [ androidPkgs.stdenv.cc ];
  } ''
    ${androidPkgs.stdenv.cc.targetPrefix}clang -c -fPIC -o dl_impl.o ${./th-support/dl_impl.c}
    ${androidPkgs.stdenv.cc.targetPrefix}clang -c -fPIC -o mmap_wrapper.o ${./th-support/mmap_wrapper.c}
    mkdir -p $out/lib
    ${androidPkgs.stdenv.cc.targetPrefix}ar rcs $out/lib/libdl.a dl_impl.o
    ${androidPkgs.stdenv.cc.targetPrefix}ar rcs $out/lib/libmmap_wrapper.a mmap_wrapper.o
  '';

  # --- Haskell package overrides ---

  # vector: test suite uses GHC plugins (inspection-testing), incompatible
  # with cross-compilation's external interpreter.
  vectorOverride = self: super: {
    vector = pkgs.haskell.lib.dontBenchmark (pkgs.haskell.lib.dontCheck super.vector);
  };

  # Template Haskell cross-compilation: package DB patching.
  #
  # Overrides mkDerivation to fix TH evaluation: copies GHC's global
  # package DB entries into the local DB, resolves ${pkgroot} to absolute
  # paths, and clears dynamic-library-dirs to force LoadArchive.
  thPackageDbOverride = self: super: {
    mkDerivation = args:
      let isIservProxy = (args.pname or "") == "iserv-proxy";
      in super.mkDerivation (args // {
        preConfigure = (args.preConfigure or "") +
          (if isIservProxy then "" else ''
            # --- TH cross-compilation fix ---
            # Copy GHC's global package DB entries (rts, base, ghc-prim,
            # etc.) into the local package DB so we can patch them.
            # The local DB shadows the global one.
            _ghcLibDir=$(${self.ghc}/bin/${self.ghc.targetPrefix}ghc --print-libdir)
            _globalConfDir="$_ghcLibDir/package.conf.d"
            if [ -d "$_globalConfDir" ] && [ -d "$packageConfDir" ]; then
              echo "TH-fix: copying global package DB from $_globalConfDir"
              for _conf in "$_globalConfDir"/*.conf; do
                _name=$(basename "$_conf")
                if [ ! -e "$packageConfDir/$_name" ]; then
                  cp "$_conf" "$packageConfDir/$_name"
                fi
              done
              # Patch ALL conf files:
              # 1. Resolve ''${pkgroot} to absolute paths (relative refs
              #    break when boot packages are copied to the local DB)
              # 2. Clear dynamic-library-dirs (forces LoadArchive over
              #    LoadDLL for Haskell .a files)
              # extra-libraries are kept: our dlsym resolves C symbols
              # from the static iserv-proxy-interpreter binary.
              for _conf in "$packageConfDir"/*.conf; do
                ${pkgs.gawk}/bin/awk -v pkgroot="$_ghcLibDir" '
                  { gsub(/\$\{pkgroot\}/, pkgroot) }
                  /^dynamic-library-dirs:/ { print "dynamic-library-dirs:"; skip=1; next }
                  skip && /^[[:space:]]/ { next }
                  { skip=0; print }
                ' "$_conf" > "$_conf.tmp" && mv "$_conf.tmp" "$_conf"
              done
              echo "TH-fix: patched package DB, recaching"
              ${self.ghc}/bin/${self.ghc.targetPrefix}ghc-pkg --package-db="$packageConfDir" recache
              echo "TH-fix: rts include-dirs after patch:"
              grep -A3 "include-dirs" "$packageConfDir"/rts-*.conf || true
            fi
          '');
      });
  };

  # Build iserv-proxy-interpreter as a static binary so QEMU can
  # run it without Android's dynamic linker.
  # --export-dynamic populates .dynsym so our dlsym can find symbols.
  # --hash-style=sysv provides DT_HASH (needed by our dlsym impl);
  #   dl_impl.c also handles DT_GNU_HASH as fallback.
  #
  # aarch64 uses -pie for ASLR compatibility; armv7a uses plain static
  # because ARM32 CRT startup doesn't reliably relocate .dynsym entries
  # in static PIE, causing dlsym to return pre-relocation offsets.
  iservStaticFlags = [
    "--ghc-option=-optl-static"
    "--ghc-option=-optl-Wl,--export-dynamic"
    "--ghc-option=-optl-Wl,--hash-style=sysv"
    "--extra-lib-dirs=${gmpStatic}/lib"
    "--extra-lib-dirs=${libffiStatic}/lib"
    "--extra-lib-dirs=${numactlStatic}/lib"
    "--extra-lib-dirs=${libdlNative}/lib"
  ];

  # aarch64 uses -pie for ASLR.  ARM32 omits it (see above).
  iservPieFlag = [ "--ghc-option=-optl-pie" ];

  # aarch64-only: --wrap=mmap intercepts NULL-hint mmaps from GHC's
  # RTS linker (which uses mmap(NULL,...) on aarch64 due to
  # linkerAlwaysPic=true) and provides hints near the binary so
  # allocations stay within the +-4 GiB ADRP relocation range.
  iservAarch64Flags = [
    "--ghc-option=-optl-Wl,--wrap=mmap"
    "--ghc-option=-optl-lmmap_wrapper"
  ];

  thIservOverride = self: super: {
    iserv-proxy = pkgs.haskell.lib.appendConfigureFlags super.iserv-proxy
      (iservStaticFlags
       ++ (if androidArch == "aarch64"
           then iservPieFlag ++ iservAarch64Flags
           else []));
  };

  # armv7a: disable profiling at the package level — the armv7a cross-GHC
  # is built without profiling boot libraries (enableProfiledLibs = false),
  # so Hackage packages must not request --enable-library-profiling either,
  # or they fail with "Perhaps you haven't installed the profiling libraries
  # for package 'base'".
  armv7aProfilingOverride = self: super: {
    mkDerivation = args: super.mkDerivation (args // {
      enableLibraryProfiling = false;
    });
  };

  defaultOverrides =
    let
      common = pkgs.lib.composeManyExtensions [
        vectorOverride
        thPackageDbOverride
        thIservOverride
      ];
    in
    if androidArch == "aarch64"
    then common
    else pkgs.lib.composeExtensions common armv7aProfilingOverride;

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

  # --- iserv wrapper for consumer-side TH ---
  # Replicates the wrapper pattern from nixpkgs generic-builder.nix so
  # mkAndroidLib can pass -fexternal-interpreter -pgmi <wrapper> to GHC.
  iservHost = crossHaskellPkgs.iserv-proxy;   # target binary (statically linked)
  iservBuild = pkgs.haskellPackages.iserv-proxy; # native build-host binary
  emulatorCmd = if androidArch == "aarch64"
    then "${pkgs.qemu-user}/bin/qemu-aarch64"   # overlay adds -B 0x4000000000
    else "${pkgs.qemu-user}/bin/qemu-arm";

  iservWrapper = pkgs.writeShellScript "iserv-wrapper" ''
    set -euo pipefail
    PORT=$((5000 + RANDOM % 5000))
    (>&2 echo "---> Starting remote interpreter on port $PORT")
    ${emulatorCmd} ${iservHost}/bin/iserv-proxy-interpreter tmp $PORT &
    RISERV_PID="$!"
    trap "kill $RISERV_PID" EXIT
    ${iservBuild}/bin/iserv-proxy "$@" 127.0.0.1 "$PORT"
  '';

in import ./collect-deps.nix {
  inherit pkgs ghc ghcPkgCmd;
  deps = resolvedDeps;
  iservProxy = iservWrapper;
}
