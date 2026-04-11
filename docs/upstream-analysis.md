# Upstream Analysis: Cross-Compilation Fixes

Which of our Android cross-compilation workarounds could be upstreamed to the
projects they work around? Covers both the aarch64 Template Haskell fixes
(see `template-haskell-android-crosscompilation.md`) and the armv7a fixes
(see `armv7a-android-wear-crosscompilation.md`).

## nixpkgs — Easy Wins

These are small, self-contained patches that would benefit anyone doing ARM
Android cross-compilation with Nix.

### 1. compiler-rt: add `armv7a` to ARM32 architecture set

**Our workaround**: `patch-compiler-rt.py` patches `builtin-config-ix.cmake`
to add `armv7a` to the ARM32 set, and patches `CMakeLists.txt` to add
`armv7a_SOURCES`.

**What upstream would look like**: PR to nixpkgs adding `armv7a` alongside
the existing `arm`, `armhf`, `armv7` entries in compiler-rt's cmake config.

**Why it should land**: `armv7a` is the standard Android ARM32 target triple
(`armv7a-unknown-linux-android`). It's an obvious omission.

**Scope**: ~5 lines in compiler-rt cmake files.

### 2. compiler-rt: baremetal architecture detection with `-nodefaultlibs`

**Our workaround**: `patch-compiler-rt.py` replaces `detect_target_arch()`
(which uses `check_symbol_exists(__arm__)` — fails to link with
`-nodefaultlibs`) with direct `add_default_target_arch()` when
`COMPILER_RT_DEFAULT_TARGET_ONLY` is set.

**What upstream would look like**: Same patch in nixpkgs compiler-rt
derivation, or upstream to LLVM's compiler-rt.

**Why it should land**: `detect_target_arch()` is fundamentally broken for
baremetal/Android targets that use `-nodefaultlibs`. The
`COMPILER_RT_DEFAULT_TARGET_ONLY` codepath already knows the target — it
shouldn't need to probe for it.

**Scope**: ~10 lines in cmake. Could go to nixpkgs or LLVM upstream.

### 3. compiler-rt: exclude `os_version_check.c` from baremetal builds

**Our workaround**: `patch-compiler-rt.py` removes `os_version_check.c` from
the baremetal builtins source list.

**What upstream would look like**: Conditional exclusion in cmake when building
for baremetal targets.

**Why it should land**: `os_version_check.c` requires `pthread.h`, which is
unavailable in baremetal environments. This file is Apple-specific version
checking code that has no purpose on Android/Linux baremetal.

**Scope**: ~3 lines in cmake. Probably combine with #1 and #2 into one PR.

### 4. LLVM package set: `libstdcxxClang` for Android cross targets

**Our workaround**: `patch-compiler-rt.py` patches
`pkgs/development/compilers/llvm/common/default.nix` to select
`libstdcxxClang` instead of `libcxxClang` for Android targets.

**What upstream would look like**: PR to nixpkgs LLVM package set adding a
condition: if target is Android, use `libstdcxxClang`.

**Why it should land**: The default `libcxxClang` depends on `libcxx`, which
requires a working cross-linker to build. The bootstrap `clang-wrapper` only
has GNU `ld.bfd`, which can't link Android libraries (zstd-compressed debug
sections, missing builtins path). GHC's LLVM backend only needs clang for
assembly — no C++ required.

**Risk**: This changes the default clang variant for all Android cross builds
in nixpkgs. Needs careful review — other consumers might depend on
`libcxxClang` features. Could be gated on a flag or made specific to the
GHC use case.

**Scope**: ~5 lines, but needs discussion.

### 5. `generic-builder.nix`: skip profiled iserv-wrapper when profiling disabled

**Our workaround**: `patch-compiler-rt.py` patches
`pkgs/development/haskell-modules/generic-builder.nix` to skip the profiled
`iserv-wrapper` variant when `enableProfiling` is false.

**What upstream would look like**: Guard the profiled iserv-wrapper derivation
behind `enableProfiling` or `enableProfiledLibs`.

