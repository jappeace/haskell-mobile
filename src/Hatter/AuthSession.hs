{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
-- | OAuth2/PKCE authentication session API for mobile platforms.
--
-- Provides a callback-based API for starting authentication sessions
-- that open the system browser with an auth URL and receive a redirect
-- callback containing the auth code.
--
-- Platform implementations:
--   * Android: @Intent.ACTION_VIEW@ + intent filter for redirect scheme
--   * iOS: @ASWebAuthenticationSession@
--   * watchOS: @ASWebAuthenticationSession@
--   * Desktop: stub returns a fake redirect URL synchronously
--
-- The callback registry follows the same sequential 'IORef' 'Int32'
-- pattern used by "Hatter.Dialog".
-- Single callback map (only one operation type).
module Hatter.AuthSession
  ( AuthSessionResult(..)
  , AuthSessionState(..)
  , newAuthSessionState
  , authSessionResultFromInt
  , startAuthSession
  , dispatchAuthSessionResult
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

-- | Result of an authentication session.
data AuthSessionResult
  = AuthSessionSuccess Text   -- ^ Full redirect URL with query params
  | AuthSessionCancelled      -- ^ User cancelled the session
  | AuthSessionError Text     -- ^ Platform-specific error message
  deriving (Show, Eq)

-- | Mutable state for the auth session callback registry.
data AuthSessionState = AuthSessionState
  { asCallbacks  :: IORef (IntMap (AuthSessionResult -> IO ()))
    -- ^ Map from requestId -> auth session result callback
  , asNextId     :: IORef Int32
    -- ^ Next available request ID
  , asContextPtr :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'AuthSessionState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'asContextPtr' before calling 'startAuthSession'.
newAuthSessionState :: IO AuthSessionState
newAuthSessionState = do
  callbacks  <- newIORef IntMap.empty
  nextId     <- newIORef 0
  contextPtr <- newIORef nullPtr
  pure AuthSessionState
    { asCallbacks  = callbacks
    , asNextId     = nextId
    , asContextPtr = contextPtr
    }

-- | Convert a C bridge status code to 'AuthSessionResult'.
-- Returns 'Nothing' for unknown codes.
-- Requires the redirect URL or error message to construct the full result.
authSessionResultFromInt :: CInt -> Maybe Text -> Maybe Text -> Maybe AuthSessionResult
authSessionResultFromInt 0 (Just redirectUrl) _          = Just (AuthSessionSuccess redirectUrl)
authSessionResultFromInt 0 Nothing            _          = Just (AuthSessionSuccess "")
authSessionResultFromInt 1 _                  _          = Just AuthSessionCancelled
authSessionResultFromInt 2 _                  (Just err) = Just (AuthSessionError err)
authSessionResultFromInt 2 _                  Nothing    = Just (AuthSessionError "")
authSessionResultFromInt _ _                  _          = Nothing

-- | Start an authentication session. Opens the system browser with
-- @authUrl@ and waits for a redirect to @callbackScheme@.
-- Registers @callback@ and calls the C bridge. The callback fires
-- when the auth session completes (or synchronously on desktop via
-- the stub that returns a fake redirect URL).
startAuthSession :: AuthSessionState -> Text -> Text -> (AuthSessionResult -> IO ()) -> IO ()
startAuthSession authSessionState authUrl callbackScheme callback = do
  requestId <- readIORef (asNextId authSessionState)
  modifyIORef' (asCallbacks authSessionState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (asNextId authSessionState) (requestId + 1)
  ctx <- readIORef (asContextPtr authSessionState)
  withCString (Text.unpack authUrl) $ \cUrl ->
    withCString (Text.unpack callbackScheme) $ \cScheme ->
      c_authSessionStart ctx (fromIntegral requestId) cUrl cScheme

-- | Dispatch an auth session result from the platform back to the
-- registered Haskell callback. Removes the callback after firing.
-- Unknown request IDs or status codes are silently logged to stderr.
dispatchAuthSessionResult :: AuthSessionState -> CInt -> CInt -> Maybe Text -> Maybe Text -> IO ()
dispatchAuthSessionResult authSessionState requestId statusCode maybeRedirectUrl maybeErrorMsg =
  case authSessionResultFromInt statusCode maybeRedirectUrl maybeErrorMsg of
    Nothing -> hPutStrLn stderr $
      "dispatchAuthSessionResult: unknown status code " ++ show statusCode
    Just result -> do
      let reqKey = fromIntegral requestId
      callbacks <- readIORef (asCallbacks authSessionState)
      case IntMap.lookup reqKey callbacks of
        Just callback -> do
          modifyIORef' (asCallbacks authSessionState) (IntMap.delete reqKey)
          callback result
        Nothing -> hPutStrLn stderr $
          "dispatchAuthSessionResult: unknown request ID " ++ show requestId

-- | FFI import: start an auth session via the C bridge.
foreign import ccall "auth_session_start"
  c_authSessionStart :: Ptr () -> CInt -> CString -> CString -> IO ()
