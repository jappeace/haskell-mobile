#include "HaskellMobile.h"
#include "UIBridge.h"
#include "PermissionBridge.h"

/* iOS UI bridge setup — called from Swift before haskellRenderUI */
void setup_ios_ui_bridge(void *viewController, void *haskellCtx);

/* iOS permission bridge setup — called from Swift during initialisation */
void setup_ios_permission_bridge(void *haskellCtx);