**Why it should land**: When a cross-GHC has `enableProfiledLibs = false`
(needed for armv7a due to LLVM crash), attempting to build a profiled
iserv-wrapper fails. The non-profiled variant works fine.

**Scope**: ~3 lines in generic-builder.nix.

## GHC — High Value, Needs Discussion

### 6. RTS linker: provide mmap hint even when `linkerAlwaysPic=true`

**Our workaround**: `--wrap=mmap` on iserv-proxy-interpreter intercepts
`mmap(NULL, ...)` and provides a hint address starting 2 MiB above `_end`.

**What upstream would look like**: In `rts/linker/MMap.c`, when
`linkerAlwaysPic=true`, instead of calling `mmap(NULL, ...)`, use a hint
address derived from `LINKER_LOAD_BASE` or the binary's load address. Fall
back to NULL hint if the hinted allocation fails.

**Why it should land**: This is arguably a bug. The `nearImage()` logic and
`LINKER_LOAD_BASE` exist precisely to keep linker allocations within ±4 GiB
for ADRP relocations, but they're completely bypassed when
`linkerAlwaysPic=true`. Any unusual memory layout (QEMU, aggressive ASLR,
large address space) can trigger the assertion in
`rts/linker/elf_reloc_aarch64.c:118`.

**Impact**: Would eliminate the need for our `mmap_wrapper.c` and
`--wrap=mmap` flag entirely. This is the single most valuable upstream fix.

**Risk**: Low. Providing a hint is advisory — the kernel can ignore it. The
fallback to NULL hint preserves current behavior if the hint fails.

**Scope**: ~15 lines in `rts/linker/MMap.c`. Probably needs a GHC issue +
MR, with a reproducer showing the failure under QEMU.

**GHC source refs** (9.10.3):
- `rts/linker/MMap.c` — `mmapForLinker` / `mmapAnywhere`
- `rts/linker/MMap.h` — `LINKER_LOAD_BASE`
- `rts/linker/elf_reloc_aarch64.c:118` — ADRP assertion
- `rts/include/rts/Flags.h` — `DEFAULT_LINKER_ALWAYS_PIC`

### 7. Cross-compiler: clear `dynamic-library-dirs` for static-only targets

**Our workaround**: `preConfigure` hook in mkDerivation overlay copies global
package confs, resolves `${pkgroot}`, clears `dynamic-library-dirs`, recaches.

**What upstream would look like**: GHC's cross-compiler installation step
should not populate `dynamic-library-dirs` when the target platform doesn't
support shared libraries (e.g., Android static builds).

**Why it should land**: The current behavior causes the RTS to attempt
`LoadDLL` for boot packages during TH evaluation, which always fails on
Android (no `.so` files), adding startup latency and confusing error messages
before falling back to `LoadArchive`.

**Risk**: Very low. Only affects cross-compiler configurations.

**Scope**: Probably a few lines in GHC's install phase or `ghc-pkg` config
generation. Needs investigation into where `dynamic-library-dirs` gets
populated during cross-compiler builds.

### 8. RTS flag: allow `-xm` when `linkerAlwaysPic=true`

