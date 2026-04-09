/*
 * Platform-agnostic BLE scanning bridge dispatcher.
 *
 * Stores function pointers filled by the platform (Android/iOS).
 * Each ble_* function delegates to the corresponding pointer.
 * When no callbacks are registered (desktop), functions log to stderr
 * and return safe defaults so that cabal build/test works without
 * native code.
 *
 * Unlike the permission bridge, no fabricated devices are delivered
 * on desktop — start_scan is a no-op.
 */

#include "BleBridge.h"
#include <stdio.h>

static int32_t (*g_check_adapter_impl)(void) = NULL;
static void (*g_start_scan_impl)(void *) = NULL;
static void (*g_stop_scan_impl)(void) = NULL;

void ble_register_impl(
    int32_t (*check_adapter)(void),
    void (*start_scan)(void *),
    void (*stop_scan)(void))
{
    g_check_adapter_impl = check_adapter;
    g_start_scan_impl = start_scan;
    g_stop_scan_impl = stop_scan;
}

int32_t ble_check_adapter(void)
{
    if (g_check_adapter_impl) {
        return g_check_adapter_impl();
    }
    /* Desktop stub: adapter is on */
    fprintf(stderr, "[BleBridge stub] ble_check_adapter() -> BLE_ADAPTER_ON\n");
    return BLE_ADAPTER_ON;
}

void ble_start_scan(void *ctx)
{
    if (g_start_scan_impl) {
        g_start_scan_impl(ctx);
        return;
    }
    /* Desktop stub: no-op (no fabricated devices) */
    fprintf(stderr, "[BleBridge stub] ble_start_scan() -> no-op\n");
}

void ble_stop_scan(void)
{
    if (g_stop_scan_impl) {
        g_stop_scan_impl();
        return;
    }
    /* Desktop stub: no-op */
    fprintf(stderr, "[BleBridge stub] ble_stop_scan() -> no-op\n");
}
