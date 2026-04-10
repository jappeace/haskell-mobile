#include "HaskellMobile.h"
#include "UIBridge.h"
#include "PermissionBridge.h"
#include "SecureStorageBridge.h"
#include "BleBridge.h"
#include "DialogBridge.h"
#include "LocationBridge.h"
#include "AuthSessionBridge.h"
#include "CameraBridge.h"
#include "BottomSheetBridge.h"
#include "HttpBridge.h"

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

/* iOS camera bridge setup — called from Swift during initialisation */
void setup_ios_camera_bridge(void *haskellCtx);
/* iOS bottom sheet bridge setup — called from Swift during initialisation */
void setup_ios_bottom_sheet_bridge(void *haskellCtx);

/* iOS HTTP bridge setup — called from Swift during initialisation */
void setup_ios_http_bridge(void *haskellCtx);
