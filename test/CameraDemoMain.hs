{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the camera-demo test app.
--
-- Used by the emulator and simulator camera integration tests.
-- Starts directly in camera-demo mode so no runtime switching is needed.
-- The desktop stub fires a synthetic capture result so the callback path
-- is verified without real camera hardware.
module Main where

import qualified Data.ByteString as BS
import Data.Text (pack)
import Foreign.Ptr (Ptr)
import HaskellMobile
  ( MobileApp(..)
  , UserState(..)
  , startMobileApp
  , platformLog
  , loggingMobileContext
  , AppContext
  , CameraResult(..)
  , CameraStatus(..)
  , Picture(..)
  , capturePhoto
  )
import HaskellMobile.Widget
  ( ButtonConfig(..)
  , TextConfig(..)
  , Widget(..)
  )

main :: IO (Ptr AppContext)
main = do
  platformLog "Camera demo app registered"
  startMobileApp cameraDemoApp

-- | Camera demo: button captures a photo, logs the result.
cameraDemoApp :: MobileApp
cameraDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = cameraDemoView
  }

-- | Builds a Column with a label and a "Capture Photo" button.
-- The button captures a photo and logs the result.
cameraDemoView :: UserState -> IO Widget
cameraDemoView userState = do
  pure $ Column
    [ Text TextConfig { tcLabel = "Camera Demo", tcFontConfig = Nothing }
    , Button ButtonConfig
        { bcLabel = "Capture Photo"
        , bcAction = capturePhoto
            (userCameraState userState)
            (\result -> case crStatus result of
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
            )
        , bcFontConfig = Nothing
        }
    ]
