{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the secure-storage-demo test app.
--
-- Used by the emulator and simulator secure storage integration tests.
-- Starts directly in secure-storage-demo mode so no runtime switching is needed.
module Main where

import Data.Text (pack)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , SecureStorageStatus(..)
  , runMobileApp
  , platformLog
  , secureStorageWrite
  , secureStorageRead
  , loggingMobileContext
  )
import HaskellMobile.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO ()
main = do
  runMobileApp secureStorageDemoApp
  platformLog "SecureStorage demo app registered"

-- | SecureStorage demo: writes and reads an OAuth token on button taps.
-- Used by integration tests to verify the secure storage FFI bridge end-to-end.
secureStorageDemoApp :: MobileApp
secureStorageDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = secureStorageDemoView
  }

-- | Builds a Column with a label, a "Store Token" button, and a "Read Token" button.
secureStorageDemoView :: UserState -> IO Widget
secureStorageDemoView userState = pure $ Column
  [ Text TextConfig { tcLabel = "SecureStorage Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel = "Store Token"
      , bcAction = secureStorageWrite (userSecureStorageState userState) "oauth_token" "test-token-12345" $ \status ->
          platformLog ("SecureStorage write result: " <> pack (show status))
      , bcFontConfig = Nothing
      }
  , Button ButtonConfig
      { bcLabel = "Read Token"
      , bcAction = secureStorageRead (userSecureStorageState userState) "oauth_token" $ \status maybeValue ->
          platformLog ("SecureStorage read result: " <> pack (show status) <> " value=" <> pack (show maybeValue))
      , bcFontConfig = Nothing
      }
  ]
