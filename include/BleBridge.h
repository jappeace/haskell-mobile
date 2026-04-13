#ifndef BLE_BRIDGE_H
#define BLE_BRIDGE_H

#include <stdint.h>

/* BLE adapter status codes (must match Hatter.Ble) */
#define BLE_ADAPTER_OFF          0
#define BLE_ADAPTER_ON           1
#define BLE_ADAPTER_UNAUTHORIZED 2
#define BLE_ADAPTER_UNSUPPORTED  3

/*
 * Platform-agnostic BLE scanning bridge.
 *
 * Haskell calls ble_check_adapter / ble_start_scan / ble_stop_scan
 * through these wrappers.  When no platform callbacks are registered
 * (desktop), stubs return BLE_ADAPTER_ON and log no-ops so that
 * cabal build/test works without native code.
 *
 * On Android/iOS the platform-specific setup function fills in real
 * implementations via ble_register_impl().
 */

/* Check the BLE adapter status (synchronous).
 * Returns one of BLE_ADAPTER_* constants. */
int32_t ble_check_adapter(void);

/* Start a BLE scan. Discovered devices are delivered via
 * haskellOnBleScanResult(). ctx is the opaque Haskell context. */
void ble_start_scan(void *ctx);

/* Stop a running BLE scan. */
void ble_stop_scan(void);

/* Register platform-specific implementations.
 * Called by platform setup functions (setup_android_ble_bridge, etc). */
void ble_register_impl(
    int32_t (*check_adapter)(void),
    void (*start_scan)(void *),
    void (*stop_scan)(void));

#endif /* BLE_BRIDGE_H */
