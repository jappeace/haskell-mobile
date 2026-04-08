#ifndef SECURE_STORAGE_BRIDGE_H
#define SECURE_STORAGE_BRIDGE_H

#include <stdint.h>

/* Secure storage status codes (must match HaskellMobile.SecureStorage) */
#define SECURE_STORAGE_SUCCESS    0
#define SECURE_STORAGE_NOT_FOUND  1
#define SECURE_STORAGE_ERROR      2

/* Operation type codes (internal, used by dispatcher) */
#define SECURE_STORAGE_OP_WRITE   0
#define SECURE_STORAGE_OP_READ    1
#define SECURE_STORAGE_OP_DELETE  2

/*
 * Platform-agnostic secure storage bridge.
 *
 * Haskell calls secure_storage_write/read/delete through these wrappers.
 * When no platform callbacks are registered (desktop), an in-memory
 * linked list stub provides basic functionality so that cabal build/test
 * works without native code.
 *
 * On Android/iOS the platform-specific setup function fills in real
 * implementations via secure_storage_register_impl().
 */

/* Write a key-value pair to secure storage.
 * ctx:       opaque Haskell context pointer (passed through to callback).
 * requestId: opaque ID from Haskell (used to dispatch the result).
 * key:       null-terminated key string.
 * value:     null-terminated value string. */
void secure_storage_write(void *ctx, int32_t requestId, const char *key, const char *value);

/* Read a value from secure storage by key.
 * ctx:       opaque Haskell context pointer (passed through to callback).
 * requestId: opaque ID from Haskell (used to dispatch the result).
 * key:       null-terminated key string.
 * Result dispatched via haskellOnSecureStorageResult with value or NULL. */
void secure_storage_read(void *ctx, int32_t requestId, const char *key);

/* Delete a key from secure storage.
 * ctx:       opaque Haskell context pointer (passed through to callback).
 * requestId: opaque ID from Haskell (used to dispatch the result).
 * key:       null-terminated key string. */
void secure_storage_delete(void *ctx, int32_t requestId, const char *key);

/* Register platform-specific implementations.
 * Called by platform setup functions (setup_android_secure_storage_bridge, etc). */
void secure_storage_register_impl(
    void (*write_impl)(void *, int32_t, const char *, const char *),
    void (*read_impl)(void *, int32_t, const char *),
    void (*delete_impl)(void *, int32_t, const char *));

#endif /* SECURE_STORAGE_BRIDGE_H */
