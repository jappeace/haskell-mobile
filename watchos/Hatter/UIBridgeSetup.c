/*
 * watchOS UI bridge setup — registers Swift @_cdecl callbacks
 * with the platform-agnostic UIBridge dispatcher.
 *
 * The Swift functions (watchos_create_node, watchos_set_str_prop, etc.)
 * are defined via @_cdecl in WatchUIBridgeState.swift.
 */

#include "UIBridge.h"
#include "SecureStorageBridge.h"
#include "DialogBridge.h"
#include "AuthSessionBridge.h"
#include "BottomSheetBridge.h"
#include <os/log.h>
#include <string.h>

/* Locale detection (cbits/locale.c) */
extern void setSystemLocale(const char *locale);

/* Forward declarations of Swift @_cdecl functions */
extern int32_t watchos_create_node(int32_t nodeType);
extern void    watchos_set_str_prop(int32_t nodeId, int32_t propId, const char *value);
extern void    watchos_set_num_prop(int32_t nodeId, int32_t propId, double value);
extern void    watchos_set_image_data(int32_t nodeId, const uint8_t *data, int32_t length);
extern void    watchos_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId);
extern void    watchos_add_child(int32_t parentId, int32_t childId);
extern void    watchos_remove_child(int32_t parentId, int32_t childId);
extern void    watchos_destroy_node(int32_t nodeId);
extern void    watchos_set_root(int32_t nodeId);
extern void    watchos_clear(void);

/* Forward declarations of Swift @_cdecl secure storage functions */
extern void watchos_secure_storage_write(void *ctx, int32_t requestId,
                                          const char *key, const char *value);
extern void watchos_secure_storage_read(void *ctx, int32_t requestId,
                                         const char *key);
extern void watchos_secure_storage_delete(void *ctx, int32_t requestId,
                                           const char *key);

/* Forward declaration of Swift @_cdecl dialog function */
extern void watchos_dialog_show(void *ctx, int32_t requestId,
                                 const char *title, const char *message,
                                 const char *button1, const char *button2,
                                 const char *button3);

/* Forward declaration of Swift @_cdecl auth session function */
extern void watchos_auth_session_start(void *ctx, int32_t requestId,
                                        const char *authUrl,
                                        const char *callbackScheme);

/* Forward declaration of Swift @_cdecl bottom sheet function */
extern void watchos_bottom_sheet_show(void *ctx, int32_t requestId,
                                       const char *title, const char *items);

static UIBridgeCallbacks g_watchos_callbacks = {
    .createNode  = watchos_create_node,
    .setStrProp  = watchos_set_str_prop,
    .setNumProp  = watchos_set_num_prop,
    .setImageData = watchos_set_image_data,
    .setHandler  = watchos_set_handler,
    .addChild    = watchos_add_child,
    .removeChild = watchos_remove_child,
    .destroyNode = watchos_destroy_node,
    .setRoot     = watchos_set_root,
    .clear       = watchos_clear,
};

/*
 * Set up the watchOS UI bridge. Called from Swift before haskellRenderUI.
 * Registers callbacks with the platform-agnostic dispatcher.
 *
 * haskellCtx: opaque Haskell context pointer
 */
void setup_watchos_ui_bridge(void *haskellCtx)
{
    ui_register_callbacks(&g_watchos_callbacks);

    os_log_t log = os_log_create("me.jappie.hatter", "UIBridge");
    os_log_info(log, "watchOS UI bridge initialized");

    /* Register Swift secure storage callbacks with platform-agnostic dispatcher */
    secure_storage_register_impl(watchos_secure_storage_write,
                                  watchos_secure_storage_read,
                                  watchos_secure_storage_delete);
    os_log_info(log, "watchOS secure storage bridge initialized");

    /* Register Swift dialog callback with platform-agnostic dispatcher */
    dialog_register_impl(watchos_dialog_show);
    os_log_info(log, "watchOS dialog bridge initialized");

    /* Register Swift auth session callback with platform-agnostic dispatcher */
    auth_session_register_impl(watchos_auth_session_start);
    os_log_info(log, "watchOS auth session bridge initialized");

    /* Register Swift bottom sheet callback with platform-agnostic dispatcher */
    bottom_sheet_register_impl(watchos_bottom_sheet_show);
    os_log_info(log, "watchOS bottom sheet bridge initialized");
}
