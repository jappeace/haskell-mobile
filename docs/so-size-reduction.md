# Shared Library Size Reduction

Analysis of the `libhatter.so` size and concrete strategies to reduce it for Android APKs (and by extension, iOS/watchOS static libraries).

---

## Current State

The counter demo app produces a `.so` of **~80 MB** (after `--strip-debug`). For a minimal counter app this is large — Flutter equivalents ship at ~5-8 MB. The CI size guard in `emulator-all.nix` hard-fails at 120 MB, and `mkAndroidLib` warns at 200 MB (configurable via `soMaxSizeMB`).

### Why it's large

Three factors dominate:

1. **`--whole-archive` on 12 boot packages.** Lines 444-456 of `lib.nix` link rts, ghc-prim, ghc-bignum, ghc-internal, base, integer-gmp, text, array, deepseq, containers, transformers, and time with `--whole-archive`. This forces every object file from every archive into the `.so`, regardless of whether any symbols are referenced.

2. **No section-level garbage collection.** GHC emits one ELF section per module by default. Even with `--gc-sections`, the linker can only discard entire modules, not individual functions. Without `-split-sections`, unreferenced functions within a used module are included unconditionally.

3. **Consumer deps are also whole-archived.** Line 458 whole-archives all `.a` files from `crossDeps/lib/`, meaning every consumer dependency (e.g. sqlite-simple, aeson) is fully included regardless of actual usage.

The post-mortem in `ci-ram-regression-110.md` documents the extreme case: when boot package archives accidentally landed in the whole-archive group, the `.so` ballooned to 373 MB.

---

## Proposed Optimisations

### 1. `-split-sections` + `--gc-sections`

**Estimated reduction: 40-60%**

GHC's `-split-sections` flag places each top-level Haskell binding (function, data constructor, type class dictionary) into its own ELF section. The linker's `--gc-sections` pass then traces from the entry points (the `-u` exported symbols) and discards every section that isn't reachable.

This is the single highest-impact change because it directly counteracts `--whole-archive`: even though every object file is pulled in, unreferenced *sections within* those objects are garbage-collected.

**Required changes in `lib.nix` `mkAndroidLib`:**

```nix
# Add -split-sections to GHC invocation (line 372):
${ghcCmd} -shared -O2 -split-sections \
  ...
  -optl-Wl,--gc-sections \
```

**Considerations:**

- The cross-GHC must support `-split-sections` on the target. Most nixpkgs GHC builds for ELF targets (including aarch64-linux-android) have this enabled. Verify with `ghc --supported-extensions | grep SplitSections` or check if `ghc --info` shows `"Target has subsections via symbols" -> "YES"`.
- Compilation time increases modestly (more relocations for the assembler/linker to process).
- The cabal file's `-O2` should also gain `-split-sections` so that the library's own `.a` benefits when linked.

**Applicability to iOS/watchOS:** Apple's linker (`ld64`) uses `-dead_strip` instead of `--gc-sections`, and GHC uses `-ffunction-sections -fdata-sections` via the LLVM backend. The iOS/watchOS builders in `mkIOSLib`/`mkWatchOSLib` would need analogous changes:

```nix
ghc -staticlib -O2 -split-sections ... -optl-Wl,-dead_strip
```

---

### 2. Reduce the `--whole-archive` set

**Estimated reduction: 10-30%**

Only the **RTS** truly requires `--whole-archive`. The RTS contains constructor/destructor tables, weak symbols, and `__stginit` module initialisers that are referenced indirectly (via info tables and the storage manager) rather than through normal symbol references. Without `--whole-archive`, the linker would discard these and the runtime would crash at startup.

The remaining 11 boot packages — ghc-prim, ghc-bignum, ghc-internal, base, integer-gmp, text, array, deepseq, containers, transformers, time — are regular Haskell libraries. Their symbols are referenced through normal call chains and do not need forced inclusion.

**Proposed link order in `lib.nix`:**

```nix
# Whole-archive only what truly needs it:
-optl-Wl,--whole-archive \
-optl$RTS_LIB \
-optl-Wl,--no-whole-archive \

# Normal linking for remaining boot packages:
-optl$GHC_PRIM_LIB \
-optl$GHC_BIGNUM_LIB \
-optl$GHC_INTERNAL_LIB \
-optl$BASE_LIB \
-optl$INTEGER_GMP_LIB \
-optl$TEXT_LIB \
-optl$ARRAY_LIB \
-optl$DEEPSEQ_LIB \
-optl$CONTAINERS_LIB \
-optl$TRANSFORMERS_LIB \
-optl$TIME_LIB \

# Consumer deps (also no longer whole-archived):
$(for a in ${crossDeps}/lib/*.a; do echo -n "-optl$a "; done)
$(for a in ${crossDeps}/lib-boot/*.a; do echo -n "-optl$a "; done)
```

**Risk:** GHC's `__stginit` module initialisers in ghc-prim, ghc-internal, and base may require whole-archive. If the app crashes at startup with missing `__stginit` symbols, add those three back into the whole-archive group:

```nix
-optl-Wl,--whole-archive \
-optl$RTS_LIB \
-optl$GHC_PRIM_LIB \
-optl$GHC_INTERNAL_LIB \
-optl$BASE_LIB \
-optl-Wl,--no-whole-archive \
```

This still saves the bulk of the reduction by removing text, containers, deepseq, array, transformers, time, ghc-bignum, and integer-gmp from whole-archive.

