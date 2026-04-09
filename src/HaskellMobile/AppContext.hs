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

import Data.IORef (IORef, newIORef, writeIORef)
import Foreign.Ptr (Ptr, castPtr)
import Foreign.StablePtr (StablePtr, castPtrToStablePtr, castStablePtrToPtr, newStablePtr, deRefStablePtr, freeStablePtr)
import HaskellMobile.Ble (BleState(..), newBleState)
import HaskellMobile.Lifecycle (MobileContext)
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
  , acViewFunction        :: IORef (UserState -> IO Widget)
  }

-- | Create a fresh 'AppContext' from a 'MobileApp', allocating a new
-- 'RenderState' and 'PermissionState' internally. Returns a typed pointer
-- suitable for passing through the C FFI (C sees @void *@).
newAppContext :: MobileApp -> IO (Ptr AppContext)
newAppContext mobileApp = do
  renderState        <- newRenderState
  permissionState    <- newPermissionState
  secureStorageState <- newSecureStorageState
  bleState           <- newBleState
  viewRef            <- newIORef (maView mobileApp)
  let appContext = AppContext
        { acMobileContext      = maContext mobileApp
        , acRenderState        = renderState
        , acPermissionState    = permissionState
        , acSecureStorageState = secureStorageState
        , acBleState           = bleState
        , acViewFunction       = viewRef
        }
  ptr <- castPtr . castStablePtrToPtr <$> newStablePtr appContext
  -- Write context pointers back so bridges can pass them to C.
  writeIORef (psContextPtr permissionState) (castPtr ptr)
  writeIORef (ssContextPtr secureStorageState) (castPtr ptr)
  writeIORef (blesContextPtr bleState) (castPtr ptr)
  pure ptr

-- | Release a pointer previously created by 'newAppContext'.
freeAppContext :: Ptr AppContext -> IO ()
freeAppContext ptr = freeStablePtr (castPtrToStablePtr (castPtr ptr) :: StablePtr AppContext)

-- | Dereference a typed pointer back to an 'AppContext'.
derefAppContext :: Ptr AppContext -> IO AppContext
derefAppContext ptr = deRefStablePtr (castPtrToStablePtr (castPtr ptr))
