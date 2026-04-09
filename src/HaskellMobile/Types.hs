-- | Core types for the mobile app framework.
-- Separated from "HaskellMobile" so that downstream modules
-- (e.g. "HaskellMobile.App") can import 'MobileApp' without
-- creating an import cycle through the main facade.
module HaskellMobile.Types
  ( MobileApp(..)
  , UserState(..)
  )
where

import HaskellMobile.Ble (BleState)
import HaskellMobile.Lifecycle (MobileContext)
import HaskellMobile.Permission (PermissionState)
import HaskellMobile.SecureStorage (SecureStorageState)
import HaskellMobile.Widget (Widget)

-- | State made available to the view function by the framework.
-- Contains handles to platform subsystems that the user's UI code
-- may need (e.g. requesting permissions).  Extended as the framework
-- gains new capabilities.
data UserState = UserState
  { userPermissionState    :: PermissionState
  , userSecureStorageState :: SecureStorageState
  , userBleState           :: BleState
  }

-- | Application definition record. Downstream apps create one of these
-- and pass it to 'startMobileApp'.
data MobileApp = MobileApp
  { maContext :: MobileContext
  , maView    :: UserState -> IO Widget
  }
