/*
 * iOS implementation of the platform sign-in bridge.
 *
 * Uses ASAuthorizationAppleIDProvider (AuthenticationServices framework)
 * for Sign in with Apple. Google Sign-In is not supported on iOS
 * (returns error).
 * Compiled by Xcode, not GHC.
 *
 * All functions run on the main thread.
 */

#import <AuthenticationServices/AuthenticationServices.h>
#import <UIKit/UIKit.h>
#import <os/log.h>
#include "PlatformSignInBridge.h"

#define LOG_TAG "PlatformSignInBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnPlatformSignInResult(void *ctx, int32_t requestId,
                                           int32_t statusCode,
                                           const char *identityToken,
                                           const char *userId,
                                           const char *email,
                                           const char *fullName,
                                           int32_t provider);

/* Delegate for ASAuthorizationController */
@interface PlatformSignInDelegate : NSObject <ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding>
@property (nonatomic, assign) void *haskellCtx;
@property (nonatomic, assign) int32_t requestId;
@end

/* Prevent ARC deallocation during active flow */
static PlatformSignInDelegate *g_delegate = nil;
static ASAuthorizationController *g_controller = nil;

@implementation PlatformSignInDelegate

- (ASPresentationAnchor)presentationAnchorForAuthorizationController:(ASAuthorizationController *)controller
{
    UIWindowScene *scene = (UIWindowScene *)[[UIApplication sharedApplication].connectedScenes anyObject];
    return scene.windows.firstObject;
}

- (void)authorizationController:(ASAuthorizationController *)controller
   didCompleteWithAuthorization:(ASAuthorization *)authorization
{
    if ([authorization.credential isKindOfClass:[ASAuthorizationAppleIDCredential class]]) {
        ASAuthorizationAppleIDCredential *appleCredential = (ASAuthorizationAppleIDCredential *)authorization.credential;

        /* Identity token is JWT data */
        NSString *identityToken = nil;
        if (appleCredential.identityToken) {
            identityToken = [[NSString alloc] initWithData:appleCredential.identityToken encoding:NSUTF8StringEncoding];
        }

        NSString *userId = appleCredential.user;

        /* Email — may be private relay address, only provided on first sign-in */
        NSString *email = appleCredential.email;

        /* Full name — only provided on first sign-in */
        NSString *fullName = nil;
        if (appleCredential.fullName) {
            NSPersonNameComponentsFormatter *formatter = [[NSPersonNameComponentsFormatter alloc] init];
            fullName = [formatter stringFromPersonNameComponents:appleCredential.fullName];
            if ([fullName length] == 0) fullName = nil;
        }

        LOGI("platform_sign_in: Apple success userId=%{public}@", userId);

        haskellOnPlatformSignInResult(self.haskellCtx, self.requestId,
                                       PLATFORM_SIGN_IN_SUCCESS,
                                       identityToken ? [identityToken UTF8String] : NULL,
                                       [userId UTF8String],
                                       email ? [email UTF8String] : NULL,
                                       fullName ? [fullName UTF8String] : NULL,
                                       PLATFORM_SIGN_IN_APPLE);
    }
    g_delegate = nil;
    g_controller = nil;
}

- (void)authorizationController:(ASAuthorizationController *)controller
           didCompleteWithError:(NSError *)error
{
    if (error.code == ASAuthorizationErrorCanceled) {
        LOGI("platform_sign_in: cancelled");
        haskellOnPlatformSignInResult(self.haskellCtx, self.requestId,
                                       PLATFORM_SIGN_IN_CANCELLED,
                                       NULL, NULL, NULL, NULL,
                                       PLATFORM_SIGN_IN_APPLE);
    } else {
        NSString *errMsg = [error localizedDescription];
        LOGE("platform_sign_in: error %{public}@", errMsg);
        haskellOnPlatformSignInResult(self.haskellCtx, self.requestId,
                                       PLATFORM_SIGN_IN_ERROR,
                                       NULL, NULL, NULL,
                                       [errMsg UTF8String],
                                       PLATFORM_SIGN_IN_APPLE);
    }
    g_delegate = nil;
    g_controller = nil;
}

@end

/* ---- Platform sign-in implementation ---- */

static void ios_platform_sign_in_start(void *ctx, int32_t requestId,
                                        int32_t provider)
{
    LOGI("platform_sign_in_start(provider=%d, id=%d)", provider, requestId);

    /* Google Sign-In not available on iOS */
    if (provider == PLATFORM_SIGN_IN_GOOGLE) {
        LOGE("platform_sign_in_start: Google Sign-In not available on iOS");
        haskellOnPlatformSignInResult(ctx, requestId,
                                       PLATFORM_SIGN_IN_ERROR,
                                       NULL, NULL, NULL,
                                       "Google Sign-In not available on iOS",
                                       PLATFORM_SIGN_IN_GOOGLE);
        return;
    }

    /* In autotest mode, return stub credentials without showing real UI.
     * CI simulators cannot interact with ASAuthorizationController. */
    NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
    if ([args containsObject:@"--autotest-buttons"] || [args containsObject:@"--autotest"]) {
        LOGI("platform_sign_in_start: autotest mode -- returning stub Apple credentials");
        haskellOnPlatformSignInResult(ctx, requestId,
                                       PLATFORM_SIGN_IN_SUCCESS,
                                       "IOS_AUTOTEST_APPLE_TOKEN",
                                       "apple-autotest-001",
                                       "autotest@privaterelay.appleid.com",
                                       "Autotest User",
                                       PLATFORM_SIGN_IN_APPLE);
        return;
    }

    /* Create Apple ID request */
    ASAuthorizationAppleIDProvider *appleIDProvider = [[ASAuthorizationAppleIDProvider alloc] init];
    ASAuthorizationAppleIDRequest *request = [appleIDProvider createRequest];
    request.requestedScopes = @[ASAuthorizationScopeFullName, ASAuthorizationScopeEmail];

    g_delegate = [[PlatformSignInDelegate alloc] init];
    g_delegate.haskellCtx = ctx;
    g_delegate.requestId = requestId;

    g_controller = [[ASAuthorizationController alloc] initWithAuthorizationRequests:@[request]];
    g_controller.delegate = g_delegate;
    g_controller.presentationContextProvider = g_delegate;

    [g_controller performRequests];
}

/* ---- Public API ---- */

/*
 * Set up the iOS platform sign-in bridge. Called from Swift during initialisation.
 * Registers callback with the platform-agnostic dispatcher.
 */
void setup_ios_platform_sign_in_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    platform_sign_in_register_impl(ios_platform_sign_in_start);

    LOGI("iOS platform sign-in bridge initialized");
}
