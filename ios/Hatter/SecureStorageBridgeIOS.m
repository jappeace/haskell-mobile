/*
 * iOS implementation of the secure storage bridge callbacks.
 *
 * Uses the iOS Keychain (Security framework) for secure key-value storage.
 * Compiled by Xcode, not GHC.
 *
 * All functions run on the main thread.
 */

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <os/log.h>
#include "SecureStorageBridge.h"

#define LOG_TAG "SecureStorageBridge"
static os_log_t g_log;

#define LOGI(fmt, ...) os_log_info(g_log, fmt, ##__VA_ARGS__)
#define LOGE(fmt, ...) os_log_error(g_log, fmt, ##__VA_ARGS__)

static NSString * const kServiceName = @"me.jappie.hatter";

/* Haskell FFI export (dispatches result back to Haskell callback) */
extern void haskellOnSecureStorageResult(void *ctx, int32_t requestId,
                                          int32_t statusCode, const char *value);

/* ---- Secure storage implementations ---- */

static void ios_secure_storage_write(void *ctx, int32_t requestId,
                                      const char *key, const char *value)
{
    LOGI("secure_storage_write(key=\"%{public}s\", id=%d)", key, requestId);

    NSString *nsKey = [NSString stringWithUTF8String:key];
    NSData *nsValue = [[NSString stringWithUTF8String:value] dataUsingEncoding:NSUTF8StringEncoding];

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kServiceName,
        (__bridge id)kSecAttrAccount: nsKey,
    };

    /* Try to update first */
    NSDictionary *update = @{
        (__bridge id)kSecValueData: nsValue,
    };

    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                     (__bridge CFDictionaryRef)update);

    if (status == errSecItemNotFound) {
        /* Item doesn't exist, add it */
        NSMutableDictionary *addQuery = [query mutableCopy];
        addQuery[(__bridge id)kSecValueData] = nsValue;
        status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    }

    if (status == errSecSuccess) {
        LOGI("secure_storage_write: SUCCESS");
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_SUCCESS, NULL);
    } else {
        LOGE("secure_storage_write: error %d", (int)status);
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_ERROR, NULL);
    }
}

static void ios_secure_storage_read(void *ctx, int32_t requestId,
                                     const char *key)
{
    LOGI("secure_storage_read(key=\"%{public}s\", id=%d)", key, requestId);

    NSString *nsKey = [NSString stringWithUTF8String:key];

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kServiceName,
        (__bridge id)kSecAttrAccount: nsKey,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status == errSecSuccess && result != NULL) {
        NSData *data = (__bridge_transfer NSData *)result;
        NSString *valueStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        const char *cvalue = [valueStr UTF8String];
        LOGI("secure_storage_read: SUCCESS value=\"%{public}s\"", cvalue);
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_SUCCESS, cvalue);
    } else if (status == errSecItemNotFound) {
        LOGI("secure_storage_read: NOT_FOUND");
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_NOT_FOUND, NULL);
    } else {
        LOGE("secure_storage_read: error %d", (int)status);
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_ERROR, NULL);
    }
}

static void ios_secure_storage_delete(void *ctx, int32_t requestId,
                                       const char *key)
{
    LOGI("secure_storage_delete(key=\"%{public}s\", id=%d)", key, requestId);

    NSString *nsKey = [NSString stringWithUTF8String:key];

    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kServiceName,
        (__bridge id)kSecAttrAccount: nsKey,
    };

    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);

    if (status == errSecSuccess || status == errSecItemNotFound) {
        LOGI("secure_storage_delete: SUCCESS");
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_SUCCESS, NULL);
    } else {
        LOGE("secure_storage_delete: error %d", (int)status);
        haskellOnSecureStorageResult(ctx, requestId, SECURE_STORAGE_ERROR, NULL);
    }
}

/* ---- Public API ---- */

/*
 * Set up the iOS secure storage bridge. Called from Swift during initialisation.
 * Registers callbacks with the platform-agnostic dispatcher.
 */
void setup_ios_secure_storage_bridge(void *haskellCtx)
{
    g_log = os_log_create("me.jappie.hatter", LOG_TAG);

    secure_storage_register_impl(ios_secure_storage_write,
                                  ios_secure_storage_read,
                                  ios_secure_storage_delete);

    LOGI("iOS secure storage bridge initialized");
}
