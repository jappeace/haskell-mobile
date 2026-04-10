{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the camera-demo test app.
--
-- Used by the emulator and simulator camera integration tests.
-- Starts directly in camera-demo mode so no runtime switching is needed.
-- The desktop stub fires a synthetic capture result so the callback path
-- is verified without real camera hardware.
module Main where

import qualified Data.ByteString as BS
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , Action
  , CameraResult(..)
  , CameraStatus(..)
  , CameraState(..)
  , Picture(..)
  , startMobileApp
  , derefAppContext
  , platformLog
  , loggingMobileContext
  , AppContext
  , capturePhoto
  , newActionState
  , runActionM
  , createAction
  )
import HaskellMobile.AppContext (AppContext(..))
import HaskellMobile.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "Camera demo app registered"
  actionState <- newActionState
  cameraStateRef <- newIORef (Nothing :: Maybe CameraState)
  onCapturePhoto <- runActionM actionState $
    createAction $ do
      Just cameraState <- readIORef cameraStateRef
      capturePhoto cameraState $ \result -> case crStatus result of
        CameraSuccess -> case crPicture result of
          Just picture ->
            platformLog ("Camera success: " <> pack (show (BS.length (pictureData picture))) <> " bytes")
          Nothing ->
            platformLog "Camera success: no picture data"
        CameraCancelled ->
          platformLog "Camera cancelled"
        CameraPermissionDenied ->
          platformLog "Camera permission denied"
        CameraUnavailable ->
          platformLog "Camera unavailable"
        CameraError ->
          platformLog "Camera error"
  ctxPtr <- startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> cameraDemoView onCapturePhoto
    , maActionState = actionState
    }
  appCtx <- derefAppContext ctxPtr
  writeIORef cameraStateRef (Just (acCameraState appCtx))
  pure ctxPtr

-- | Builds a Column with a label and a "Capture Photo" button.
cameraDemoView :: Action -> IO Widget
cameraDemoView onCapturePhoto = pure $ Column
  [ Text TextConfig { tcLabel = "Camera Demo", tcFontConfig = Nothing }
  , Button ButtonConfig
      { bcLabel      = "Capture Photo"
      , bcAction     = onCapturePhoto
      , bcFontConfig = Nothing
      }
  ]
