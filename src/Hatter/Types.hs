-- | Core types for the mobile app framework.
-- Separated from "Hatter" so that downstream modules
-- (e.g. "Hatter.App") can import 'MobileApp' without
-- creating an import cycle through the main facade.
module Hatter.Types
  ( MobileApp(..)
  , UserState(..)
  )
where

import Hatter.Action (ActionState)
import Hatter.Animation (AnimationState)
import Hatter.AuthSession (AuthSessionState)
import Hatter.Ble (BleState)
import Hatter.Camera (CameraState)
import Hatter.BottomSheet (BottomSheetState)
import Hatter.Dialog (DialogState)
import Hatter.Http (HttpState)
import Hatter.Lifecycle (MobileContext)
import Hatter.Location (LocationState)
import Hatter.NetworkStatus (NetworkStatusState)
import Hatter.Permission (PermissionState)
import Hatter.PlatformSignIn (PlatformSignInState)
import Hatter.SecureStorage (SecureStorageState)
import Hatter.Widget (Widget)

-- | State made available to the view function by the framework.
-- Contains handles to platform subsystems that the user's UI code
-- may need (e.g. requesting permissions).  Extended as the framework
-- gains new capabilities.
data UserState = UserState
  { userPermissionState    :: PermissionState
  , userSecureStorageState :: SecureStorageState
  , userBleState           :: BleState
  , userDialogState        :: DialogState
  , userLocationState      :: LocationState
  , userAuthSessionState   :: AuthSessionState
  , userCameraState        :: CameraState
  , userBottomSheetState   :: BottomSheetState
  , userHttpState              :: HttpState
  , userNetworkStatusState    :: NetworkStatusState
  , userAnimationState        :: AnimationState
  , userPlatformSignInState   :: PlatformSignInState
  }

-- | Application definition record. Downstream apps create one of these
-- and pass it to 'startMobileApp'.
data MobileApp = MobileApp
  { maContext     :: MobileContext
  , maView        :: UserState -> IO Widget
  , maActionState :: ActionState
    -- ^ Shared callback registry for 'Action' / 'OnChange' handles.
  }
