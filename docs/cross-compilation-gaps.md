# Why Haskell-Mobile Needs Nix Hacks: What Cabal Is Missing

## Executive Summary

The hatter project uses **~20 distinct workarounds** in its Nix build system to cross-compile Haskell to Android, iOS, and watchOS. These fall into categories that reveal fundamental gaps in both GHC and Cabal's cross-compilation story. The core problem: **Cabal was designed for native builds and has never been seriously adapted for mobile cross-compilation**.

---

## The 6 Most Pressing Issues

### 1. `--with-PROG` Not Propagated to Dependencies ([cabal#4939](https://github.com/haskell/cabal/issues/4939))

**The hack:** Nix creates symlink farms (`ln -s cross-ghc $TMPDIR/cross-bin/ghc`) and patches `build-tool-depends: hsc2hs` out of every dependency's `.cabal` file with `sed`.

**The problem:** When you set `--with-hsc2hs=/path/to/cross-hsc2hs` or `--hsc2hs-options=--cross-compile`, cabal applies these **only to your local package**, not to dependencies. Every dependency that uses `.hsc` files silently uses the wrong `hsc2hs`.

**What cabal needs:** A `--cross-prefix` flag or automatic propagation of tool overrides to all transitive dependencies. This was reported in 2018 and called "utterly unusable for cross-compilation."

### 2. `Setup.hs` Compiled with Cross-Compiler ([cabal#1493](https://github.com/haskell/cabal/issues/1493), [cabal#2085](https://github.com/haskell/cabal/issues/2085))

**The hack:** hatter only works because its dependencies happen to use `build-type: Simple`. If any dependency used `build-type: Custom`, the build would fail entirely.

**The problem:** Cabal compiles `Setup.hs` with whatever GHC is configured. If that's a cross-compiler, the resulting `Setup` binary targets ARM and can't run on the x86 build machine. There is no `--with-build-ghc` flag.

**What cabal needs:** Distinguish between "build machine GHC" (for running Setup.hs, hsc2hs, etc.) and "target GHC" (for compiling the actual library). This is the single biggest architectural gap.

### 3. No Standalone `foreign-library` on Non-Windows ([cabal#6097](https://github.com/haskell/cabal/issues/6097))

**The hack:** Nix bypasses cabal entirely for the linking step. It manually discovers all GHC boot library `.a` files via `find`, then links them with `--whole-archive` into a single `.so` (Android) or merges them with `libtool -static` into a single `.a` (iOS).

**The problem:** Cabal's `foreign-library` stanza supports a `standalone` option that bundles the RTS, but it **only works on Windows**. On Android/iOS, the produced library has dangling dependencies on GHC's shared libraries, which don't exist on the device.

**What cabal needs:** `standalone` support on all platforms. On Android, this means `--whole-archive` linking of boot libs into one `.so`. On iOS, it means `libtool -static` merging into one `.a`. This is the #1 feature that would eliminate the most Nix code.

### 4. No Way to Bundle Runtime Dependencies

**The hack:** Nix manually copies `libgmp.so` and `libffi.so` from the cross-compilation sysroot into the APK's `lib/` directory.

**The problem:** GHC depends on libgmp and libffi at runtime, but Android doesn't provide them. Cabal has no concept of "runtime dependencies that must be shipped alongside the output." It assumes the target system has these libraries.

**What cabal needs:** A `bundle-libs` or `runtime-deps` field that specifies shared libraries to include in the output. Or, better yet: static linking of gmp/ffi into the RTS when targeting mobile (GHC-level fix).

### 5. FFI Exports Silently Dropped by Linker

**The hack:** Nix passes `-Wl,-u,haskellRunMain -Wl,-u,haskellOnLifecycle ...` for every single FFI export symbol -- 9 symbols manually listed.

**The problem:** GHC's `foreign export ccall` produces C-callable symbols, but the linker sees no references to them (they're called from JNI/ObjC at runtime, not from Haskell). The linker garbage-collects them as "unreferenced." Every new FFI export requires updating the Nix build with another `-Wl,-u` flag.

