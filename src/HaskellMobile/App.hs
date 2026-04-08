{-# LANGUAGE OverloadedStrings #-}
-- | Default implementation of the mobile app.
-- Provides 'loggingMobileContext' as the application context and a simple
-- counter demo as the default UI.
module HaskellMobile.App (mobileApp, scrollDemoApp, textInputDemoApp, imageDemoApp) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import Data.Text qualified as Text
import HaskellMobile.Types (MobileApp(..))
import HaskellMobile.Lifecycle (loggingMobileContext)
import HaskellMobile.Widget (ButtonConfig(..), Color(..), FontConfig(..), ImageConfig(..), ImageSource(..), InputType(..), ScaleType(..), TextAlignment(..), TextConfig(..), TextInputConfig(..), Widget(..), WidgetStyle(..))
import System.IO.Unsafe (unsafePerformIO)

-- | The default mobile app — logs every lifecycle event and shows a counter.
mobileApp :: MobileApp
mobileApp = MobileApp
  { maContext = loggingMobileContext
  , maView = \_userState ->counterView
  }

-- | Global counter state for the demo app.
counter :: IORef Int
counter = unsafePerformIO (newIORef 0)
{-# NOINLINE counter #-}

-- | Counter demo: displays current count with +/- buttons.
counterView :: IO Widget
counterView = do
  n <- readIORef counter
  pure $ Column
    [ Styled (WidgetStyle (Just 16.0) (Just AlignCenter) (Just (Color 255 0 0 255)) (Just (Color 0 255 0 255)))
        (Text TextConfig
          { tcLabel      = "Counter: " <> Text.pack (show n)
          , tcFontConfig = Just (FontConfig 24.0)
          })
    , Row [ Button ButtonConfig
              { bcLabel = "+", bcAction = modifyIORef' counter (+ 1), bcFontConfig = Nothing }
          , Button ButtonConfig
              { bcLabel = "-", bcAction = modifyIORef' counter (subtract 1), bcFontConfig = Nothing }
          ]
    ]

-- | Scroll demo: 20 text items + a button at the bottom inside a ScrollView.
-- Used by integration tests to verify the ScrollView FFI binding end-to-end.
scrollDemoApp :: MobileApp
scrollDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = \_userState ->scrollDemoView
  }

-- | Builds a ScrollView containing 20 text items followed by a button.
-- The button's callback ID is 0 (first registered), matching the --autotest dispatch.
scrollDemoView :: IO Widget
scrollDemoView = pure $ ScrollView
  [ Column
    ( map (\itemNumber -> Text TextConfig
        { tcLabel = "Item " <> Text.pack (show (itemNumber :: Int)), tcFontConfig = Nothing }) [1..20]
    ++ [Button ButtonConfig
        { bcLabel = "Reached Bottom", bcAction = pure (), bcFontConfig = Nothing }]
    )
  ]

-- | TextInput demo: renders numeric and text inputs side by side.
-- Used by integration tests to verify InputType FFI binding end-to-end.
textInputDemoApp :: MobileApp
textInputDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = \_userState ->textInputDemoView
  }

-- | Builds a Column with a label and two TextInputs of different InputType.
textInputDemoView :: IO Widget
textInputDemoView = pure $ Column
  [ Text TextConfig { tcLabel = "TextInput Demo", tcFontConfig = Nothing }
  , TextInput TextInputConfig
      { tiInputType  = InputNumber
      , tiHint       = "enter weight (kg)"
      , tiValue      = ""
      , tiOnChange   = \_ -> pure ()
      , tiFontConfig = Nothing
      }
  , TextInput TextInputConfig
      { tiInputType  = InputText
      , tiHint       = "enter name"
      , tiValue      = ""
      , tiOnChange   = \_ -> pure ()
      , tiFontConfig = Nothing
      }
  ]

-- | Image demo: displays images from all three source types.
-- Used by integration tests to verify Image FFI binding end-to-end.
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
      { icSource    = ImageResource "ic_launcher"
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
onePixelRedPng :: ByteString
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

