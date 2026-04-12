/*
 * Platform-agnostic animation frame loop bridge dispatcher.
 *
 * Stores function pointers filled by the platform (Android/iOS).
 * Each animation_* function delegates to the corresponding pointer.
 * When no callbacks are registered (desktop), start_loop fires
 * three synchronous test frames (0ms, 16.67ms, 1000ms) so that
 * cabal test can verify the Haskell animation callback chain.
 */

#include "AnimationBridge.h"
#include <stdio.h>

/* Haskell FFI export (dispatches animation frame back to Haskell) */
extern void haskellOnAnimationFrame(void *ctx, double timestampMs);

static void (*g_start_loop_impl)(void *) = NULL;
static void (*g_stop_loop_impl)(void) = NULL;

void animation_register_impl(
    void (*start_loop)(void *),
    void (*stop_loop)(void))
{
    g_start_loop_impl = start_loop;
    g_stop_loop_impl = stop_loop;
}

void animation_start_loop(void *ctx)
{
    if (g_start_loop_impl) {
        g_start_loop_impl(ctx);
        return;
    }
    /* Desktop stub: fire three synchronous test frames */
    fprintf(stderr, "[AnimationBridge stub] animation_start_loop() -> firing test frames\n");
    haskellOnAnimationFrame(ctx, 0.0);
    haskellOnAnimationFrame(ctx, 16.67);
    haskellOnAnimationFrame(ctx, 1000.0);
}

void animation_stop_loop(void)
{
    if (g_stop_loop_impl) {
        g_stop_loop_impl();
        return;
    }
    /* Desktop stub: no-op */
    fprintf(stderr, "[AnimationBridge stub] animation_stop_loop() -> no-op\n");
}
