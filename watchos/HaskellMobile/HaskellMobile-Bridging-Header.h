#include "HaskellMobile.h"
#include "UIBridge.h"
#include "PermissionBridge.h"
#include "SecureStorageBridge.h"
#include "BleBridge.h"
#include "DialogBridge.h"
#include "LocationBridge.h"
#include "AuthSessionBridge.h"

/* Dispatch a text change event to Haskell.
 * Not declared in HaskellMobile.h but exported via foreign export ccall. */
void haskellOnUITextChange(void *ctx, int32_t callbackId, const char *text);

/* watchOS UI bridge setup — called from Swift before haskellRenderUI */
void setup_watchos_ui_bridge(void *haskellCtx);
