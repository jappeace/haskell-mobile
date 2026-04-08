#include "HaskellMobile.h"
#include "UIBridge.h"
#include "PermissionBridge.h"
#include "SecureStorageBridge.h"

/* iOS UI bridge setup — called from Swift before haskellRenderUI */
void setup_ios_ui_bridge(void *viewController, void *haskellCtx);

/* iOS permission bridge setup — called from Swift during initialisation */
void setup_ios_permission_bridge(void *haskellCtx);

/* iOS secure storage bridge setup — called from Swift during initialisation */
void setup_ios_secure_storage_bridge(void *haskellCtx);
