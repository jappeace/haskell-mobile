{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the secure-storage-demo test app.
--
-- Used by the emulator and simulator secure storage integration tests.
-- Starts directly in secure-storage-demo mode so no runtime switching is needed.
module Main where

import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import Hatter
  ( MobileApp(..)
  , Action
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , newActionState
  , runActionM
  , createAction
  )
import Hatter.AppContext (AppContext(..), derefAppContext)
import Hatter.SecureStorage (SecureStorageState(..), secureStorageWrite, secureStorageRead)
import Hatter.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  actionState <- newActionState
  ssRef <- newIORef (Nothing :: Maybe SecureStorageState)
  (onStoreToken, onReadToken) <- runActionM actionState $ do
    store <- createAction $ do
      Just secureStorageState <- readIORef ssRef
      secureStorageWrite secureStorageState "oauth_token" "test-token-12345" $ \status ->
        platformLog ("SecureStorage write result: " <> pack (show status))
    readTok <- createAction $ do
      Just secureStorageState <- readIORef ssRef
      secureStorageRead secureStorageState "oauth_token" $ \status maybeValue ->
        platformLog ("SecureStorage read result: " <> pack (show status) <> " value=" <> pack (show maybeValue))
    pure (store, readTok)
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> secureStorageDemoView onStoreToken onReadToken
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef ssRef (Just (acSecureStorageState appCtx))
  platformLog "SecureStorage demo app registered"
  pure ctxPtr

-- | Builds a Column with a label, a "Store Token" button, and a "Read Token" button.
secureStorageDemoView :: Action -> Action -> IO Widget
secureStorageDemoView onStoreToken onReadToken = pure $ Column
  [ Text TextConfig { tcLabel = "SecureStorage Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Store Token", bcAction = onStoreToken, bcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Read Token", bcAction = onReadToken, bcFontConfig = Nothing }
  ]
