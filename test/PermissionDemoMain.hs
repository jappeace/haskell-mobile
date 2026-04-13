{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the permission-demo test app.
--
-- Used by the emulator and simulator permission integration tests.
-- Starts directly in permission-demo mode so no runtime switching is needed.
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
import Hatter.Permission (Permission(..), PermissionState(..), requestPermission)
import Hatter.Widget (ButtonConfig(..), TextConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "Permission demo app registered"
  actionState <- newActionState
  permStateRef <- newIORef (Nothing :: Maybe PermissionState)
  onRequestCamera <- runActionM actionState $
    createAction $ do
      Just permState <- readIORef permStateRef
      requestPermission permState PermissionCamera $ \status ->
        platformLog ("Permission result: " <> pack (show status))
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> permissionDemoView onRequestCamera
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef permStateRef (Just (acPermissionState appCtx))
  pure ctxPtr

-- | Builds a Column with a label and a "Request Camera" button.
permissionDemoView :: Action -> IO Widget
permissionDemoView onRequestCamera = pure $ Column
  [ Text TextConfig { tcLabel = "Permission Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel      = "Request Camera"
      , bcAction     = onRequestCamera
      , bcFontConfig = Nothing
      }
  ]
