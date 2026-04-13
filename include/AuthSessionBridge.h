#ifndef AUTH_SESSION_BRIDGE_H
#define AUTH_SESSION_BRIDGE_H

#include <stdint.h>

/* Auth session status codes (must match Hatter.AuthSession) */
#define AUTH_SESSION_SUCCESS    0
#define AUTH_SESSION_CANCELLED  1
#define AUTH_SESSION_ERROR      2

/*
 * Platform-agnostic auth session bridge.
 *
 * Haskell calls auth_session_start() through this wrapper.
 * When no platform callback is registered (desktop), a stub builds a
 * fake redirect URL and fires haskellOnAuthSessionResult synchronously.
 *
 * On Android/iOS the platform-specific setup function fills in a real
 * implementation via auth_session_register_impl().
 */

/* Start an authentication session (opens system browser).
 * ctx:            opaque Haskell context pointer (passed through to callback).
 * requestId:      opaque ID from Haskell (used to dispatch the result).
 * authUrl:        null-terminated URL to open in the system browser.
 * callbackScheme: null-terminated URL scheme for the redirect (e.g. "myapp"). */
void auth_session_start(void *ctx, int32_t requestId,
                        const char *authUrl, const char *callbackScheme);

/* Register the platform-specific implementation.
 * Called by platform setup functions (setup_android_auth_session_bridge, etc). */
void auth_session_register_impl(
    void (*start_impl)(void *, int32_t, const char *, const char *));

#endif /* AUTH_SESSION_BRIDGE_H */
