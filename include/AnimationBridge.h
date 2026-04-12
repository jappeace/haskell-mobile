#ifndef ANIMATION_BRIDGE_H
#define ANIMATION_BRIDGE_H

/*
 * Platform-agnostic animation frame loop bridge.
 *
 * Haskell calls animation_start_loop / animation_stop_loop through
 * these wrappers.  When no platform callbacks are registered (desktop),
 * start_loop fires three synchronous test frames (0ms, 16.67ms, 1000ms)
 * so that cabal test can verify the callback chain.
 *
 * On Android/iOS the platform-specific setup function fills in real
 * implementations via animation_register_impl().
 */

/* Start the platform animation frame loop.
 * Each vsync frame calls haskellOnAnimationFrame(ctx, timestampMs).
 * ctx is the opaque Haskell context pointer. */
void animation_start_loop(void *ctx);

/* Stop the platform animation frame loop. */
void animation_stop_loop(void);

/* Register platform-specific implementations.
 * Called by platform setup functions (setup_android_animation_bridge, etc). */
void animation_register_impl(
    void (*start_loop)(void *),
    void (*stop_loop)(void));

#endif /* ANIMATION_BRIDGE_H */
