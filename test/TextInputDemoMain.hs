{-# LANGUAGE OverloadedStrings #-}
-- | Mobile entry point for the text-input-demo test app.
--
-- Used by the emulator and simulator TextInput integration tests.
-- Starts directly in text-input-demo mode so no runtime switching is needed.
module Main where

import Foreign.Ptr (Ptr)
import Hatter (startMobileApp, platformLog, loggingMobileContext, MobileApp(..), newActionState, runActionM, createOnChange, OnChange)
import Hatter.AppContext (AppContext)
import Hatter.Widget (InputType(..), TextConfig(..), TextInputConfig(..), Widget(..))

main :: IO (Ptr AppContext)
main = do
  platformLog "TextInput demo app registered"
  actionState <- newActionState
  (onWeightChange, onNameChange) <- runActionM actionState $ do
    wc <- createOnChange (\_ -> pure ())
    nc <- createOnChange (\_ -> pure ())
    pure (wc, nc)
  startMobileApp MobileApp
    { maContext     = loggingMobileContext
    , maView        = \_userState -> textInputDemoView onWeightChange onNameChange
    , maActionState = actionState
    }

-- | Builds a Column with a label and two TextInputs of different InputType.
textInputDemoView :: OnChange -> OnChange -> IO Widget
textInputDemoView onWeightChange onNameChange = pure $ Column
  [ Text TextConfig { tcLabel = "TextInput Demo", tcFontConfig = Nothing }
  , TextInput TextInputConfig
      { tiInputType  = InputNumber
      , tiHint       = "enter weight (kg)"
      , tiValue      = ""
      , tiOnChange   = onWeightChange
      , tiFontConfig = Nothing
      , tiAutoFocus  = True
      }
  , TextInput TextInputConfig
      { tiInputType  = InputText
      , tiHint       = "enter name"
      , tiValue      = ""
      , tiOnChange   = onNameChange
      , tiFontConfig = Nothing
      , tiAutoFocus  = False
      }
  ]
