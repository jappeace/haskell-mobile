/*
 * iOS implementation of the network connectivity status bridge.
 *
 * Uses NWPathMonitor from the Network framework to receive
 * connectivity changes. Compiled by Xcode, not GHC.
 *
 * All Haskell callbacks are dispatched on the main thread.
 */

#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import <os/log.h>
#include "NetworkStatusBridge.h"

#define LOG_TAG "NetworkStatusBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches network status change back to Haskell callback) */
extern void haskellOnNetworkStatusChange(void *ctx, int connected, int transport);

/* ---- Global state ---- */
static nw_path_monitor_t g_monitor = nil;
static void *g_haskell_ctx = NULL;

/* ---- Network status bridge implementations ---- */

static void ios_network_status_start_monitoring(void *ctx)
{
    LOGI("ios_network_status_start_monitoring()");

    g_haskell_ctx = ctx;

    /* Cancel any existing monitor */
    if (g_monitor) {
        nw_path_monitor_cancel(g_monitor);
        g_monitor = nil;
    }

    g_monitor = nw_path_monitor_create();
    nw_path_monitor_set_queue(g_monitor, dispatch_get_main_queue());

    nw_path_monitor_set_update_handler(g_monitor, ^(nw_path_t path) {
        nw_path_status_t status = nw_path_get_status(path);
        int connected = (status == nw_path_status_satisfied ||
                         status == nw_path_status_satisfiable) ? 1 : 0;

        int transport = NETWORK_TRANSPORT_OTHER;
        if (nw_path_uses_interface_type(path, nw_interface_type_wifi)) {
            transport = NETWORK_TRANSPORT_WIFI;
        } else if (nw_path_uses_interface_type(path, nw_interface_type_cellular)) {
            transport = NETWORK_TRANSPORT_CELLULAR;
        } else if (nw_path_uses_interface_type(path, nw_interface_type_wired)) {
            transport = NETWORK_TRANSPORT_ETHERNET;
        } else if (!connected) {
            transport = NETWORK_TRANSPORT_NONE;
        }

        LOGI("Network status changed: connected=%d, transport=%d", connected, transport);
        haskellOnNetworkStatusChange(g_haskell_ctx, connected, transport);
    });

    nw_path_monitor_start(g_monitor);
    LOGI("Network monitoring started");
}

static void ios_network_status_stop_monitoring(void)
{
    LOGI("ios_network_status_stop_monitoring()");

    if (g_monitor) {
        nw_path_monitor_cancel(g_monitor);
        g_monitor = nil;
    }
}

/* ---- Public API ---- */

/*
 * Set up the iOS network status bridge. Called from Swift during initialisation.
 * Registers callbacks with the platform-agnostic dispatcher.
 */
void setup_ios_network_status_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    network_status_register_impl(ios_network_status_start_monitoring,
                                  ios_network_status_stop_monitoring);

    LOGI("iOS network status bridge initialized");
}
