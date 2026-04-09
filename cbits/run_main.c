/*
 * Run the user's Haskell main after hs_init.
 *
 * GHC compiles Main.main into ZCMain_main_closure, but does not
 * make it callable as a C function.  This wrapper uses the RTS API
 * (rts_evalIO) to evaluate that closure and capture the return value,
 * which is a Ptr AppContext.
 *
 * This removes the need for "foreign export ccall" in the user's
 * Main.hs — they write a plain main :: IO (Ptr AppContext) and we
 * call it, returning the context pointer to the platform bridge.
 */

#include "Rts.h"

/* GHC's Z-encoded symbol for :Main.main (the program's main closure) */
extern StgClosure ZCMain_main_closure;

void* haskellRunMain(void)
{
    Capability *cap = rts_lock();
    HaskellObj result;
    rts_evalIO(&cap, &ZCMain_main_closure, &result);
    rts_checkSchedStatus("haskellRunMain", cap);
    void *ctx = rts_getPtr(result);
    rts_unlock(cap);
    return ctx;
}
