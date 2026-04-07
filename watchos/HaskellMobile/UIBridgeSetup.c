/*
 * watchOS UI bridge setup — registers Swift @_cdecl callbacks
 * with the platform-agnostic UIBridge dispatcher.
 *
 * The Swift functions (watchos_create_node, watchos_set_str_prop, etc.)
 * are defined via @_cdecl in WatchUIBridgeState.swift.
 */

#include "UIBridge.h"
#include <os/log.h>
#include <string.h>

/* Locale detection (cbits/locale.c) */
extern void setSystemLocale(const char *locale);

/* Log detected locale from Haskell (HaskellMobile.Locale) */
extern void haskellLogLocale(void);

/* Forward declarations of Swift @_cdecl functions */
extern int32_t watchos_create_node(int32_t nodeType);
extern void    watchos_set_str_prop(int32_t nodeId, int32_t propId, const char *value);
extern void    watchos_set_num_prop(int32_t nodeId, int32_t propId, double value);
extern void    watchos_set_handler(int32_t nodeId, int32_t eventType, int32_t callbackId);
extern void    watchos_add_child(int32_t parentId, int32_t childId);
extern void    watchos_remove_child(int32_t parentId, int32_t childId);
extern void    watchos_destroy_node(int32_t nodeId);
extern void    watchos_set_root(int32_t nodeId);
extern void    watchos_clear(void);

static UIBridgeCallbacks g_watchos_callbacks = {
    .createNode  = watchos_create_node,
    .setStrProp  = watchos_set_str_prop,
    .setNumProp  = watchos_set_num_prop,
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

    os_log_t log = os_log_create("me.jappie.haskellmobile", "UIBridge");
    os_log_info(log, "watchOS UI bridge initialized");

    /* Cache the system locale from NSLocale via Foundation.
     * On watchOS we default to "en" — the locale query is done
     * in Swift (HaskellBridge) if needed. */
    setSystemLocale("en");
    haskellLogLocale();
}
