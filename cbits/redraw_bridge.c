/*
 * Platform-agnostic redraw bridge dispatcher.
 *
 * Stores a function pointer filled by the platform (Android/iOS/watchOS).
 * request_redraw() delegates to the platform implementation.
 * When no callback is registered (desktop), calls haskellRenderUI()
 * directly so that cabal test can verify the redraw path.
 *
 * Also provides start_periodic_redraw() — a test helper that creates
 * a native OS thread to call request_redraw() on a timer.  This is
 * needed because forkIO + threadDelay does not work on Android's
 * non-threaded RTS (the scheduler only runs during JNI callbacks).
 */

#include "RedrawBridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>

#ifdef _WIN32
#include <windows.h>
#define SLEEP_SECS(n) Sleep((n) * 1000)
#else
#include <unistd.h>
#define SLEEP_SECS(n) sleep((unsigned)(n))
#endif

/* Haskell FFI export (renders the UI tree) */
extern void haskellRenderUI(void *ctx);

/* hatterLog (defined in platform_log.c) — platform-aware logging */
extern void hatterLog(const char *msg);

static void (*g_request_redraw_impl)(void *) = NULL;
static void *g_redraw_ctx = NULL;
static volatile int g_periodic_counter = 0;

void redraw_register_impl(void (*impl)(void *))
{
    g_request_redraw_impl = impl;
}

void redraw_store_ctx(void *ctx)
{
    g_redraw_ctx = ctx;
}

void request_redraw(void *ctx)
{
    if (g_request_redraw_impl) {
        g_request_redraw_impl(ctx);
        return;
    }
    /* Desktop stub: call haskellRenderUI directly */
    fprintf(stderr, "[RedrawBridge stub] request_redraw() -> calling haskellRenderUI\n");
    haskellRenderUI(ctx);
}

/* --- Test helper: periodic redraw from a native OS thread ------------- */

struct periodic_ctx {
    void *ctx;
    int interval_secs;
    int count;
};

static void *periodic_thread(void *arg)
{
    struct periodic_ctx *pc = (struct periodic_ctx *)arg;
    for (int i = 1; i <= pc->count; i++) {
        SLEEP_SECS(pc->interval_secs);
        g_periodic_counter = i;
        char msg[64];
        snprintf(msg, sizeof(msg), "Background tick: %d", i);
        hatterLog(msg);
        request_redraw(pc->ctx);
    }
    free(pc);
    return NULL;
}

void start_periodic_redraw(int interval_secs, int count)
{
    g_periodic_counter = 0;
    struct periodic_ctx *pc =
        (struct periodic_ctx *)malloc(sizeof(struct periodic_ctx));
    pc->ctx = g_redraw_ctx;
    pc->interval_secs = interval_secs;
    pc->count = count;
    pthread_t thread;
    pthread_create(&thread, NULL, periodic_thread, pc);
    pthread_detach(thread);
}

int get_periodic_counter(void)
{
    return g_periodic_counter;
}
