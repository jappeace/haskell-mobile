{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the HTTP demo test app.
--
-- Used by the emulator and simulator HTTP integration tests.
-- On lifecycle Create, fires a GET request to a configurable URL
-- and logs the result via platformLog.
module Main where

import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , AppContext
  , HttpRequest(..)
  , HttpResponse(..)
  , HttpMethod(..)
  , HttpError(..)
  , performRequest
  )
import HaskellMobile.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "HTTP demo app registered"
  startMobileApp httpDemoApp

-- | HTTP demo: a button fires a GET request and logs the result.
httpDemoApp :: MobileApp
httpDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = httpDemoView
  }

-- | Builds a Column with a label and a "Send Request" button.
-- The button fires a GET request to http://localhost:8765/
httpDemoView :: UserState -> IO Widget
httpDemoView userState = do
  pure $ Column
    [ Text TextConfig { tcLabel = "HTTP Demo", tcFontConfig = Nothing }
    , Button ButtonConfig
        { bcLabel = "Send Request"
        , bcAction = performRequest
            (userHttpState userState)
            HttpRequest
              { hrMethod  = HttpGet
              , hrUrl     = "http://localhost:8765/"
              , hrHeaders = []
              , hrBody    = Nothing
              }
            (\result -> case result of
              Right response ->
                platformLog ("HTTP response: " <> pack (show (hrStatusCode response)))
              Left (HttpNetworkError errorMsg) ->
                platformLog ("HTTP error: " <> errorMsg)
              Left HttpTimeout ->
                platformLog "HTTP error: timeout"
            )
        , bcFontConfig = Nothing
        }
    ]
