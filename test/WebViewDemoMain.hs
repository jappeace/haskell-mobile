{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the webview-demo test app.
--
-- Used by the emulator and simulator WebView integration tests.
-- Starts directly in webview-demo mode so no runtime switching is needed.
module Main where

import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , AppContext
  )
import HaskellMobile.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , WebViewConfig(..)
  , Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "WebView demo app registered"
  urlRef <- newIORef ("https://example.com" :: String)
  startMobileApp (webViewDemoApp urlRef)

-- | WebView demo: loads a URL and logs when page finishes loading.
-- A button switches to a second URL to test navigation.
webViewDemoApp :: IORef String -> MobileApp
webViewDemoApp urlRef = MobileApp
  { maContext = loggingMobileContext
  , maView    = webViewDemoView urlRef
  }

-- | Builds a Column with a WebView, a status label, and a URL-switch button.
webViewDemoView :: IORef String -> UserState -> IO Widget
webViewDemoView urlRef _userState = do
  currentUrl <- readIORef urlRef
  pure $ Column
    [ Text TextConfig { tcLabel = "WebView Demo", tcFontConfig = Nothing }
    , WebView WebViewConfig
        { wvUrl = pack currentUrl
        , wvOnPageLoad = Just (platformLog ("WebView page loaded: " <> pack currentUrl))
        }
    , Button ButtonConfig
        { bcLabel = "Load example.org"
        , bcAction = writeIORef urlRef "https://example.org"
        , bcFontConfig = Nothing
        }
    ]
