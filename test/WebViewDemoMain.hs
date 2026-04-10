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
  , UserState
  , Action
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , AppContext
  , newActionState
  , runActionM
  , createAction
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
  actionState <- newActionState
  urlRef <- newIORef ("https://example.com" :: String)
  (onPageLoad, onLoadExampleOrg) <- runActionM actionState $ do
    pl <- createAction (do
      currentUrl <- readIORef urlRef
      platformLog ("WebView page loaded: " <> pack currentUrl))
    sw <- createAction (writeIORef urlRef "https://example.org")
    pure (pl, sw)
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = webViewDemoView urlRef onPageLoad onLoadExampleOrg
    , maActionState = actionState
    }

-- | Builds a Column with a WebView, a status label, and a URL-switch button.
webViewDemoView :: IORef String -> Action -> Action -> UserState -> IO Widget
webViewDemoView urlRef onPageLoad onLoadExampleOrg _userState = do
  currentUrl <- readIORef urlRef
  pure $ Column
    [ Text TextConfig { tcLabel = "WebView Demo", tcFontConfig = Nothing }
    , WebView WebViewConfig
        { wvUrl = pack currentUrl
        , wvOnPageLoad = Just onPageLoad
        }
    , Button ButtonConfig
        { bcLabel = "Load example.org"
        , bcAction = onLoadExampleOrg
        , bcFontConfig = Nothing
        }
    ]