**What cabal needs:** Automatic detection and preservation of `foreign export` symbols. When building a `foreign-library`, cabal/GHC should emit a linker script or use `--export-dynamic` to keep all FFI exports alive.

### 6. Mach-O Platform Tag Rewriting (mac2ios / mac2watchos)

**The hack:** hatter includes two custom C programs (`mac2ios.c`, `mac2watchos.c`) that parse Mach-O binaries and rewrite `LC_BUILD_VERSION` from `PLATFORM_MACOS` to `PLATFORM_IOS` or `PLATFORM_WATCHOS`. Every compiled `.a` file goes through this binary patching.

**The problem:** GHC on macOS always produces macOS-tagged binaries, even when the output is intended for iOS/watchOS. Apple's Xcode linker rejects macOS-tagged objects when building iOS apps.

**What GHC needs:** A `-fplatform-ios` / `-fplatform-watchos` flag, or proper cross-compilation target triples (`aarch64-apple-ios`, `aarch64-apple-watchos`) that emit the correct platform tags. This is a GHC issue, not cabal.

---

## Additional Hacks (Less Critical but Still Painful)

| Hack | What It Does | Root Cause |
|------|-------------|------------|
| Source copy to writable dir | Copies all `.hs`/`.c` files out of Nix store | GHC writes `_stub.h` next to sources; read-only stores break this |
| NUMA stubs (`numa_stubs.c`) | Provides fake `numa_available()` etc. | GHC RTS references libnuma; Android lacks it |
| Android libc stubs (`android_stubs.c`) | Stubs for `__svfscanf`, `__vfwscanf` | GHC RTS references GNU libc symbols absent from bionic |
| `run_main.c` wrapper | Calls `rts_evalLazyIO(ZCMain_main_closure)` | No standard C entry point for Haskell `main` in shared lib mode |
| ARM page size (`-Wl,-z,max-page-size=16384`) | Sets correct 16KB page alignment | GHC/linker defaults to 4KB; ARM uses 16KB |
| Library discovery via `find` | Searches `$GHC_PKG_DIR` for `libHS*.a` by glob | Library names have hash suffixes; no API to query paths |
| armv7a profiling disabled | `enableProfiledLibs = false` for 32-bit ARM | LLVM ARM32 backend crashes on profiled code |
| compiler-rt patches | 4 separate patches to nixpkgs compiler-rt | armv7a not recognized as valid ARM32 arch |
| boot package hardcoding | List of 15 packages to exclude from cross-build | No `ghc-pkg --boot-packages` query |
| `project.yml` Python patching | Injects `OTHER_CFLAGS` into Xcode config | No way to pass C flags through cabal to Xcode |
| Two-stage NDK compilation | JNI bridge compiled by NDK clang, not GHC | GHC's C compiler doesn't know about JNI headers |
| cabal2nix spy derivation | Extracts deps without building | No `cabal plan --to-json` for dependency info |

---

## What's Improving

### ghc-toolchain (GHC 9.10+, not yet default)

Replaces the 10,000-line `./configure` script. Long-term goal: **runtime-retargetable GHC** where one GHC can target multiple platforms via `ghc --target=aarch64-linux-android`. This would eliminate needing separate cross-compiler builds. Status: shipping but not default; full retargetability is years out.