**Our workaround**: `--wrap=mmap` (same as #6).

**What upstream would look like**: Accept `-xm <addr>` as a hint base even
when `linkerAlwaysPic=true`, rather than silently ignoring it.

**Why it should land**: Gives users a way to work around mmap placement issues
without patching the RTS. Complementary to #6.

**Risk**: Very low — it's an opt-in flag.

**Scope**: ~5 lines. But if #6 lands, this becomes less important.

## QEMU — Worth Filing, Hard to Land

### 9. Guest mmap: honor address hints for anonymous mappings

**Our workaround**: `--wrap=mmap` provides hints that QEMU happens to honor
(QEMU checks if the hinted guest address is free and uses it if so, but its
default allocator ignores NULL hints entirely, allocating top-down from high
addresses).

**What upstream would look like**: When `mmap(addr, ...)` is called with a
non-NULL hint and no `MAP_FIXED`, QEMU should prefer addresses near the hint,
matching Linux kernel behavior. For NULL hints, QEMU could optionally try
allocating near the binary before falling back to top-down.

**Why it might land**: It's a correctness argument — Linux kernel's mmap tries
to honor hints, and programs (like GHC's RTS) depend on this.

**Why it might not**: QEMU's user-mode address allocator is complex and
changes here affect all guest binaries. The top-down allocator exists for
good reasons (avoiding fragmentation).

**What to file**: Bug report documenting that `mmap(NULL, ...)` for anonymous
mappings returns addresses far (>4 GiB) from the binary, breaking
aarch64 programs that rely on mmap hints for PIC code loading. Include
reproducer: statically linked aarch64 binary that loads `.o` files with ADRP
relocations.

**Scope**: Unknown. Would require understanding QEMU's `mmap_find_vma` and
the guest address allocator deeply.

### 10. Static binary ELF header / TLS presentation (ARM32)

**Our workaround**: Keep `__aeabi_*` symbols out of `.dynsym` (use static
functions + dlsym interception) to avoid changing binary layout.

**What upstream would look like**: Fix how QEMU presents `AT_PHDR` or TLS
program headers to statically linked ARM32 binaries.

**Why it probably won't land**: Extremely niche — only triggers with specific
binary layouts under QEMU + Bionic's static libc. The TLS alignment check
passes mathematically on the binary itself; the issue is in how QEMU loads or
presents the ELF segments. Reproducing and root-causing this would require
deep QEMU ELF loading investigation.

**What to file**: Bug report documenting that adding a global symbol to a
static ARM32 binary (changing `.dynsym` size) causes Bionic's TLS init to
crash under QEMU, with both working and crashing binaries attached.

**Scope**: Unknown, probably significant QEMU internals work.

## Android NDK — Not Worth Upstreaming

### 11. Native ELF `libdl.a`

**Our workaround**: Custom `libdl.a` with `dlsym` that walks `.dynsym`.

**Why not upstream**: NDK intentionally ships `libdl.a` as stubs because
Android apps should use the dynamic linker. Our use case (statically linked
binary doing its own dynamic symbol lookup for an in-process RTS linker) is
too niche.

### 12. ARM EABI division helpers in compiler-rt

**Our workaround**: Static implementations in `dl_impl.c` + dlsym
interception.

**Why not upstream**: NDK targets API 21+ which effectively requires
hardware IDIV (Cortex-A7+). The helpers are omitted intentionally. Our need
comes from cross-compiled `.o` files targeting generic `armv7-a` being loaded
by the RTS linker at runtime — not a normal NDK use case.

## LLVM — Low Priority

### 13. `ARMAsmPrinter::emitXXStructor` crash with profiled code

**Our workaround**: Disable profiled libraries for armv7a.

**Why low priority**: Hard to reproduce outside the GHC build context. Would
need a minimal `.ll` file that triggers the crash, filed against LLVM's ARM
backend. The GHC profiling transform generates unusual code patterns that
LLVM's ARM backend doesn't handle.

**What to file**: LLVM bug with the crashing `.ll` input (extractable from
a failing GHC build with `-keep-llvm-files`).

## Recommended Order of Action

1. **nixpkgs PR**: compiler-rt fixes (#1, #2, #3) — single PR, easy review
2. **nixpkgs PR**: generic-builder profiling fix (#5) — standalone, easy
3. **GHC issue + MR**: RTS linker mmap hints (#6) — highest value
4. **nixpkgs PR**: LLVM clang for Android (#4) — needs discussion
5. **GHC issue**: cross-compiler dynamic-library-dirs (#7) — file issue first
6. **QEMU bug**: mmap hint handling (#9) — file with reproducer
7. **QEMU bug**: ARM32 TLS crash (#10) — file for documentation, low expectations
8. **LLVM bug**: ARM32 profiling crash (#13) — file if we can extract the `.ll`
