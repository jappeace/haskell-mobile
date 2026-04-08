import Foundation
import Security
import os.log

/// watchOS secure storage bridge — uses the Keychain via Security framework.
/// Provides @_cdecl wrappers callable from C for the platform-agnostic dispatcher.

private let bridgeLog = OSLog(subsystem: "me.jappie.haskellmobile", category: "SecureStorageBridge")
private let serviceName = "me.jappie.haskellmobile"

@_cdecl("watchos_secure_storage_write")
func watchosSecureStorageWrite(_ ctx: UnsafeMutableRawPointer?,
                                _ requestId: Int32,
                                _ key: UnsafePointer<CChar>?,
                                _ value: UnsafePointer<CChar>?) {
    guard let key = key, let value = value else {
        haskellOnSecureStorageResult(ctx, requestId, 2 /* ERROR */, nil)
        return
    }

    let keyStr = String(cString: key)
    let valueStr = String(cString: value)
    let valueData = valueStr.data(using: .utf8)!

    os_log("secure_storage_write(key=%{public}s, id=%d)", log: bridgeLog, type: .info, keyStr, requestId)

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: keyStr,
    ]
    let update: [String: Any] = [
        kSecValueData as String: valueData,
    ]

    var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

    if status == errSecItemNotFound {
        var addQuery = query
        addQuery[kSecValueData as String] = valueData
        status = SecItemAdd(addQuery as CFDictionary, nil)
    }

    if status == errSecSuccess {
        os_log("secure_storage_write: SUCCESS", log: bridgeLog, type: .info)
        haskellOnSecureStorageResult(ctx, requestId, 0 /* SUCCESS */, nil)
    } else {
        os_log("secure_storage_write: error %d", log: bridgeLog, type: .error, status)
        haskellOnSecureStorageResult(ctx, requestId, 2 /* ERROR */, nil)
    }
}

@_cdecl("watchos_secure_storage_read")
func watchosSecureStorageRead(_ ctx: UnsafeMutableRawPointer?,
                               _ requestId: Int32,
                               _ key: UnsafePointer<CChar>?) {
    guard let key = key else {
        haskellOnSecureStorageResult(ctx, requestId, 2 /* ERROR */, nil)
        return
    }

    let keyStr = String(cString: key)

    os_log("secure_storage_read(key=%{public}s, id=%d)", log: bridgeLog, type: .info, keyStr, requestId)

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: keyStr,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecSuccess, let data = result as? Data,
       let valueStr = String(data: data, encoding: .utf8) {
        os_log("secure_storage_read: SUCCESS value=%{public}s", log: bridgeLog, type: .info, valueStr)
        valueStr.withCString { cvalue in
            haskellOnSecureStorageResult(ctx, requestId, 0 /* SUCCESS */, cvalue)
        }
    } else if status == errSecItemNotFound {
        os_log("secure_storage_read: NOT_FOUND", log: bridgeLog, type: .info)
        haskellOnSecureStorageResult(ctx, requestId, 1 /* NOT_FOUND */, nil)
    } else {
        os_log("secure_storage_read: error %d", log: bridgeLog, type: .error, status)
        haskellOnSecureStorageResult(ctx, requestId, 2 /* ERROR */, nil)
    }
}

@_cdecl("watchos_secure_storage_delete")
func watchosSecureStorageDelete(_ ctx: UnsafeMutableRawPointer?,
                                 _ requestId: Int32,
                                 _ key: UnsafePointer<CChar>?) {
    guard let key = key else {
        haskellOnSecureStorageResult(ctx, requestId, 2 /* ERROR */, nil)
        return
    }

    let keyStr = String(cString: key)

    os_log("secure_storage_delete(key=%{public}s, id=%d)", log: bridgeLog, type: .info, keyStr, requestId)

    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: keyStr,
    ]

    let status = SecItemDelete(query as CFDictionary)

    if status == errSecSuccess || status == errSecItemNotFound {
        os_log("secure_storage_delete: SUCCESS", log: bridgeLog, type: .info)
        haskellOnSecureStorageResult(ctx, requestId, 0 /* SUCCESS */, nil)
    } else {
        os_log("secure_storage_delete: error %d", log: bridgeLog, type: .error, status)
        haskellOnSecureStorageResult(ctx, requestId, 2 /* ERROR */, nil)
    }
}
