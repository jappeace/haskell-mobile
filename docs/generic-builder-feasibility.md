# Can hatter use the generic nixpkgs Haskell builder?

Investigation into whether hatter's custom `stdenv.mkDerivation` for
Android/iOS builds could be replaced by the standard nixpkgs Haskell
builder (`haskellPackages.mkDerivation` / `callCabal2nix`).

**Conclusion**: No.  The custom derivation is the correct approach.
Switching would require ~20 upstream cabal fixes, most of which have
been open for years.

Relates to [#160](https://github.com/jappeace/hatter/issues/160).


## How the build works today

`nix/lib.nix` uses raw `ghc` invocations — not cabal, not
`callCabal2nix`, not `haskellPackages.mkDerivation`.

**Android** (`mkAndroidLib`):
1. NDK clang compiles JNI bridge C files with `-DJNI_PACKAGE`
2. GHC cross-compiler compiles Haskell sources
3. `ghc -shared` links everything into `libhatter.so`, with
   `--whole-archive` for boot packages (RTS, base, ghc-prim) and
   normal linking for everything else

**iOS** (`mkIOSLib`):
1. GHC cross-compiler compiles Haskell sources
2. `ghc -staticlib` produces a static archive
3. `libtool` merges with libgmp
4. `mac2ios` patches Mach-O headers for iOS architecture

**Why not cabal?** Every step above requires capabilities cabal
doesn't have.


## Reasons the generic builder can't work

### 1. Pre-GHC NDK compilation

JNI bridge C files must be compiled by NDK clang *before* GHC runs,
with `-DJNI_PACKAGE=me_jappie_hatter` (or the consumer's package).
Consumer JNI bridges (`extraJniBridge`) are injected at nix-level.

The standard builder compiles C sources as part of cabal's build
phase, using GHC's C compiler — not a separate NDK toolchain.  There
is no cabal mechanism for "compile these C files with a different
compiler before Haskell compilation starts."

### 2. Whole-archive linker control

Boot packages (RTS, base, ghc-prim) must be `--whole-archive`'d into
the `.so` because Android can't find GHC's separate shared libraries
at runtime.  Other packages link normally.

The standard builder passes a single set of `ld-options` to the whole
link phase.  There is no way to toggle `--whole-archive` per-package.

### 3. C bridge separation from Template Haskell

Bridge `.o` files reference Haskell FFI exports (`haskellOnUIEvent`,
`haskellOnUITextChange`) that `iserv-proxy-interpreter` can't resolve.
They must be compiled separately and linked via `-optl`, outside
cabal's dependency graph.

If cabal compiled them as `c-sources`, Template Haskell evaluation
would try to load them and fail.

### 4. iOS `ghc -staticlib` + mac2ios patching

`ghc -staticlib` produces a static archive — a completely different
output format from what nixpkgs' Haskell builder targets.  The
subsequent `libtool` merge and `mac2ios` Mach-O patching are not
expressible in cabal metadata.

### 5. Dynamic library path discovery

Library paths are discovered at build-time via `find` over
hash-suffixed nix store directories.  Boot packages are split into
`lib/` (whole-archived) and `lib-boot/` (normal) directories.  This
runtime configuration isn't expressible in cabal.

### 6. iserv-proxy injection for Template Haskell

Cross-compilation TH requires `-fexternal-interpreter` with a
QEMU-wrapped `iserv-proxy-interpreter` (including a custom guest-base
offset `-B 0x4000000000` to fix ADRP relocation range on aarch64).

Cabal has no concept of build-machine tool dependencies for TH, and no
way to conditionally enable `-fexternal-interpreter` based on whether
the build is cross-compiling.

### 7. Consumer code injection

Hatter builds bundle the consumer's Haskell code into the same shared
library.  Parameters like `consumerCabalFile`, `consumerCabal2Nix`,
`extraJniBridge`, and `consumerExtraDeps` are nix-level — cabal has no
mechanism for a library to absorb and link consumer code at build time.


## Upstream cabal issues that would need fixing

The `foreign-library` stanza was the intended cabal mechanism for
producing standalone shared libraries, but it is incomplete.  The
following open issues would need to be resolved before hatter could
even consider switching.

### Foreign library stanza

These issues make `foreign-library` unusable for producing
self-contained Android `.so` files:

- [#4827](https://github.com/haskell/cabal/issues/4827) —
  **Standalone foreign libraries on Linux**: foreign-libs still require
  GHC's RTS shared libraries at runtime.  This is *the* core blocker —
  hatter's `--whole-archive` pattern exists specifically to work around
  this.
- [#1688](https://github.com/haskell/cabal/issues/1688) —
  **Shared libraries without dynamic dependencies**: no way to build a
  self-contained `.so` that statically links all Haskell deps.
- [#4815](https://github.com/haskell/cabal/issues/4815) —
  **Which RTS to link into a foreign library**: no way to select
  threaded/non-threaded/debug RTS.
- [#8890](https://github.com/haskell/cabal/issues/8890) —
  **Can't `cabal install` a foreign-library**.
- [#4878](https://github.com/haskell/cabal/issues/4878) —
  **`pkgconfig-depends` ignored** in foreign-library stanza.
- [#11297](https://github.com/haskell/cabal/issues/11297) —
  **pkgconfig cflags not passed to c-sources** in foreign-library.
- [#7227](https://github.com/haskell/cabal/issues/7227) —
  **`HookedBuildInfo` doesn't support foreign-library**: build hooks
  can't modify foreign-lib configuration.
- [#4243](https://github.com/haskell/cabal/issues/4243) —
  **foreign-library breaks with `--enable-profiling`**.
- [#6046](https://github.com/haskell/cabal/issues/6046) —
  **`v2-install` doesn't support foreign-library**.
- [#10762](https://github.com/haskell/cabal/issues/10762) —
  **`getDynLibDir` returns wrong path** for foreign libraries.
- [#10763](https://github.com/haskell/cabal/issues/10763) —
  **`list-bin` returns wrong filename** for versioned foreign libraries.

### Cross-compilation

These issues break basic cross-compilation workflows:

- [#1493](https://github.com/haskell/cabal/issues/1493) —
  **Setup.hs compiled with wrong compiler** during cross-compilation.
- [#1988](https://github.com/haskell/cabal/issues/1988) —
  **Cabal tries to build executables for iOS** (impossible on iOS).
- [#5760](https://github.com/haskell/cabal/issues/5760) —
  **Wrong hsc2hs invoked** during cross-compilation.
- [#5887](https://github.com/haskell/cabal/issues/5887) —
  **Incorrect `--host=`** passed to `./configure`.
- [#7038](https://github.com/haskell/cabal/issues/7038) —
  **`--target=` not passed** to `./configure`.
- [#9321](https://github.com/haskell/cabal/issues/9321) —
  **No conditional for detecting cross-compilation** in `.cabal` files.
- [#2517](https://github.com/haskell/cabal/issues/2517) —
  **Can't specify OS version** (e.g. iOS deployment target).

### Template Haskell + external interpreter

- [#5411](https://github.com/haskell/cabal/issues/5411) —
  **No `run-tool-depends`** for declaring build-machine tools
  (iserv-proxy).
- [#9321](https://github.com/haskell/cabal/issues/9321) —
  **Can't conditionally disable TH** when cross-compiling (same issue
  as above, different consequence).

### Build hooks / custom C compilation

These issues prevent integrating NDK toolchain invocations into cabal:

- [#10791](https://github.com/haskell/cabal/issues/10791) —
  **Setup hooks can't produce library artifacts** (`.a`/`.so`).
- [#11607](https://github.com/haskell/cabal/issues/11607) —
  **Pre-build rules can't generate extra source files**.
- [#7350](https://github.com/haskell/cabal/issues/7350) —
  **No per-component build hooks**.
- [#10552](https://github.com/haskell/cabal/issues/10552) —
  **No per-file compiler options** (NDK clang vs host GCC need
  different flags for different files).
- [#4435](https://github.com/haskell/cabal/issues/4435) —
  **cc-options not passed to GHC**.
- [#9801](https://github.com/haskell/cabal/issues/9801) —
  **cc-options ignored for Haskell sources** with inline C.
- [#4937](https://github.com/haskell/cabal/issues/4937) —
  **C sources not recompiled** when cc-options change.
- [#696](https://github.com/haskell/cabal/issues/696) —
  **Foreign code in Haskell libraries**: foundational design issue.

### Linker control

- [#10789](https://github.com/haskell/cabal/issues/10789) —
  **Inconsistent `ld-options` application** between library and
  executable linking (breaks `--whole-archive`).
- [#11224](https://github.com/haskell/cabal/issues/11224) —
  **`extra-libraries-static` of deps ignored** when linking statically.
- [#9263](https://github.com/haskell/cabal/issues/9263) —
  **`extra-bundled-libraries` confusion**.
- [#8701](https://github.com/haskell/cabal/issues/8701) —
  **`extra-bundled-libraries` placed in wrong search path**.
- [#8826](https://github.com/haskell/cabal/issues/8826) —
  **`extra-bundled-libraries` not found** even when present.

### Shared library output

- [#747](https://github.com/haskell/cabal/issues/747) —
  **First-class `.so`/`.dylib` support** from Haskell code.
- [#7377](https://github.com/haskell/cabal/issues/7377) —
  **Dynamic `.dyn_o` files always built** even when only static is
  requested.
- [#2715](https://github.com/haskell/cabal/issues/2715) —
  **macOS shared libraries miss framework deps** and custom ld flags.


## Summary

| Requirement | Standard builder | Custom derivation |
|---|---|---|
| NDK clang compilation | No | Yes |
| JNI bridge injection | No | Yes |
| `--whole-archive` per-package | No | Yes |
| Consumer code injection | No | Yes |
| Dynamic library discovery | No | Yes |
| iserv-proxy wrapper | No | Yes |
| C bridge / TH separation | No | Yes |
| iOS `-staticlib` + mac2ios | No | Yes |

The custom derivation is the right tool.  The alternative would be
patching cabal to support Android/iOS shared library targets with JNI
bridge injection — which is essentially what hatter's nix build
already *is*: a cabal replacement for the cross-compilation link phase.

This could be revisited if cabal's `foreign-library` stanza matures
(especially #4827 and #1688), but those issues have been open since
2017 with no movement.
