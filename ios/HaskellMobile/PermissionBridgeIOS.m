/*
 * iOS implementation of the permission bridge callbacks.
 *
 * Uses platform APIs (AVFoundation, Contacts, CoreLocation) to check
 * and request permissions.  Compiled by Xcode, not GHC.
 *
 * All functions run on the main thread.
 */

#import <AVFoundation/AVFoundation.h>
#import <Contacts/Contacts.h>
#import <CoreLocation/CoreLocation.h>
#import <os/log.h>
#include "PermissionBridge.h"

#define LOG_TAG "PermissionBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnPermissionResult(void *ctx, int32_t requestId, int32_t statusCode);

/* ---- Location manager delegate ---- */

@interface PermissionLocationDelegate : NSObject <CLLocationManagerDelegate>
@property (nonatomic, assign) int32_t requestId;
@property (nonatomic, assign) void *haskellCtx;
@property (nonatomic, strong) CLLocationManager *manager;
@end

@implementation PermissionLocationDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    /* Only dispatch once we have a definitive answer */
    if (status == kCLAuthorizationStatusNotDetermined) return;

    int32_t result = (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
                      status == kCLAuthorizationStatusAuthorizedAlways)
        ? PERMISSION_GRANTED : PERMISSION_DENIED;

    LOGI("location authorization changed: %d -> result=%d", (int)status, result);
    haskellOnPermissionResult(self.haskellCtx, self.requestId, result);
}

@end

/* Retained delegate instance (must outlive the authorization flow) */
static PermissionLocationDelegate *g_location_delegate = nil;

/* ---- Permission bridge implementations ---- */

static int32_t ios_permission_check(int32_t permissionCode)
{
    switch (permissionCode) {
    case PERMISSION_CAMERA: {
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        return (status == AVAuthorizationStatusAuthorized) ? PERMISSION_GRANTED : PERMISSION_DENIED;
    }
    case PERMISSION_MICROPHONE: {
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
        return (status == AVAuthorizationStatusAuthorized) ? PERMISSION_GRANTED : PERMISSION_DENIED;
    }
    case PERMISSION_CONTACTS: {
        CNAuthorizationStatus status = [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts];
        return (status == CNAuthorizationStatusAuthorized) ? PERMISSION_GRANTED : PERMISSION_DENIED;
    }
    case PERMISSION_LOCATION: {
        CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
        return (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
                status == kCLAuthorizationStatusAuthorizedAlways)
            ? PERMISSION_GRANTED : PERMISSION_DENIED;
    }
    case PERMISSION_BLUETOOTH:
    case PERMISSION_STORAGE:
        /* Bluetooth uses CBCentralManager state machine (not a simple check);
         * storage is always available on modern iOS. Auto-grant both. */
        return PERMISSION_GRANTED;
    default:
        LOGE("permission_check: unknown code %d", permissionCode);
        return PERMISSION_DENIED;
    }
}

static void ios_permission_request(void *ctx, int32_t permissionCode, int32_t requestId)
{
    LOGI("permission_request(code=%d, id=%d)", permissionCode, requestId);

    switch (permissionCode) {
    case PERMISSION_CAMERA: {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                haskellOnPermissionResult(ctx, requestId,
                    granted ? PERMISSION_GRANTED : PERMISSION_DENIED);
            });
        }];
        break;
    }
    case PERMISSION_MICROPHONE: {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                haskellOnPermissionResult(ctx, requestId,
                    granted ? PERMISSION_GRANTED : PERMISSION_DENIED);
            });
        }];
        break;
    }
    case PERMISSION_CONTACTS: {
        CNContactStore *store = [[CNContactStore alloc] init];
        [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                haskellOnPermissionResult(ctx, requestId,
                    granted ? PERMISSION_GRANTED : PERMISSION_DENIED);
            });
        }];
        break;
    }
    case PERMISSION_LOCATION: {
        g_location_delegate = [[PermissionLocationDelegate alloc] init];
        g_location_delegate.requestId = requestId;
        g_location_delegate.haskellCtx = ctx;
        g_location_delegate.manager = [[CLLocationManager alloc] init];
        g_location_delegate.manager.delegate = g_location_delegate;
        [g_location_delegate.manager requestWhenInUseAuthorization];
        break;
    }
    case PERMISSION_BLUETOOTH:
    case PERMISSION_STORAGE:
        /* Auto-grant (see ios_permission_check comment) */
        haskellOnPermissionResult(ctx, requestId, PERMISSION_GRANTED);
        break;
    default:
        LOGE("permission_request: unknown code %d", permissionCode);
        haskellOnPermissionResult(ctx, requestId, PERMISSION_DENIED);
        break;
    }
}

/* ---- Public API ---- */

/*
 * Set up the iOS permission bridge. Called from Swift during initialisation.
 * Registers callbacks with the platform-agnostic dispatcher.
 */
void setup_ios_permission_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.haskellmobile", LOG_TAG);

    permission_register_impl(ios_permission_request, ios_permission_check);

    LOGI("iOS permission bridge initialized");
}
