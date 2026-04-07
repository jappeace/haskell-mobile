{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
-- | Runtime permission management for mobile platforms.
--
-- Provides a callback-based API for requesting and checking dangerous
-- permissions at runtime.  On desktop (no platform bridge registered)
-- the C stub auto-grants every permission so that @cabal test@ works
-- without native code.
--
-- The callback registry follows the same sequential 'IORef' 'Int32'
-- pattern used by "HaskellMobile.Render".
module HaskellMobile.Permission
  ( Permission(..)
  , PermissionStatus(..)
  , PermissionState(..)
  , newPermissionState
  , permissionToInt
  , permissionStatusFromInt
  , requestPermission
  , checkPermission
  , dispatchPermissionResult
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Foreign.C.Types (CInt(..))
import System.IO (hPutStrLn, stderr)

-- | Dangerous permissions that require runtime consent on mobile.
data Permission
  = PermissionLocation
  | PermissionBluetooth
  | PermissionCamera
  | PermissionMicrophone
  | PermissionContacts
  | PermissionStorage
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Result of a permission request or check.
data PermissionStatus
  = PermissionGranted
  | PermissionDenied
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Mutable state for the permission callback registry.
-- Holds pending callbacks and the next request ID counter.
data PermissionState = PermissionState
  { psCallbacks :: IORef (IntMap (PermissionStatus -> IO ()))
    -- ^ Map from requestId -> result callback
  , psNextId    :: IORef Int32
    -- ^ Next available request ID
  }

-- | Create a fresh 'PermissionState' with no pending callbacks.
newPermissionState :: IO PermissionState
newPermissionState = do
  callbacks <- newIORef IntMap.empty
  nextId    <- newIORef 0
  pure PermissionState
    { psCallbacks = callbacks
    , psNextId    = nextId
    }

-- | Convert a 'Permission' to its C bridge integer code.
-- Must match the @PERMISSION_*@ constants in @PermissionBridge.h@.
permissionToInt :: Permission -> CInt
permissionToInt PermissionLocation   = 0
permissionToInt PermissionBluetooth  = 1
permissionToInt PermissionCamera     = 2
permissionToInt PermissionMicrophone = 3
permissionToInt PermissionContacts   = 4
permissionToInt PermissionStorage    = 5

-- | Convert a C bridge status code to 'PermissionStatus'.
-- Returns 'Nothing' for unknown codes.
permissionStatusFromInt :: CInt -> Maybe PermissionStatus
permissionStatusFromInt 0 = Just PermissionGranted
permissionStatusFromInt 1 = Just PermissionDenied
permissionStatusFromInt _ = Nothing

-- | Request a runtime permission.  Registers @callback@ and calls the
-- C bridge asynchronously.  The callback fires when the platform
-- responds (or synchronously on desktop via the auto-grant stub).
requestPermission :: PermissionState -> Permission -> (PermissionStatus -> IO ()) -> IO ()
requestPermission permissionState permission callback = do
  requestId <- readIORef (psNextId permissionState)
  modifyIORef' (psCallbacks permissionState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (psNextId permissionState) (requestId + 1)
  c_permissionRequest (permissionToInt permission) (fromIntegral requestId)

-- | Check whether a permission is currently granted (synchronous).
checkPermission :: Permission -> IO PermissionStatus
checkPermission permission = do
  result <- c_permissionCheck (permissionToInt permission)
  case permissionStatusFromInt result of
    Just status -> pure status
    Nothing     -> do
      hPutStrLn stderr $ "checkPermission: unknown status code " ++ show result
      pure PermissionDenied

-- | Dispatch a permission result from the platform back to the
-- registered Haskell callback.  Removes the callback after firing.
-- Unknown request IDs or status codes are silently logged to stderr.
dispatchPermissionResult :: PermissionState -> CInt -> CInt -> IO ()
dispatchPermissionResult permissionState requestId statusCode =
  case permissionStatusFromInt statusCode of
    Nothing -> hPutStrLn stderr $
      "dispatchPermissionResult: unknown status code " ++ show statusCode
    Just status -> do
      callbacks <- readIORef (psCallbacks permissionState)
      case IntMap.lookup (fromIntegral requestId) callbacks of
        Nothing -> hPutStrLn stderr $
          "dispatchPermissionResult: unknown request ID " ++ show requestId
        Just callback -> do
          modifyIORef' (psCallbacks permissionState) (IntMap.delete (fromIntegral requestId))
          callback status

-- | FFI import: request a permission via the C bridge.
foreign import ccall "permission_request"
  c_permissionRequest :: CInt -> CInt -> IO ()

-- | FFI import: check a permission via the C bridge.
foreign import ccall "permission_check"
  c_permissionCheck :: CInt -> IO CInt
