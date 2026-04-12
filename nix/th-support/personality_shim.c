/*
 * LD_PRELOAD shim: intercept personality() for QEMU user-mode.
 *
 * Bionic's 32-bit static binary startup calls personality(0xffffffff)
 * to query the process personality, then personality(PER_LINUX32) to set
 * it.  QEMU user-mode passes these through to the host kernel, but the
 * Nix build sandbox blocks the personality syscall via seccomp, returning
 * EPERM.  Bionic treats this as fatal and aborts.
 *
 * This shim is LD_PRELOADed into the *host-side* QEMU process (x86_64),
 * intercepting the libc personality() call before it reaches the kernel.
 * Since personality flags have no meaningful effect under QEMU user-mode
 * emulation, we simply return PER_LINUX (0) for queries and pretend
 * success for sets.
 *
 * Only needed for armv7a (32-bit) — aarch64 Bionic skips the personality
 * call entirely (#if !defined(__LP64__)).
 */

#include <sys/personality.h>

int personality(unsigned long persona) {
    (void)persona;
    return 0;  /* PER_LINUX — success for both query and set */
}
