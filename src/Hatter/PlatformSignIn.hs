{-# LANGUAGE ForeignFunctionInterface #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}
-- | Native platform sign-in API for mobile platforms.
--
-- Provides a callback-based API for starting sign-in flows using
-- platform-native identity providers:
--
--   * iOS\/watchOS: Sign in with Apple (@ASAuthorizationAppleIDProvider@)
--   * Android\/Wear OS: Google identity via @AccountManager@
--   * Desktop: stub returns fake credentials synchronously
--
-- The callback registry follows the same sequential 'IORef' 'Int32'
-- pattern used by "Hatter.AuthSession".
-- Single callback map (only one operation type).
module Hatter.PlatformSignIn
  ( SignInProvider(..)
  , SignInCredential(..)
  , SignInResult(..)
  , PlatformSignInState(..)
  , newPlatformSignInState
  , providerToInt
  , providerFromInt
  , signInResultFromInt
  , startPlatformSignIn
  , dispatchPlatformSignInResult
  )
where

import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Int (Int32)
import Data.IntMap.Strict (IntMap)
import Data.IntMap.Strict qualified as IntMap
import Data.Text (Text)
import Foreign.C.Types (CInt(..))
import Foreign.Ptr (Ptr, nullPtr)
import System.IO (hPutStrLn, stderr)

-- | Identity provider for platform sign-in.
data SignInProvider
  = AppleSignIn   -- ^ Sign in with Apple (iOS\/watchOS)
  | GoogleSignIn  -- ^ Google identity (Android\/Wear OS)
  deriving (Show, Eq)

-- | Credentials returned by a successful platform sign-in.
data SignInCredential = SignInCredential
  { sicIdentityToken :: Maybe Text
    -- ^ JWT (Apple) or OAuth2 access token (Google)
  , sicUserId        :: Text
    -- ^ Stable user ID from the provider
  , sicEmail         :: Maybe Text
    -- ^ Email address (may be relay address for Apple)
  , sicFullName      :: Maybe Text
    -- ^ Full name if provided by the user
  , sicProvider      :: SignInProvider
    -- ^ Which provider issued these credentials
  }
  deriving (Show, Eq)

-- | Result of a platform sign-in attempt.
data SignInResult
  = SignInSuccess SignInCredential  -- ^ Successful sign-in with credentials
  | SignInCancelled                 -- ^ User cancelled the sign-in
  | SignInError Text                -- ^ Platform-specific error message
  deriving (Show, Eq)

-- | Mutable state for the platform sign-in callback registry.
data PlatformSignInState = PlatformSignInState
  { psiCallbacks  :: IORef (IntMap (SignInResult -> IO ()))
    -- ^ Map from requestId -> sign-in result callback
  , psiNextId     :: IORef Int32
    -- ^ Next available request ID
  , psiContextPtr :: IORef (Ptr ())
    -- ^ Opaque context pointer passed to the C bridge.
    -- Set by 'AppContext.newAppContext' after the 'StablePtr' is created.
  }

-- | Create a fresh 'PlatformSignInState' with no pending callbacks.
-- The context pointer is initially null and must be set via
-- 'psiContextPtr' before calling 'startPlatformSignIn'.
newPlatformSignInState :: IO PlatformSignInState
newPlatformSignInState = do
  callbacks  <- newIORef IntMap.empty
  nextId     <- newIORef 0
  contextPtr <- newIORef nullPtr
  pure PlatformSignInState
    { psiCallbacks  = callbacks
    , psiNextId     = nextId
    , psiContextPtr = contextPtr
    }

-- | Convert a 'SignInProvider' to its C bridge integer code.
providerToInt :: SignInProvider -> CInt
providerToInt AppleSignIn  = 0
providerToInt GoogleSignIn = 1

-- | Convert a C bridge integer code to a 'SignInProvider'.
-- Returns 'Nothing' for unknown codes.
providerFromInt :: CInt -> Maybe SignInProvider
providerFromInt 0 = Just AppleSignIn
providerFromInt 1 = Just GoogleSignIn
providerFromInt _ = Nothing

-- | Convert C bridge status code and credential fields to 'SignInResult'.
-- Returns 'Nothing' for unknown status codes.
signInResultFromInt :: CInt -> Maybe Text -> Maybe Text -> Maybe Text -> Maybe Text -> CInt -> Maybe SignInResult
signInResultFromInt 0 maybeToken (Just userId) maybeEmail maybeFullName providerCode =
  case providerFromInt providerCode of
    Just provider -> Just $ SignInSuccess SignInCredential
      { sicIdentityToken = maybeToken
      , sicUserId        = userId
      , sicEmail         = maybeEmail
      , sicFullName      = maybeFullName
      , sicProvider      = provider
      }
    Nothing -> Nothing
signInResultFromInt 0 _ Nothing _ _ _ = Nothing
signInResultFromInt 1 _ _ _ _ _ = Just SignInCancelled
signInResultFromInt 2 _ _ _ (Just errorMsg) _ = Just (SignInError errorMsg)
signInResultFromInt 2 _ _ _ Nothing _ = Just (SignInError "")
signInResultFromInt _ _ _ _ _ _ = Nothing

-- | Start a platform sign-in flow. Registers @callback@ and calls
-- the C bridge. The callback fires when the sign-in completes
-- (or synchronously on desktop via the stub that returns fake credentials).
startPlatformSignIn :: PlatformSignInState -> SignInProvider -> (SignInResult -> IO ()) -> IO ()
startPlatformSignIn signInState provider callback = do
  requestId <- readIORef (psiNextId signInState)
  modifyIORef' (psiCallbacks signInState) (IntMap.insert (fromIntegral requestId) callback)
  writeIORef (psiNextId signInState) (requestId + 1)
  ctx <- readIORef (psiContextPtr signInState)
  c_platformSignInStart ctx (fromIntegral requestId) (providerToInt provider)

-- | Dispatch a platform sign-in result from the platform back to the
-- registered Haskell callback. Removes the callback after firing.
-- Unknown request IDs or status codes are silently logged to stderr.
dispatchPlatformSignInResult :: PlatformSignInState -> CInt -> CInt -> Maybe Text -> Maybe Text -> Maybe Text -> Maybe Text -> CInt -> IO ()
dispatchPlatformSignInResult signInState requestId statusCode maybeToken maybeUserId maybeEmail maybeFullName providerCode =
  case signInResultFromInt statusCode maybeToken maybeUserId maybeEmail maybeFullName providerCode of
    Nothing -> hPutStrLn stderr $
      "dispatchPlatformSignInResult: unknown status code " ++ show statusCode
    Just result -> do
      let reqKey = fromIntegral requestId
      callbacks <- readIORef (psiCallbacks signInState)
      case IntMap.lookup reqKey callbacks of
        Just callback -> do
          modifyIORef' (psiCallbacks signInState) (IntMap.delete reqKey)
          callback result
        Nothing -> hPutStrLn stderr $
          "dispatchPlatformSignInResult: unknown request ID " ++ show requestId

-- | FFI import: start a platform sign-in via the C bridge.
foreign import ccall "platform_sign_in_start"
  c_platformSignInStart :: Ptr () -> CInt -> CInt -> IO ()
