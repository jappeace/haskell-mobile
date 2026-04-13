/*
 * iOS implementation of the location (GPS) bridge callbacks.
 *
 * Uses CoreLocation (CLLocationManager) to receive location updates.
 * Compiled by Xcode, not GHC.
 *
 * All Haskell callbacks are dispatched on the main thread.
 */

#import <CoreLocation/CoreLocation.h>
#import <os/log.h>
#include "LocationBridge.h"

#define LOG_TAG "LocationBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches location update back to Haskell callback) */
extern void haskellOnLocationUpdate(void *ctx, double lat, double lon,
                                     double alt, double acc);

/* ---- Location delegate ---- */

@interface LocationDelegate : NSObject <CLLocationManagerDelegate>
@property (nonatomic, assign) void *haskellCtx;
@property (nonatomic, strong) CLLocationManager *locationManager;
@end

@implementation LocationDelegate

- (void)locationManager:(CLLocationManager *)manager
     didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = [locations lastObject];
    if (!location) return;

    double lat = location.coordinate.latitude;
    double lon = location.coordinate.longitude;
    double alt = location.altitude;
    double acc = location.horizontalAccuracy;

    dispatch_async(dispatch_get_main_queue(), ^{
        haskellOnLocationUpdate(self.haskellCtx, lat, lon, alt, acc);
    });
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
    LOGE("CLLocationManager error: %{public}@", error.localizedDescription);
}

@end

static LocationDelegate *g_delegate = nil;

/* ---- Location bridge implementations ---- */

static void ios_location_start_updates(void *ctx)
{
    LOGI("ios_location_start_updates()");

    if (!g_delegate) {
        g_delegate = [[LocationDelegate alloc] init];
    }
    g_delegate.haskellCtx = ctx;

    if (!g_delegate.locationManager) {
        g_delegate.locationManager = [[CLLocationManager alloc] init];
        g_delegate.locationManager.delegate = g_delegate;
        g_delegate.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    }

    [g_delegate.locationManager startUpdatingLocation];
    LOGI("Location updates started");
}

static void ios_location_stop_updates(void)
{
    LOGI("ios_location_stop_updates()");

    if (g_delegate && g_delegate.locationManager) {
        [g_delegate.locationManager stopUpdatingLocation];
    }
}

/* ---- Public API ---- */

/*
 * Set up the iOS location bridge. Called from Swift during initialisation.
 * Registers callbacks with the platform-agnostic dispatcher.
 */
void setup_ios_location_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    location_register_impl(ios_location_start_updates,
                           ios_location_stop_updates);

    LOGI("iOS location bridge initialized");
}
