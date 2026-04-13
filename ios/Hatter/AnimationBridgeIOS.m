/*
 * iOS implementation of the animation frame loop bridge.
 *
 * Uses CADisplayLink from QuartzCore to receive vsync frames.
 * Compiled by Xcode, not GHC.
 *
 * All Haskell callbacks are dispatched on the main thread.
 */

#import <Foundation/Foundation.h>
#import <QuartzCore/CADisplayLink.h>
#import <os/log.h>
#include "AnimationBridge.h"

#define LOG_TAG "AnimationBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches animation frame back to Haskell) */
extern void haskellOnAnimationFrame(void *ctx, double timestampMs);

/* ---- AnimationFrameHandler (CADisplayLink target) ---- */

@interface AnimationFrameHandler : NSObject
@property (nonatomic, assign) void *haskellCtx;
@property (nonatomic, strong) CADisplayLink *displayLink;
- (void)onFrame:(CADisplayLink *)link;
@end

@implementation AnimationFrameHandler

- (void)onFrame:(CADisplayLink *)link {
    double timestampMs = link.timestamp * 1000.0;
    haskellOnAnimationFrame(self.haskellCtx, timestampMs);
}

@end

/* ---- Global state ---- */
static AnimationFrameHandler *g_handler = nil;

/* ---- Animation bridge implementations ---- */

static void ios_animation_start_loop(void *ctx)
{
    LOGI("ios_animation_start_loop()");

    /* Stop any existing loop */
    if (g_handler) {
        [g_handler.displayLink invalidate];
        g_handler = nil;
    }

    g_handler = [[AnimationFrameHandler alloc] init];
    g_handler.haskellCtx = ctx;
    g_handler.displayLink = [CADisplayLink displayLinkWithTarget:g_handler
                                                        selector:@selector(onFrame:)];
    [g_handler.displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                                forMode:NSRunLoopCommonModes];
    LOGI("Animation loop started");
}

static void ios_animation_stop_loop(void)
{
    LOGI("ios_animation_stop_loop()");

    if (g_handler) {
        [g_handler.displayLink invalidate];
        g_handler = nil;
    }
}

/* ---- Public API ---- */

/*
 * Set up the iOS animation bridge. Called from Swift during initialisation.
 * Registers callbacks with the platform-agnostic dispatcher.
 */
void setup_ios_animation_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    animation_register_impl(ios_animation_start_loop,
                             ios_animation_stop_loop);

    LOGI("iOS animation bridge initialized");
}
