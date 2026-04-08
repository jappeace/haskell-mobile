{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the image-demo test app.
--
-- Used by the emulator and simulator Image integration tests.
-- Starts directly in image-demo mode so no runtime switching is needed.
module Main where

import Data.ByteString qualified as BS
import HaskellMobile (runMobileApp, platformLog, loggingMobileContext, MobileApp(..))
import HaskellMobile.Widget (ImageConfig(..), ImageSource(..), ResourceName(..), ScaleType(..), TextConfig(..), Widget(..))

main :: IO ()
main = do
  runMobileApp imageDemoApp
  platformLog "Image demo app registered"

-- | Image demo: displays images from all three source types.
-- Exercises every ImageSource constructor and every ScaleType variant.
imageDemoApp :: MobileApp
imageDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = \_userState -> imageDemoView
  }

-- | Builds a Column with a label and three Image widgets (resource, data, file).
imageDemoView :: IO Widget
imageDemoView = pure $ Column
  [ Text TextConfig { tcLabel = "Image Demo", tcFontConfig = Nothing }
  , Image ImageConfig
      { icSource    = ImageResource (ResourceName "ic_launcher")
      , icScaleType = ScaleFit
      }
  , Image ImageConfig
      { icSource    = ImageData onePixelRedPng
      , icScaleType = ScaleFill
      }
  , Image ImageConfig
      { icSource    = ImageFile "/nonexistent/test.png"
      , icScaleType = ScaleNone
      }
  ]

-- | A minimal 1x1 red PNG image (67 bytes).
-- Used for integration testing of the ImageData source path.
onePixelRedPng :: BS.ByteString
onePixelRedPng = BS.pack
  [ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A  -- PNG signature
  , 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52  -- IHDR chunk
  , 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01  -- 1x1
  , 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53  -- 8-bit RGB
  , 0xDE                                              -- IHDR CRC
  , 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54  -- IDAT chunk
  , 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00  -- zlib red pixel
  , 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33  -- IDAT CRC
  , 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44  -- IEND chunk
  , 0xAE, 0x42, 0x60, 0x82                           -- IEND CRC
  ]
