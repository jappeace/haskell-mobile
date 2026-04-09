#include <stddef.h>
#include <stdint.h>

/*
 * mmap wrapper for iserv-proxy-interpreter under QEMU user-mode.
 *
 * GHC's RTS linker on aarch64 sets linkerAlwaysPic=true, which
 * causes mmapForLinker to call mmap(NULL,...) without any address
 * hint.  Under QEMU user-mode, NULL-hint mmaps land at very high
 * guest addresses (0x7fb...), far from the static binary at
 * 0x200000.  When the RTS linker processes ADRP relocations
 * between loaded code and its GOT, the +-4 GiB range is exceeded.
 *
 * This wrapper intercepts mmap(NULL,...) calls and provides a
 * hint address just above the binary.  QEMU honours the hint if
 * the guest address is free, keeping all allocations within the
 * +-4 GiB ADRP range.
 *
 * Linked with -Wl,--wrap=mmap so __wrap_mmap replaces mmap and
 * __real_mmap calls the original.
 */

/* Flags from linux/mman.h -- same on all architectures */
#define _MAP_ANONYMOUS 0x20
#define _MAP_FIXED     0x10

void *__real_mmap(void *addr, unsigned long length, int prot,
                  int flags, int fd, long offset);

/* _end is provided by the linker: end of BSS = end of binary */
extern char _end;

static void *_mmap_next_hint = 0;

void *__wrap_mmap(void *addr, unsigned long length, int prot,
                  int flags, int fd, long offset) {
    /* Only intercept NULL-hint anonymous mappings */
    if (addr == 0 && (flags & _MAP_ANONYMOUS)
                  && !(flags & _MAP_FIXED)) {
        if (_mmap_next_hint == 0) {
            /* First call: start 2 MiB above end of binary */
            uintptr_t binary_end = ((uintptr_t)&_end + 0xfff)
                                   & ~(uintptr_t)0xfff;
            _mmap_next_hint = (void *)(binary_end + 0x200000);
        }
        void *result = __real_mmap(_mmap_next_hint, length, prot,
                                   flags, fd, offset);
        if (result != (void *)(intptr_t)-1) {
            /* Advance hint past this allocation (page-aligned) */
            uintptr_t next = ((uintptr_t)result + length + 0xfff)
                             & ~(uintptr_t)0xfff;
            _mmap_next_hint = (void *)next;
            return result;
        }
        /* Hint rejected (region occupied): fall through */
    }
    return __real_mmap(addr, length, prot, flags, fd, offset);
}
