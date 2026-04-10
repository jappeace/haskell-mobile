{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the text-input-demo test app.
--
-- Used by the emulator and simulator TextInput integration tests.
-- Starts directly in text-input-demo mode so no runtime switching is needed.
module Main where

import Foreign.Ptr (Ptr)
import HaskellMobile (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), AppContext)
import HaskellMobile.Widget (InputType(..), TextConfig(..), TextInputConfig(..), User, Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "TextInput demo app registered"
  startMobileApp textInputDemoApp

-- | TextInput demo: renders numeric and text inputs side by side.
-- Used by integration tests to verify InputType FFI binding end-to-end.
textInputDemoApp :: MobileApp
textInputDemoApp = MobileApp
  { maContext = loggingMobileContext
  , maView    = \_userState -> textInputDemoView
  }

-- | Builds a Column with a label and two TextInputs of different InputType.
textInputDemoView :: IO (Widget User)
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