- [Well-Typed blog post](https://well-typed.com/blog/2023/10/improving-ghc-configuration-and-cross-compilation-with-ghc-toolchain/)
- [GHC #11470 - Runtime retargetable cross-compilation](https://gitlab.haskell.org/ghc/ghc/-/issues/11470)

### Explicit Level Imports (GHC 9.14)

[Proposal #682](https://ghc-proposals.readthedocs.io/en/latest/proposals/0682-explicit-level-imports.html) -- distinguishes compile-time imports from runtime imports, reducing the scope of Template Haskell cross-compilation problems.

---

## Template Haskell and Cross-Compilation

Template Haskell splices execute code at compile time on the **build machine**, but when cross-compiling, the code targets the **target machine** and can't run locally.

**Current workaround:** GHC's `-fexternal-interpreter` with `iserv-proxy` + `remote-iserv`, delegating TH evaluation to an emulator (QEMU for Android, iOS Simulator for iOS). This works but is slow and fragile.

**hatter's approach:** Avoid TH entirely. The project and its dependencies don't use Template Haskell, sidestepping the problem. This limits which Hackage packages can be used as dependencies.

---

## Reference Implementations

### SimpleX Chat

The most prominent production Haskell app on Android/iOS. Uses **haskell.nix** (not plain nixpkgs) for cross-compilation infrastructure. Ships `libsimplex.so` via `ghc -shared` with static linking. Maintains custom forks of several Hackage packages for Android compatibility.

### hatter (this project)

Uses **plain nixpkgs** (not haskell.nix) with `pkgsCross.aarch64-android-prebuilt`. Simpler but requires more manual workarounds. The Nix code in `nix/lib.nix` is essentially a hand-written cross-compilation build system.

---

## Priority Ranking: What Would Help hatter Most

1. **`foreign-library standalone` on all platforms** -- eliminates the entire `--whole-archive` / `libtool -static` / boot library discovery machinery (~40% of Nix build code)
2. **Build/host tool distinction in cabal** -- eliminates `Setup.hs` problem and `hsc2hs` propagation hacks
3. **FFI export preservation** -- eliminates manual `-Wl,-u` symbol lists
4. **GHC iOS/watchOS platform tags** -- eliminates mac2ios/mac2watchos binary patchers
5. **GHC `--without-numa` for mobile targets** -- eliminates NUMA/libc stubs
6. **`cabal plan --to-json`** -- eliminates cabal2nix spy derivation for dependency resolution
7. **Runtime dependency bundling** -- eliminates manual libgmp/libffi copying

---

## Key References

- [Cabal #4939 - new-build unusable for cross-compilation](https://github.com/haskell/cabal/issues/4939)
- [Cabal #1493 - Setup.hs with local compiler](https://github.com/haskell/cabal/issues/1493)
- [Cabal #2085 - Avoid compiling setup for cross](https://github.com/haskell/cabal/issues/2085)
- [Cabal #9321 - Cross-compilation conditional](https://github.com/haskell/cabal/issues/9321)
- [Cabal #5887 - Incorrect --host=](https://github.com/haskell/cabal/issues/5887)
- [Cabal #9222 - extra-lib-dirs not propagated](https://github.com/haskell/cabal/issues/9222)
- [Cabal #6097 - -staticlib for Android](https://github.com/haskell/cabal/issues/6097)
- [GHC #10324 - Shared library tricks don't work on Android](https://gitlab.haskell.org/ghc/ghc/-/issues/10324)
- [GHC #11470 - Runtime retargetable cross-compilation](https://gitlab.haskell.org/ghc/ghc/-/issues/11470)
- [GHC Proposal #682 - Explicit Level Imports](https://ghc-proposals.readthedocs.io/en/latest/proposals/0682-explicit-level-imports.html)
- [zw3rk: The Haskell Cabal and Cross Compilation](https://medium.com/@zw3rk/the-haskell-cabal-and-cross-compilation-e9885fd5e2f)
- [zw3rk: Haskell Cross Compiler for Android](https://medium.com/@zw3rk/a-haskell-cross-compiler-for-android-8e297cb74e8a)
- [zw3rk: Haskell Cross Compiler for iOS](https://medium.com/@zw3rk/a-haskell-cross-compiler-for-ios-7cc009abe208)
- [Cabal foreign-library discussion (Discourse)](https://discourse.haskell.org/t/cabals-foreign-library-stanza/6516)

---

## Conclusion

**Nix is doing the job of a cross-compilation-aware build system because cabal isn't one.** Every hack in hatter exists because cabal assumes you're building natively and GHC assumes the target has a full POSIX environment. The most impactful single change would be making `foreign-library standalone` work on Linux/macOS, which would eliminate roughly 40% of the Nix build infrastructure.
