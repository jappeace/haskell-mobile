/*
 * iOS implementation of the BLE scanning bridge callbacks.
 *
 * Uses CoreBluetooth (CBCentralManager) to check adapter state
 * and scan for peripherals. Compiled by Xcode, not GHC.
 *
 * All Haskell callbacks are dispatched on the main thread.
 */

#import <CoreBluetooth/CoreBluetooth.h>
#import <os/log.h>
#include "BleBridge.h"

#define LOG_TAG "BleBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

/* Haskell FFI export (dispatches scan result back to Haskell callback) */
extern void haskellOnBleScanResult(void *ctx, const char *name, const char *address, int32_t rssi);

/* ---- Module-level state (declared before use in delegate methods) ---- */

static BOOL g_scanning_requested = NO;

/* ---- Scan delegate ---- */

@interface BleScanDelegate : NSObject <CBCentralManagerDelegate>
@property (nonatomic, assign) void *haskellCtx;
@property (nonatomic, strong) CBCentralManager *centralManager;
@end

@implementation BleScanDelegate

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    LOGI("CBCentralManager state: %ld", (long)central.state);
    /* If scanning was requested before the manager was ready, start now */
    if (central.state == CBManagerStatePoweredOn && g_scanning_requested) {
        [central scanForPeripheralsWithServices:nil
                                        options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
        LOGI("BLE scan started (deferred)");
    }
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *, id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {
    const char *name = peripheral.name ? [peripheral.name UTF8String] : NULL;
    const char *address = [[peripheral.identifier UUIDString] UTF8String];
    int32_t rssi = [RSSI intValue];

    dispatch_async(dispatch_get_main_queue(), ^{
        haskellOnBleScanResult(self.haskellCtx, name, address, rssi);
    });
}

@end

static BleScanDelegate *g_delegate = nil;

/* ---- BLE bridge implementations ---- */

static int32_t ios_ble_check_adapter(void)
{
    if (!g_delegate || !g_delegate.centralManager) {
        return BLE_ADAPTER_UNSUPPORTED;
    }

    switch (g_delegate.centralManager.state) {
    case CBManagerStatePoweredOn:
        return BLE_ADAPTER_ON;
    case CBManagerStatePoweredOff:
        return BLE_ADAPTER_OFF;
    case CBManagerStateUnauthorized:
        return BLE_ADAPTER_UNAUTHORIZED;
    case CBManagerStateUnsupported:
        return BLE_ADAPTER_UNSUPPORTED;
    case CBManagerStateResetting:
        return BLE_ADAPTER_OFF;
    case CBManagerStateUnknown:
        return BLE_ADAPTER_OFF;
    }
    return BLE_ADAPTER_UNSUPPORTED;
}

static void ios_ble_start_scan(void *ctx)
{
    LOGI("ios_ble_start_scan()");

    if (!g_delegate) {
        g_delegate = [[BleScanDelegate alloc] init];
    }
    g_delegate.haskellCtx = ctx;

    if (!g_delegate.centralManager) {
        g_scanning_requested = YES;
        g_delegate.centralManager = [[CBCentralManager alloc]
            initWithDelegate:g_delegate
                       queue:dispatch_get_main_queue()];
        return;
    }

    if (g_delegate.centralManager.state == CBManagerStatePoweredOn) {
        g_scanning_requested = NO;
        [g_delegate.centralManager scanForPeripheralsWithServices:nil
                                                         options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @NO}];
        LOGI("BLE scan started");
    } else {
        g_scanning_requested = YES;
        LOGI("BLE adapter not ready (state=%ld), scan deferred", (long)g_delegate.centralManager.state);
    }
}

static void ios_ble_stop_scan(void)
{
    LOGI("ios_ble_stop_scan()");
    g_scanning_requested = NO;

    if (g_delegate && g_delegate.centralManager) {
        [g_delegate.centralManager stopScan];
    }
}

/* ---- Public API ---- */

/*
 * Set up the iOS BLE bridge. Called from Swift during initialisation.
 * Registers callbacks with the platform-agnostic dispatcher.
 */
void setup_ios_ble_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    ble_register_impl(ios_ble_check_adapter, ios_ble_start_scan, ios_ble_stop_scan);

    LOGI("iOS BLE bridge initialized");
}
