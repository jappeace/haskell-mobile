# armv7a Template Haskell Segfault Investigation

Issue: [#147](https://github.com/jappeace/hatter/issues/147)
PR: [#148](https://github.com/jappeace/hatter/pull/148)
Date: 2026-04-12

## Summary

Template Haskell evaluation on armv7a-android crashes with SIGSEGV in
GHC's RTS runtime linker.  This is an upstream GHC defect (GHC #14291,
haskell.nix #1544) that is not fixable at our level.  ARM32 support is
effectively abandoned in GHC.

Regular armv7a cross-compilation (without Template Haskell) works fine.

## Architecture

Template Haskell cross-compilation uses a two-process architecture:

```
  Build host (x86_64)              QEMU user-mode (ARM32 guest)
 ┌─────────────────────┐          ┌──────────────────────────────┐
 │  GHC cross-compiler │          │  iserv-proxy-interpreter     │
 │         │           │   TCP    │  (statically linked ARM32)   │
 │   iserv-proxy  ─────┼──────── │                              │
 │  (native x86_64)    │  socket │  Loads .o files via RTS      │
 └─────────────────────┘          │  linker, evaluates splices   │
                                  └──────────────────────────────┘
```

GHC sends `.o` files to the remote interpreter for loading and
evaluation.  The interpreter uses GHC's built-in RTS runtime linker
(`rts/linker/Elf.c`) to load ELF object files into memory, resolve
relocations, and execute TH splices.

## The Crash

The SIGSEGV occurs during garbage collection after `processForeignExports()`
which is called as part of `ocRunInit` during boot library initialization.
The GC walks the heap and encounters a closure with an invalid info pointer.

### Crash evidence

| Evidence | Value | Meaning |
|---|---|---|
| Fault address | `0xfffffff8` | `INFO_PTR_TO_STRUCT(NULL)` = `0 - 8` |
| Closure info pointer | `0x0` or `0x10` | NULL or THUNK_2_0 type constant |
| Crash location | `closure_sizeW_` related code | GC trying to compute closure size |
| Nearby heap data | `0x2a` (= 42) | The TH splice value `$(lift (42 :: Int))` |
| Crash module | Varies between builds | Not module-specific (systemic) |
| Relocation errors | None | All relocations reported as successful |

### Disassembly of crash site

```arm
0x1fabc14: ldr  r0, [r0]           ; load info pointer from closure
0x1fabc18: bl   INFO_PTR_TO_STRUCT  ; subtract 8 (tables-next-to-code)
0x1fabc24: ldrh r0, [r0]           ; CRASH: load ptrs from StgInfoTable
                                    ; r0 = 0xfffffff8 (unmapped)
```

`INFO_PTR_TO_STRUCT` on 32-bit with tables-next-to-code subtracts 8 from
the info pointer to get the `StgInfoTable` address.  With a NULL info
pointer, this produces `0xfffffff8`.

### Heap dump at crash site

```
outer closure (from base-4):
  [0] = 0x10       <-- INFO POINTER = 0x10 (THUNK_2_0 type constant!)
  [1] = 0x2a       <-- 42 (the TH splice value)
  [2] = 0x0        <-- NULL
  [3] = 0x44aaf9a8
```

The info pointer `0x10` is not a valid address -- it is the numeric value
of the `THUNK_2_0` closure type tag.  This indicates heap corruption:
something wrote a closure type tag where a pointer to an info table
should be.

## Root Cause Analysis

### GHC's ARM32 RTS linker

The LLVM backend (used for ARM32 code generation) produces per-function
ELF sections (`.text.functionName`) due to `-ffunction-sections`.  A
typical boot library `.o` file (e.g. `Posix.o` from `template-haskell`)
has ~1830 sections.

GHC's RTS linker loads these sections using the m32 allocator, resolves
ELF relocations (R_ARM_ABS32, R_ARM_CALL, R_ARM_JUMP24, R_ARM_GOT_PREL,
etc.), and creates ARM veneers (trampolines) for out-of-range branches.

The combination of:
1. Per-function sections (1000+ sections per `.o` file)
2. Statically-linked iserv binary (required for QEMU without Android's linker)
3. ARM32 architecture

triggers heap corruption during module initialization.  The exact
mechanism is unclear but likely involves incorrect relocation of closure
info pointers or corruption during the veneer allocation process.

### Known upstream issues

- **GHC #14291**: "iserv-proxy segfaults with split-sections on ARM"
  Exact match for our configuration.  Open since 2017.

- **haskell.nix #1544**: "Cross-compiling to armv7 with TH segfaults under QEMU"
  Same scenario.  Closed as **wontfix** with comment:
  *"the 32bit support in GHC is very poor."*

- **GHCup dropped ARM32**: Due to "frequent segfaults for compiled programs."

### What was ruled out

| Hypothesis | How ruled out |
|---|---|
| Relocation errors | `-Dl` linker trace shows all relocations succeed |
| Wrong section classification | `getSectionKind_ELF` uses flags (not names), per-function sections get correct `SECTIONKIND_CODE_OR_RODATA` |
| PIE/dlsym address issues | Binary is ET_EXEC, `st_value` is absolute, dlsym returns correct addresses |
| Module-specific bug | Crash module varies between builds (Posix.o, strerror.o) |
| QEMU address overlap | Fixed with `-B 0x10000000` guest_base, crash persists |
| Missing division helpers | Added `__aeabi_idiv` etc. in dl_impl.c, crash persists |
| I-cache coherency | QEMU handles I-cache transparently for guest code |

## Workarounds Applied

While TH itself cannot work on armv7a, the investigation produced
infrastructure improvements that benefit armv7a cross-compilation:

### 1. QEMU guest_base for ARM32

```
qemu-arm -B 0x10000000 ...
```

Without `-B`, the static iserv binary (loaded at `0x10000`) overlaps
QEMU's own host memory mappings.  `-B 0x10000000` (256 MiB) shifts the
guest address space away from QEMU's JIT code cache.

### 2. Bionic personality shim

```c
// nix/th-support/personality_shim.c
int personality(unsigned long persona) {
    (void)persona;
    return 0;
}
```

Android Bionic's 32-bit static binary startup calls
`personality(0xffffffff)`, which QEMU passes to the host kernel.  The
Nix build sandbox blocks this syscall via seccomp, returning EPERM.
Bionic treats this as fatal and aborts.

The shim is `LD_PRELOAD`ed into the host-side QEMU process.  64-bit
Bionic skips the personality call (`#if !defined(__LP64__)`), so aarch64
is unaffected.

### 3. ARM EABI division helpers

```c
// nix/th-support/dl_impl.c
static int impl_aeabi_idiv(int numerator, int denominator);
static unsigned impl_aeabi_uidiv(unsigned numerator, unsigned denominator);
// + 64-bit variants with naked asm thunks for AAPCS calling convention
```

GHC's LLVM backend emits `__aeabi_idiv` calls for ARM32 code loaded by
the RTS linker.  The Android NDK doesn't provide these (assumes hardware
divide).  Our `dlsym` intercepts lookups for these names and returns
pointers to software implementations.

## CI Configuration

The armv7a TH test is in `knownFailing` in `nix/ci.nix` -- excluded
from `all-builds` but available for manual testing:

```
nix-build nix/ci.nix -A th-direct-test-armv7a
```

## Possible Future Fixes

1. **GHC upgrade**: A future GHC version might fix the ARM32 RTS linker,
   though this seems unlikely given the lack of maintainers.

2. **Avoid TH on armv7a**: Consumer code can use `DerivingVia`,
   `Generic`-based deriving, or manual implementations instead of TH
   splices for armv7a targets.

3. **Pre-evaluated TH**: If GHC adds support for caching TH evaluation
   results, aarch64 results could potentially be reused for armv7a.

4. **External linker**: Using an external linker (like `lld`) instead of
   GHC's built-in RTS linker might avoid the bug, but would require
   significant GHC-side changes.
