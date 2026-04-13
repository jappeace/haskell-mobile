{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the HTTP demo test app.
--
-- Used by the emulator and simulator HTTP integration tests.
-- On lifecycle Create, fires a GET request to a configurable URL
-- and logs the result via platformLog.
module Main where

import qualified Data.ByteString as BS
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
import Hatter.Http (HttpState(..), HttpRequest(..), HttpResponse(..), HttpMethod(..), HttpError(..), performRequest)
import Hatter.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "HTTP demo app registered"
  actionState <- newActionState
  httpStateRef <- newIORef (Nothing :: Maybe HttpState)
  onSendRequest <- runActionM actionState $
    createAction $ do
      Just httpState <- readIORef httpStateRef
      performRequest httpState
        HttpRequest
          { hrMethod  = HttpGet
          , hrUrl     = "http://localhost:8765/"
          , hrHeaders = []
          , hrBody    = BS.empty
          }
        (\result -> case result of
          Right response ->
            platformLog ("HTTP response: " <> pack (show (hrStatusCode response)))
          Left (HttpNetworkError errorMsg) ->
            platformLog ("HTTP error: " <> errorMsg)
          Left HttpTimeout ->
            platformLog "HTTP error: timeout"
        )
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> httpDemoView onSendRequest
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef httpStateRef (Just (acHttpState appCtx))
  pure ctxPtr

-- | Builds a Column with a label and a "Send Request" button.
-- The button fires a GET request to http://localhost:8765/
httpDemoView :: Action -> IO Widget
httpDemoView onSendRequest = do
  pure $ Column
    [ Text TextConfig { tcLabel = "HTTP Demo", tcFontConfig = Nothing }
    , Button ButtonConfig
        { bcLabel = "Send Request"
        , bcAction = onSendRequest
        , bcFontConfig = Nothing
        }
    ]
