-- | Internal context type that bundles a 'MobileContext' (user callbacks)
-- with a 'RenderState' (UI callback registry), a 'PermissionState'
-- (permission callback registry), and the current view function.
-- Passed through the C FFI as a single 'StablePtr', eliminating the
-- need for global mutable state.
module HaskellMobile.AppContext
  ( AppContext(..)
  , newAppContext
  , freeAppContext
  , derefAppContext
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Foreign.Ptr (Ptr, castPtr)
import Foreign.StablePtr (StablePtr, castPtrToStablePtr, castStablePtrToPtr, newStablePtr, deRefStablePtr, freeStablePtr)
import HaskellMobile.Action (Action, ActionState, runActionM, createAction)
import HaskellMobile.Animation (AnimationState(..), newAnimationState)
import HaskellMobile.AuthSession (AuthSessionState(..), newAuthSessionState)
import HaskellMobile.Ble (BleState(..), newBleState)
import HaskellMobile.Camera (CameraState(..), newCameraState)
import HaskellMobile.BottomSheet (BottomSheetState(..), newBottomSheetState)
import HaskellMobile.Dialog (DialogState(..), newDialogState)
import HaskellMobile.Http (HttpState(..), newHttpState)
import HaskellMobile.Lifecycle (MobileContext)
import HaskellMobile.Location (LocationState(..), newLocationState)
import HaskellMobile.NetworkStatus (NetworkStatusState(..), newNetworkStatusState)
import HaskellMobile.Permission (PermissionState(..), newPermissionState)
import HaskellMobile.Render (RenderState, newRenderState)
import HaskellMobile.SecureStorage (SecureStorageState(..), newSecureStorageState)
import HaskellMobile.Types (MobileApp(..), UserState(..))
import HaskellMobile.Widget (Widget)

-- | Combines user-supplied lifecycle callbacks with the rendering engine's
-- mutable state, the permission callback registry, the secure storage
-- callback registry, and the current view function.
-- One of these is created per platform bridge session.
data AppContext = AppContext
  { acMobileContext       :: MobileContext
  , acRenderState         :: RenderState
  , acPermissionState     :: PermissionState
  , acSecureStorageState  :: SecureStorageState
  , acBleState            :: BleState
  , acDialogState         :: DialogState
  , acLocationState       :: LocationState
  , acAuthSessionState    :: AuthSessionState
  , acCameraState         :: CameraState
  , acBottomSheetState    :: BottomSheetState
  , acHttpState           :: HttpState
  , acNetworkStatusState  :: NetworkStatusState
  , acAnimationState      :: AnimationState
  , acViewFunction        :: IORef (UserState -> IO Widget)
  , acDismissAction       :: Action
    -- ^ Pre-registered dismiss action for the error widget.
  , acDismissRef          :: IORef (IO ())
    -- ^ Mutable slot written by the exception handler with the
    -- real dismiss logic. The 'acDismissAction' closure reads this.
  , acActionState         :: ActionState
    -- ^ Shared callback registry (from 'maActionState').
  }

-- | Create a fresh 'AppContext' from a 'MobileApp', allocating a new
-- 'RenderState' and 'PermissionState' internally. Returns a typed pointer
-- suitable for passing through the C FFI (C sees @void *@).
newAppContext :: MobileApp -> IO (Ptr AppContext)
newAppContext mobileApp = do
  let actionState = maActionState mobileApp
  animationState     <- newAnimationState
  renderState        <- newRenderState actionState animationState
  permissionState    <- newPermissionState
  secureStorageState <- newSecureStorageState
  bleState           <- newBleState
  dialogState        <- newDialogState
  locationState      <- newLocationState
  authSessionState   <- newAuthSessionState
  cameraState        <- newCameraState
  bottomSheetState   <- newBottomSheetState
  httpState          <- newHttpState
  networkStatusState <- newNetworkStatusState
  viewRef            <- newIORef (maView mobileApp)
  -- Pre-register a dismiss action that reads from an IORef.
  -- The real dismiss logic is written by handleException at exception time.
  dismissRef         <- newIORef (pure ())
  dismissAction      <- runActionM actionState
                           (createAction (do dismissIO <- readIORef dismissRef; dismissIO))
  let appContext = AppContext
        { acMobileContext      = maContext mobileApp
        , acRenderState        = renderState
        , acPermissionState    = permissionState
        , acSecureStorageState = secureStorageState
        , acBleState           = bleState
        , acDialogState        = dialogState
        , acLocationState      = locationState
        , acAuthSessionState   = authSessionState
        , acCameraState        = cameraState
        , acBottomSheetState   = bottomSheetState
        , acHttpState          = httpState
        , acNetworkStatusState = networkStatusState
        , acAnimationState     = animationState
        , acViewFunction       = viewRef
        , acDismissAction      = dismissAction
        , acDismissRef         = dismissRef
        , acActionState        = actionState
        }
  ptr <- castPtr . castStablePtrToPtr <$> newStablePtr appContext
  -- Write context pointers back so bridges can pass them to C.
  writeIORef (psContextPtr permissionState) (castPtr ptr)
  writeIORef (ssContextPtr secureStorageState) (castPtr ptr)
  writeIORef (blesContextPtr bleState) (castPtr ptr)
  writeIORef (dsContextPtr dialogState) (castPtr ptr)
  writeIORef (lsContextPtr locationState) (castPtr ptr)
  writeIORef (asContextPtr authSessionState) (castPtr ptr)
  writeIORef (csContextPtr cameraState) (castPtr ptr)
  writeIORef (bssContextPtr bottomSheetState) (castPtr ptr)
  writeIORef (hsContextPtr httpState) (castPtr ptr)
  writeIORef (nssContextPtr networkStatusState) (castPtr ptr)
  writeIORef (ansContextPtr animationState) (castPtr ptr)
  pure ptr

-- | Release a pointer previously created by 'newAppContext'.
freeAppContext :: Ptr AppContext -> IO ()
freeAppContext ptr = freeStablePtr (castPtrToStablePtr (castPtr ptr) :: StablePtr AppContext)

-- | Dereference a typed pointer back to an 'AppContext'.
derefAppContext :: Ptr AppContext -> IO AppContext
derefAppContext ptr = deRefStablePtr (castPtrToStablePtr (castPtr ptr))
