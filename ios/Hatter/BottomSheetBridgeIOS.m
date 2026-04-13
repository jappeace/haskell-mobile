/*
 * iOS implementation of the bottom sheet bridge callback.
 *
 * Uses UIAlertController with actionSheet style to present a bottom sheet
 * with a title and selectable item buttons.  This is the standard iOS
 * pattern for action menus from the bottom of the screen.
 * Compiled by Xcode, not GHC.
 *
 * All functions run on the main thread.
 */

#import <UIKit/UIKit.h>
#import <os/log.h>
#include "BottomSheetBridge.h"

#define LOG_TAG "BottomSheetBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnBottomSheetResult(void *ctx, int32_t requestId, int32_t actionCode);

/* ---- Bottom sheet implementation ---- */

static void ios_bottom_sheet_show(void *ctx, int32_t requestId,
                                   const char *title, const char *items)
{
    LOGI("bottom_sheet_show(title=\"%{public}s\", id=%d)", title, requestId);

    /* In autotest mode, auto-select first item without presenting the sheet. */
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    if ([args containsObject:@"--autotest-buttons"] || [args containsObject:@"--autotest"]) {
        LOGI("bottom_sheet_show: autotest mode -- auto-selecting first item");
        haskellOnBottomSheetResult(ctx, requestId, 0);
        return;
    }

    NSString *nsTitle = [NSString stringWithUTF8String:title];
    NSString *nsItems = [NSString stringWithUTF8String:items];
    NSArray<NSString *> *itemLabels = [nsItems componentsSeparatedByString:@"\n"];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nsTitle
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleActionSheet];

    /* Add an action for each item */
    for (NSUInteger i = 0; i < itemLabels.count; i++) {
        NSInteger index = (NSInteger)i;
        [sheet addAction:[UIAlertAction actionWithTitle:itemLabels[i]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            haskellOnBottomSheetResult(ctx, requestId, (int32_t)index);
        }]];
    }

    /* Cancel action fires DISMISSED */
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        haskellOnBottomSheetResult(ctx, requestId, BOTTOM_SHEET_DISMISSED);
    }]];

    /* Present on the topmost view controller */
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
        UIWindow *window = scene.windows.firstObject;
        UIViewController *rootVC = window.rootViewController;

        /* Walk up presented controllers to find the topmost */
        while (rootVC.presentedViewController) {
            rootVC = rootVC.presentedViewController;
        }

        if (rootVC) {
            [rootVC presentViewController:sheet animated:YES completion:nil];
        } else {
            LOGE("bottom_sheet_show: no root view controller to present on");
            haskellOnBottomSheetResult(ctx, requestId, BOTTOM_SHEET_DISMISSED);
        }
    });
}

/* ---- Public API ---- */

/*
 * Set up the iOS bottom sheet bridge. Called from Swift during initialisation.
 * Registers callback with the platform-agnostic dispatcher.
 */
void setup_ios_bottom_sheet_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    bottom_sheet_register_impl(ios_bottom_sheet_show);

    LOGI("iOS bottom sheet bridge initialized");
}