**Testing strategy:** Build the counter app with the reduced whole-archive set and run it on the emulator. If it starts and the counter works, the minimal set is correct. If it crashes, check `adb logcat` for missing symbol errors and add the relevant package back.

---

### 3. Linker version script (export only JNI symbols)

**Estimated reduction: 5-15%**

The `.so` currently exports its full symbol table. Only the `haskell*` JNI entry points (listed as `-u` flags on lines 423-441 of `lib.nix`) need to be visible to the Android runtime. Everything else can be marked `local`, allowing the linker to:

- Discard symbol table entries (smaller `.dynsym`)
- Inline or merge functions that were only kept because they were exported
- Apply more aggressive `--gc-sections` (local symbols have no external references to preserve)

**Implementation:**

Create a version script file at `nix/exports.map`:

```
{
  global:
    haskellRunMain;
    haskellOnLifecycle;
    haskellRenderUI;
    haskellOnUIEvent;
    haskellOnUITextChange;
    haskellOnPermissionResult;
    haskellOnSecureStorageResult;
    haskellOnBleScanResult;
    haskellOnDialogResult;
    haskellOnLocationUpdate;
    haskellOnAuthSessionResult;
    haskellOnPlatformSignInResult;
    haskellOnCameraResult;
    haskellOnVideoFrame;
    haskellOnAudioChunk;
    haskellOnBottomSheetResult;
    haskellOnHttpResult;
    haskellOnNetworkStatusChange;
    haskellLogLocale;
    JNI_OnLoad;
  local:
    *;
};
```

Add to the GHC link flags:

```nix
-optl-Wl,--version-script=${./exports.map}
```

**Note:** Consumer apps that add extra JNI exports would need to provide their own version script or extend this one. The `extraJniBridge` parameter could be extended to also accept extra export symbols.

---

### 4. `--strip-all` instead of `--strip-debug`

**Estimated reduction: 5-10%**

The install phase (line 481) uses `llvm-strip --strip-debug`, which removes DWARF debug info but preserves the `.symtab` symbol table. Since the version script (optimisation 3) already controls dynamic visibility, the static symbol table serves no purpose in a release build.

**Change in `lib.nix`:**

```nix
# Was: llvm-strip --strip-debug
${ndk}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip \
  --strip-all $out/lib/${archConfig.abiDir}/${soName}
```

If the version script is not adopted, `--strip-unneeded` is a safer middle ground — it strips symbols not needed for relocation but preserves dynamic symbols.

---

### 5. `-Os` instead of `-O2`

**Estimated reduction: 10-20%**

GHC's `-O2` enables aggressive inlining, specialisation, and unfolding that increases code size. `-Os` (available since GHC 9.2) optimises for code size: less inlining, smaller unfoldings, and more compact code generation.

For mobile apps where startup latency and memory footprint matter more than peak throughput, `-Os` is typically the better tradeoff.

**Changes:**

In `hatter.cabal`:

```cabal
ghc-options:
  -Os -Wall -Werror ...
```

In `lib.nix` line 372:

```nix
${ghcCmd} -shared -Os -split-sections \
```

**Consideration:** This affects the framework library only. Consumer apps control their own optimisation level in their cabal file. Document that consumers should also use `-Os` for best results.

---

### 6. Native bignum backend (drop `libgmp.so`)

**Estimated reduction: removes `libgmp.so` (~1 MB)**

The install phase bundles `libgmp.so` as a runtime dependency. GHC 9.x's `ghc-bignum` package supports a native Haskell backend that eliminates the GMP dependency entirely. Unless the app performs heavy arbitrary-precision arithmetic, the native backend is functionally equivalent.

**Implementation:** Rebuild the cross-GHC with `ghc-bignum` configured to use the native backend. This is a nixpkgs-level change:

```nix
haskell.compiler.ghc98.override {
  enableNativeBignum = true;
}
```

This also removes the `-optl-L${androidPkgs.gmp}/lib` flag and the `libgmp.so` copy in the install phase.

**Risk:** Low for typical mobile apps. High for apps that depend on fast bignum (cryptography libraries, etc.).

---

## Summary

| # | Optimisation | Est. reduction | Effort | Risk |
|---|---|---|---|---|
| 1 | `-split-sections` + `--gc-sections` | 40-60% | Low | Low |
| 2 | Reduce `--whole-archive` set | 10-30% | Low | Medium |
| 3 | Linker version script | 5-15% | Low | Low |
| 4 | `--strip-all` | 5-10% | Trivial | Low |
| 5 | `-Os` instead of `-O2` | 10-20% | Trivial | Low |
| 6 | Native bignum backend | ~1 MB | High | Low |

Optimisations 1 + 2 are the highest priority and could realistically bring the counter app `.so` from ~80 MB down to ~25-35 MB. Adding 3-5 could push it further to ~15-25 MB.

These estimates are cumulative but not strictly additive — `-split-sections` + `--gc-sections` partially overlaps with reducing the whole-archive set, since gc-sections recovers some of the same dead code that whole-archive forced in.

---

## Measurement

To measure the impact of each change independently, build the counter app `.so` and compare:

```bash
# Before/after sizes (printed by mkAndroidLib install phase):
# "Stripped: X MB -> Y MB"

# Detailed section breakdown:
llvm-readelf -S libhatter.so | sort -k6 -rn | head -20

# Symbol count:
llvm-nm --defined-only libhatter.so | wc -l

# Top space consumers by object file origin:
llvm-nm --print-size --size-sort -r libhatter.so | head -50
```
