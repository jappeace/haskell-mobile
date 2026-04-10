#include "HaskellMobile.h"
#include "UIBridge.h"
#include "PermissionBridge.h"
#include "SecureStorageBridge.h"
#include "BleBridge.h"
#include "DialogBridge.h"
#include "LocationBridge.h"
#include "AuthSessionBridge.h"

/* iOS UI bridge setup — called from Swift before haskellRenderUI */
void setup_ios_ui_bridge(void *viewController, void *haskellCtx);

/* iOS permission bridge setup — called from Swift during initialisation */
void setup_ios_permission_bridge(void *haskellCtx);

/* iOS secure storage bridge setup — called from Swift during initialisation */
void setup_ios_secure_storage_bridge(void *haskellCtx);

/* iOS BLE bridge setup — called from Swift during initialisation */
void setup_ios_ble_bridge(void *haskellCtx);

/* iOS dialog bridge setup — called from Swift during initialisation */
void setup_ios_dialog_bridge(void *haskellCtx);

/* iOS location bridge setup — called from Swift during initialisation */
void setup_ios_location_bridge(void *haskellCtx);

/* iOS auth session bridge setup — called from Swift during initialisation */
void setup_ios_auth_session_bridge(void *haskellCtx);
