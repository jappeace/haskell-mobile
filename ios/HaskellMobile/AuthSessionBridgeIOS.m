/*
 * iOS implementation of the auth session bridge callback.
 *
 * Uses ASWebAuthenticationSession (AuthenticationServices framework)
 * to open an in-app browser for OAuth2/PKCE flows.
 * Compiled by Xcode, not GHC.
 *
 * All functions run on the main thread.
 */

#import <AuthenticationServices/AuthenticationServices.h>
#import <UIKit/UIKit.h>
#import <os/log.h>
#include "AuthSessionBridge.h"

#define LOG_TAG "AuthSessionBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnAuthSessionResult(void *ctx, int32_t requestId,
                                        int32_t statusCode,
                                        const char *redirectUrl,
                                        const char *errorMessage);

/* Presentation context provider for ASWebAuthenticationSession */
@interface AuthSessionPresentationContext : NSObject <ASWebAuthenticationPresentationContextProviding>
@end

@implementation AuthSessionPresentationContext
- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session
{
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    return scene.windows.firstObject;
}
@end

/* Prevent ARC deallocation during active session */
static ASWebAuthenticationSession *g_session = nil;
static AuthSessionPresentationContext *g_presentationCtx = nil;

/* ---- Auth session implementation ---- */

static void ios_auth_session_start(void *ctx, int32_t requestId,
                                    const char *authUrl,
                                    const char *callbackScheme)
{
    LOGI("auth_session_start(url=\"%{public}s\", scheme=\"%{public}s\", id=%d)",
         authUrl, callbackScheme, requestId);

    /* In autotest mode, return stub success without opening the browser.
     * CI simulators cannot interact with ASWebAuthenticationSession. */
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    if ([args containsObject:@"--autotest-buttons"] || [args containsObject:@"--autotest"]) {
        LOGI("auth_session_start: autotest mode — returning stub success");
        NSString *scheme = [NSString stringWithUTF8String:callbackScheme];
        NSString *stubUrl = [NSString stringWithFormat:@"%@://callback?code=IOS_AUTOTEST_CODE&state=test", scheme];
        haskellOnAuthSessionResult(ctx, requestId, AUTH_SESSION_SUCCESS,
                                    [stubUrl UTF8String], NULL);
        return;
    }

    NSURL *nsUrl = [NSURL URLWithString:[NSString stringWithUTF8String:authUrl]];
    NSString *nsScheme = [NSString stringWithUTF8String:callbackScheme];

    g_session = [[ASWebAuthenticationSession alloc]
        initWithURL:nsUrl
        callbackURLScheme:nsScheme
        completionHandler:^(NSURL *callbackURL, NSError *error) {
            if (callbackURL) {
                LOGI("auth_session_start: success url=%{public}@", callbackURL);
                haskellOnAuthSessionResult(ctx, requestId, AUTH_SESSION_SUCCESS,
                                            [[callbackURL absoluteString] UTF8String], NULL);
            } else if (error && error.code == ASWebAuthenticationSessionErrorCodeCanceledLogin) {
                LOGI("auth_session_start: cancelled");
                haskellOnAuthSessionResult(ctx, requestId, AUTH_SESSION_CANCELLED,
                                            NULL, NULL);
            } else {
                NSString *errMsg = error ? [error localizedDescription] : @"unknown error";
                LOGE("auth_session_start: error %{public}@", errMsg);
                haskellOnAuthSessionResult(ctx, requestId, AUTH_SESSION_ERROR,
                                            NULL, [errMsg UTF8String]);
            }
            g_session = nil;
            g_presentationCtx = nil;
        }];

    g_presentationCtx = [[AuthSessionPresentationContext alloc] init];
    g_session.presentationContextProvider = g_presentationCtx;

    if (![g_session start]) {
        LOGE("auth_session_start: failed to start session");
        haskellOnAuthSessionResult(ctx, requestId, AUTH_SESSION_ERROR,
                                    NULL, "failed to start auth session");
        g_session = nil;
        g_presentationCtx = nil;
    }
}

/* ---- Public API ---- */

/*
 * Set up the iOS auth session bridge. Called from Swift during initialisation.
 * Registers callback with the platform-agnostic dispatcher.
 */
void setup_ios_auth_session_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.haskellmobile", LOG_TAG);

    auth_session_register_impl(ios_auth_session_start);

    LOGI("iOS auth session bridge initialized");
}
