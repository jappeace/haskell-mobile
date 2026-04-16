/*
 * watchOS implementation of the redraw bridge.
 *
 * Same approach as iOS: uses GCD (dispatch_async_f) to post
 * haskellRenderUI to the main queue.
 *
 * Compiled by Xcode, not GHC.
 */

#include "RedrawBridge.h"
#include <dispatch/dispatch.h>
#include <os/log.h>

#define LOG_TAG "RedrawBridge"

/* Haskell FFI export (renders the UI tree) */
extern void haskellRenderUI(void *ctx);

static void redraw_on_main(void *ctx)
{
    haskellRenderUI(ctx);
}

static void watchos_request_redraw(void *ctx)
{
    os_log_info(OS_LOG_DEFAULT, "watchos_request_redraw()");
    dispatch_async_f(dispatch_get_main_queue(), ctx, redraw_on_main);
}

/* ---- Public API ---- */

/*
 * Set up the watchOS redraw bridge. Called from Swift during initialisation.
 * Registers callback with the platform-agnostic dispatcher.
 */
void setup_watchos_redraw_bridge(void *haskellCtx)
{
    redraw_register_impl(watchos_request_redraw);

    os_log_info(OS_LOG_DEFAULT, "watchOS redraw bridge initialized");
}
