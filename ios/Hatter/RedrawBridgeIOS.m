/*
 * iOS implementation of the redraw bridge.
 *
 * Uses GCD (dispatch_async_f) to post haskellRenderUI to the main
 * queue. This ensures JNI-equivalent thread safety: all UI bridge
 * callbacks run on the main thread.
 *
 * Compiled by Xcode, not GHC.
 */

#include "RedrawBridge.h"
#include <dispatch/dispatch.h>
#include <os/log.h>

#define LOG_TAG "RedrawBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (renders the UI tree) */
extern void haskellRenderUI(void *ctx);

static void redraw_on_main(void *ctx)
{
    haskellRenderUI(ctx);
}

static void ios_request_redraw(void *ctx)
{
    LOGI("ios_request_redraw()");
    dispatch_async_f(dispatch_get_main_queue(), ctx, redraw_on_main);
}

/* ---- Public API ---- */

/*
 * Set up the iOS redraw bridge. Called from Swift during initialisation.
 * Registers callback with the platform-agnostic dispatcher.
 */
void setup_ios_redraw_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    redraw_register_impl(ios_request_redraw);

    LOGI("iOS redraw bridge initialized");
}
