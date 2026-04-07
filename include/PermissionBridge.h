#ifndef PERMISSION_BRIDGE_H
#define PERMISSION_BRIDGE_H

#include <stdint.h>

/* Permission codes (must match HaskellMobile.Permission) */
#define PERMISSION_LOCATION    0
#define PERMISSION_BLUETOOTH   1
#define PERMISSION_CAMERA      2
#define PERMISSION_MICROPHONE  3
#define PERMISSION_CONTACTS    4
#define PERMISSION_STORAGE     5

/* Permission status codes (must match HaskellMobile.Permission) */
#define PERMISSION_GRANTED     0
#define PERMISSION_DENIED      1

/*
 * Platform-agnostic permission bridge.
 *
 * Haskell calls permission_request / permission_check through these wrappers.
 * When no platform callbacks are registered (desktop), stubs auto-grant
 * so that cabal build/test works without native code.
 *
 * On Android/iOS the platform-specific setup function fills in real
 * implementations via permission_register_impl().
 */

/* Request a runtime permission asynchronously.
 * ctx:            opaque Haskell context pointer (passed through to callback).
 * permissionCode: one of PERMISSION_* constants.
 * requestId:      opaque ID from Haskell (used to dispatch the result). */
void permission_request(void *ctx, int32_t permissionCode, int32_t requestId);

/* Check whether a permission is currently granted (synchronous).
 * Returns PERMISSION_GRANTED or PERMISSION_DENIED. */
int32_t permission_check(int32_t permissionCode);

/* Register platform-specific implementations.
 * Called by platform setup functions (setup_android_permission_bridge, etc). */
void permission_register_impl(
    void (*request)(void *, int32_t, int32_t),
    int32_t (*check)(int32_t));

#endif /* PERMISSION_BRIDGE_H */
