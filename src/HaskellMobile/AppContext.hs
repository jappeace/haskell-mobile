-- | Internal context type that bundles a 'MobileContext' (user callbacks)
-- with a 'RenderState' (UI callback registry) and a 'PermissionState'
-- (permission callback registry). Passed through the C FFI as a single
-- 'StablePtr', eliminating the need for global mutable state.
module HaskellMobile.AppContext
  ( AppContext(..)
  , newAppContext
  , freeAppContext
  , derefAppContext
  )
where

import Data.IORef (writeIORef)
import Foreign.Ptr (Ptr, castPtr)
import Foreign.StablePtr (StablePtr, castPtrToStablePtr, castStablePtrToPtr, newStablePtr, deRefStablePtr, freeStablePtr)
import HaskellMobile.Lifecycle (MobileContext)
import HaskellMobile.Permission (PermissionState(..), newPermissionState)
import HaskellMobile.Render (RenderState, newRenderState)

-- | Combines user-supplied lifecycle callbacks with the rendering engine's
-- mutable state and the permission callback registry.
-- One of these is created per platform bridge session.
data AppContext = AppContext
  { acMobileContext    :: MobileContext
  , acRenderState      :: RenderState
  , acPermissionState  :: PermissionState
  }

-- | Create a fresh 'AppContext' from a 'MobileContext', allocating a new
-- 'RenderState' and 'PermissionState' internally. Returns a typed pointer
-- suitable for passing through the C FFI (C sees @void *@).
newAppContext :: MobileContext -> IO (Ptr AppContext)
newAppContext mobileContext = do
  renderState     <- newRenderState
  permissionState <- newPermissionState
  let appContext = AppContext
        { acMobileContext   = mobileContext
        , acRenderState     = renderState
        , acPermissionState = permissionState
        }
  ptr <- castPtr . castStablePtrToPtr <$> newStablePtr appContext
  -- Write the context pointer back so requestPermission can pass it to C.
  writeIORef (psContextPtr permissionState) (castPtr ptr)
  pure ptr

-- | Release a pointer previously created by 'newAppContext'.
freeAppContext :: Ptr AppContext -> IO ()
freeAppContext ptr = freeStablePtr (castPtrToStablePtr (castPtr ptr) :: StablePtr AppContext)

-- | Dereference a typed pointer back to an 'AppContext'.
derefAppContext :: Ptr AppContext -> IO AppContext
derefAppContext ptr = deRefStablePtr (castPtrToStablePtr (castPtr ptr))
