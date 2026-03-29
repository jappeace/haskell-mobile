/*
 * Run the user's Haskell main after hs_init.
 *
 * GHC compiles Main.main into ZCMain_main_closure, but does not
 * make it callable as a C function.  This wrapper uses the RTS API
 * (rts_evalLazyIO) to evaluate that closure, which is the same
 * mechanism hs_main uses internally.
 *
 * This removes the need for "foreign export ccall" in the user's
 * Main.hs — they write a plain main :: IO () and we call it.
 */

#include "Rts.h"

/* GHC's Z-encoded symbol for :Main.main (the program's main closure) */
extern StgClosure ZCMain_main_closure;

void haskellRunMain(void)
{
    Capability *cap = rts_lock();
    rts_evalLazyIO(&cap, &ZCMain_main_closure, NULL);
    rts_checkSchedStatus("haskellRunMain", cap);
    rts_unlock(cap);
}
