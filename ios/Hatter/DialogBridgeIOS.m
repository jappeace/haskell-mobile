/*
 * iOS implementation of the dialog bridge callback.
 *
 * Uses UIAlertController to present modal dialogs with up to 3 buttons.
 * Compiled by Xcode, not GHC.
 *
 * All functions run on the main thread.
 */

#import <UIKit/UIKit.h>
#import <os/log.h>
#include "DialogBridge.h"

#define LOG_TAG "DialogBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnDialogResult(void *ctx, int32_t requestId, int32_t actionCode);

/* ---- Dialog implementation ---- */

static void ios_dialog_show(void *ctx, int32_t requestId,
                             const char *title, const char *message,
                             const char *button1, const char *button2,
                             const char *button3)
{
    LOGI("dialog_show(title=\"%{public}s\", id=%d)", title, requestId);

    /* In autotest mode, auto-press button 1 without presenting the dialog.
     * The autotest mechanism only fires widget button callbacks (onUIEvent),
     * it cannot tap native UIAlertController buttons. */
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    if ([args containsObject:@"--autotest-buttons"] || [args containsObject:@"--autotest"]) {
        LOGI("dialog_show: autotest mode — auto-pressing button 1");
        haskellOnDialogResult(ctx, requestId, DIALOG_BUTTON_1);
        return;
    }

    NSString *nsTitle = [NSString stringWithUTF8String:title];
    NSString *nsMessage = [NSString stringWithUTF8String:message];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nsTitle
                                                                  message:nsMessage
                                                           preferredStyle:UIAlertControllerStyleAlert];

    /* Button 1 (always present) */
    NSString *nsButton1 = [NSString stringWithUTF8String:button1];
    [alert addAction:[UIAlertAction actionWithTitle:nsButton1
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        haskellOnDialogResult(ctx, requestId, DIALOG_BUTTON_1);
    }]];

    /* Button 2 (optional) */
    if (button2 != NULL) {
        NSString *nsButton2 = [NSString stringWithUTF8String:button2];
        [alert addAction:[UIAlertAction actionWithTitle:nsButton2
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            haskellOnDialogResult(ctx, requestId, DIALOG_BUTTON_2);
        }]];
    }

    /* Button 3 (optional) */
    if (button3 != NULL) {
        NSString *nsButton3 = [NSString stringWithUTF8String:button3];
        [alert addAction:[UIAlertAction actionWithTitle:nsButton3
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *action) {
            haskellOnDialogResult(ctx, requestId, DIALOG_BUTTON_3);
        }]];
    }

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
            [rootVC presentViewController:alert animated:YES completion:nil];
        } else {
            LOGE("dialog_show: no root view controller to present on");
            haskellOnDialogResult(ctx, requestId, DIALOG_DISMISSED);
        }
    });
}

/* ---- Public API ---- */

/*
 * Set up the iOS dialog bridge. Called from Swift during initialisation.
 * Registers callback with the platform-agnostic dispatcher.
 */
void setup_ios_dialog_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    dialog_register_impl(ios_dialog_show);

    LOGI("iOS dialog bridge initialized");
}
