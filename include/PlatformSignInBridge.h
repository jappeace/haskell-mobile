#ifndef PLATFORM_SIGN_IN_BRIDGE_H
#define PLATFORM_SIGN_IN_BRIDGE_H

#include <stdint.h>

/* Platform sign-in status codes (must match Hatter.PlatformSignIn) */
#define PLATFORM_SIGN_IN_SUCCESS    0
#define PLATFORM_SIGN_IN_CANCELLED  1
#define PLATFORM_SIGN_IN_ERROR      2

/* Platform sign-in provider codes (must match Hatter.PlatformSignIn) */
#define PLATFORM_SIGN_IN_APPLE   0
#define PLATFORM_SIGN_IN_GOOGLE  1

/*
 * Platform-agnostic sign-in bridge.
 *
 * Haskell calls platform_sign_in_start() through this wrapper.
 * When no platform callback is registered (desktop), a stub returns
 * fake credentials and fires haskellOnPlatformSignInResult synchronously.
 *
 * On Android/iOS the platform-specific setup function fills in a real
 * implementation via platform_sign_in_register_impl().
 */

/* Start a platform sign-in flow.
 * ctx:       opaque Haskell context pointer (passed through to callback).
 * requestId: opaque ID from Haskell (used to dispatch the result).
 * provider:  PLATFORM_SIGN_IN_APPLE (0) or PLATFORM_SIGN_IN_GOOGLE (1). */
void platform_sign_in_start(void *ctx, int32_t requestId, int32_t provider);

/* Register the platform-specific implementation.
 * Called by platform setup functions (setup_android_platform_sign_in_bridge, etc). */
void platform_sign_in_register_impl(
    void (*start_impl)(void *, int32_t, int32_t));

#endif /* PLATFORM_SIGN_IN_BRIDGE_H */
