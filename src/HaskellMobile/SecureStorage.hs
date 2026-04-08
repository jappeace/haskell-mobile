{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
-- | Secure key-value storage for mobile platforms.
--
-- Provides a callback-based API for writing, reading, and deleting
-- key-value pairs in platform-secure storage (Android SharedPreferences,
-- iOS/watchOS Keychain).  On desktop (no platform bridge registered)
-- an in-memory C stub provides basic functionality so that @cabal test@
-- exercises write/read round-trips without native code.
--
-- The callback registry follows the same sequential 'IORef' 'Int32'
-- pattern used by "HaskellMobile.Permission" and "HaskellMobile.Render".
module HaskellMobile.SecureStorage
  ( SecureStorageStatus(..)
  , SecureStorageState(..)
  , newSecureStorageState
  , storageStatusFromInt
  , secureStorageWrite
  , secureStorageRead
  , secureStorageDelete
  , dispatchSecureStorageResult
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)
import Data.Text qualified as Text
import Foreign.C.String (CString, withCString)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import System.IO (hPutStrLn, stderr)

-- | Result of a secure storage operation.
data SecureStorageStatus
  = StorageSuccess
  | StorageNotFound
  | StorageError
  deriving (Show, Eq, Ord, Enum, Bounded)

-- | Mutable state for the secure storage callback registry.
-- Holds separate callback maps for write, read, and delete operations
-- because read has a different callback signature (includes a value).
data SecureStorageState = SecureStorageState
  { ssWriteCallbacks  :: IORef (IntMap (SecureStorageStatus -> IO ()))
    -- ^ Map from requestId -> write result callback
  , ssReadCallbacks   :: IORef (IntMap (SecureStorageStatus -> Maybe Text -> IO ()))
    -- ^ Map from requestId -> read result callback (includes optional value)
  , ssDeleteCallbacks :: IORef (IntMap (SecureStorageStatus -> IO ()))
    -- ^ Map from requestId -> delete result callback
  , ssNextId          :: IORef Int32
    -- ^ Next available request ID (shared across all operation types)
  , ssContextPtr      :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'SecureStorageState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'ssContextPtr' before calling any storage operation.
newSecureStorageState :: IO SecureStorageState
newSecureStorageState = do
  writeCallbacks  <- newIORef IntMap.empty
  readCallbacks   <- newIORef IntMap.empty
  deleteCallbacks <- newIORef IntMap.empty
  nextId          <- newIORef 0
  contextPtr      <- newIORef nullPtr
  pure SecureStorageState
    { ssWriteCallbacks  = writeCallbacks
    , ssReadCallbacks   = readCallbacks
    , ssDeleteCallbacks = deleteCallbacks
    , ssNextId          = nextId
    , ssContextPtr      = contextPtr
    }

-- | Convert a C bridge status code to 'SecureStorageStatus'.
-- Returns 'Nothing' for unknown codes.
storageStatusFromInt :: CInt -> Maybe SecureStorageStatus
storageStatusFromInt 0 = Just StorageSuccess
storageStatusFromInt 1 = Just StorageNotFound
storageStatusFromInt 2 = Just StorageError
storageStatusFromInt _ = Nothing

-- | Write a key-value pair to secure storage.  Registers @callback@ and
-- calls the C bridge.  The callback fires when the platform responds
-- (or synchronously on desktop via the in-memory stub).
secureStorageWrite :: SecureStorageState -> Text -> Text -> (SecureStorageStatus -> IO ()) -> IO ()
secureStorageWrite storageState key value callback = do
  requestId <- readIORef (ssNextId storageState)
  modifyIORef' (ssWriteCallbacks storageState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (ssNextId storageState) (requestId + 1)
  ctx <- readIORef (ssContextPtr storageState)
  withCString (Text.unpack key) $ \cKey ->
    withCString (Text.unpack value) $ \cValue ->
      c_secureStorageWrite ctx (fromIntegral requestId) cKey cValue

-- | Read a value from secure storage by key.  Registers @callback@ and
-- calls the C bridge.  The callback receives the status and an optional
-- value ('Just' on success, 'Nothing' on not-found or error).
secureStorageRead :: SecureStorageState -> Text -> (SecureStorageStatus -> Maybe Text -> IO ()) -> IO ()
secureStorageRead storageState key callback = do
  requestId <- readIORef (ssNextId storageState)
  modifyIORef' (ssReadCallbacks storageState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (ssNextId storageState) (requestId + 1)
  ctx <- readIORef (ssContextPtr storageState)
  withCString (Text.unpack key) $ \cKey ->
    c_secureStorageRead ctx (fromIntegral requestId) cKey

-- | Delete a key from secure storage.  Registers @callback@ and calls
-- the C bridge.  The callback fires when the platform responds.
secureStorageDelete :: SecureStorageState -> Text -> (SecureStorageStatus -> IO ()) -> IO ()
secureStorageDelete storageState key callback = do
  requestId <- readIORef (ssNextId storageState)
  modifyIORef' (ssDeleteCallbacks storageState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (ssNextId storageState) (requestId + 1)
  ctx <- readIORef (ssContextPtr storageState)
  withCString (Text.unpack key) $ \cKey ->
    c_secureStorageDelete ctx (fromIntegral requestId) cKey

-- | Dispatch a secure storage result from the platform back to the
-- registered Haskell callback.  Tries write callbacks first, then read,
-- then delete.  Removes the callback after firing.
-- Unknown request IDs or status codes are silently logged to stderr.
dispatchSecureStorageResult :: SecureStorageState -> CInt -> CInt -> Maybe Text -> IO ()
dispatchSecureStorageResult storageState requestId statusCode maybeValue =
  case storageStatusFromInt statusCode of
    Nothing -> hPutStrLn stderr $
      "dispatchSecureStorageResult: unknown status code " ++ show statusCode
    Just status -> do
      let reqKey = fromIntegral requestId
      -- Try write callbacks
      writeCallbacks <- readIORef (ssWriteCallbacks storageState)
      case IntMap.lookup reqKey writeCallbacks of
        Just callback -> do
          modifyIORef' (ssWriteCallbacks storageState) (IntMap.delete reqKey)
          callback status
          return ()
        Nothing -> do
          -- Try read callbacks
          readCallbacks <- readIORef (ssReadCallbacks storageState)
          case IntMap.lookup reqKey readCallbacks of
            Just callback -> do
              modifyIORef' (ssReadCallbacks storageState) (IntMap.delete reqKey)
              callback status maybeValue
              return ()
            Nothing -> do
              -- Try delete callbacks
              deleteCallbacks <- readIORef (ssDeleteCallbacks storageState)
              case IntMap.lookup reqKey deleteCallbacks of
                Just callback -> do
                  modifyIORef' (ssDeleteCallbacks storageState) (IntMap.delete reqKey)
                  callback status
                  return ()
                Nothing -> hPutStrLn stderr $
                  "dispatchSecureStorageResult: unknown request ID " ++ show requestId

-- | FFI import: write a key-value pair via the C bridge.
foreign import ccall "secure_storage_write"
  c_secureStorageWrite :: Ptr () -> CInt -> CString -> CString -> IO ()

-- | FFI import: read a value via the C bridge.
foreign import ccall "secure_storage_read"
  c_secureStorageRead :: Ptr () -> CInt -> CString -> IO ()

-- | FFI import: delete a key via the C bridge.
foreign import ccall "secure_storage_delete"
  c_secureStorageDelete :: Ptr () -> CInt -> CString -> IO ()
